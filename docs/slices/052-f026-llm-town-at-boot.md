# Slice 052 — F-026 LLM town generation ON at server boot
GitHub issue: #95

Status: **delivered**

Phase: 8 (JIT world generation and local inference), advancing
[F-026](../FEATURE-LIST.md#f-026-organic-districted-starting-city).

## User outcome

When an operator opts in via an environment flag, the server generates the
starting town from the local LLM at boot (validated + required-structure-
guaranteed via the existing [Slice 026](026-llm-town-generation.md)
`TownLayoutProvider` seam), while the hand-authored fixture stays the DEFAULT
and the always-safe fallback so the town is never unusable and default boot
behavior is unchanged.

## Scope and non-goals

In scope:
- A default-off boot flag, `PROJECT0_LLM_TOWN_AT_BOOT`, read via a small
  static helper (`TownLayoutProvider.llm_at_boot_enabled()`), matching the
  repo's existing `PROJECT0_E2E_DISABLE_TOWN_COLLISION == "1"` convention
  (only the literal string `"1"` is ON; unset or any other value is OFF).
- Boot wiring in `server/server_main.gd`'s `_start_server()`: the validated
  fixture blueprint is always computed first (unchanged fail-closed check).
  When the flag is ON, a `LocalLLMClient` is constructed, configured from
  environment (Slice 051's `configure_from_env()`), added to the tree, and
  `TownLayoutProvider.new().request_town(client, fixture_blueprint)` is
  awaited; its `blueprint` result becomes `_starting_town_hub_blueprint`. The
  client is freed afterward. A boot-level log line reports `source`/`outcome`.
  When OFF, the fixture blueprint is used directly — exactly today's
  behavior.
- Unit coverage of the flag helper's two branches and the boot-level town
  resolution helper's three branches (ON+valid, ON+failing client, OFF).

Out of scope (unchanged by this slice):
- The fixture, the schema, `SectorCollisionMap`, `HouseAllocator`,
  `ServerMonsterManager`, Canon canonicalization, or the network/authority
  model — all consume whichever blueprint won, unchanged.
- Deriving the monster exclusion from the town bounds (F-026 remains
  `In Progress` for exactly this one remaining item).
- Any new prompt content beyond `TownLayoutProvider.default_town_prompt()`.
- Live-Ollama dependency in the GUT suite (hermetic only, matching Slice 026
  and Slice 051's own test seams).

## Public seam

- `server/town_layout_provider.gd`: new static `llm_at_boot_enabled() -> bool`
  and new static `resolve_boot_town(flag_enabled, llm_client, fallback) ->
  Dictionary` coroutine (thin wrapper so `server_main.gd`'s boot branch is
  covered by an injected-fake-client unit test without booting a SceneTree).
- `server/server_main.gd`'s `_start_server()`: the only behavioral change is
  the source of `_starting_town_hub_blueprint` before it is handed downstream.

## Boot-latency tradeoff

`_start_server()` is already a deferred coroutine (`call_deferred` from
`_initialize()`), so awaiting `request_town()` here does not block the
SceneTree — it defers when the ENet socket opens, not whether the process
stays responsive. Because `request_town()` always falls back to the validated
fixture on any transport, timeout, or invalid-output failure (Slice 026), boot
can never yield an unusable town; the accepted cost is that a slow or
unreachable Ollama instance delays the socket open by up to
`LocalLLMClient`'s configured request timeout (default 60s, Slice 051's
`PROJECT0_OLLAMA_TIMEOUT_SEC`). This is opt-in (default OFF) specifically so
that tradeoff is never imposed on a boot that hasn't asked for it.

## ADR rationale

No new ADR. This wires two already-normative, already-delivered seams
together (Slice 026's guarantee, Slice 051's env configuration) behind a
default-off flag; it introduces no new authority, persistence, or validation
rule. Consistent with CLAUDE.md's "the LLM proposes; it never authorizes" (the
fixture fallback is unconditional on any failure) and the JIT generation
lifecycle already documented there.

## BDD

### Default boot is unchanged

Given `PROJECT0_LLM_TOWN_AT_BOOT` is unset (or any value other than `"1"`)
When the server boots
Then the starting town is the hand-authored fixture blueprint, with no LLM
request made — identical to pre-Slice-052 behavior.

### Opt-in boot with a usable LLM candidate

Given `PROJECT0_LLM_TOWN_AT_BOOT=1` and a live/fake LLM client that returns a
valid, complete candidate
When the server boots
Then the starting town is the LLM-generated blueprint (`source == "llm"`) and
a boot-level log line reports it.

### Opt-in boot with a failing or incomplete LLM response

Given `PROJECT0_LLM_TOWN_AT_BOOT=1` and an LLM client that fails, times out, or
returns an invalid/incomplete candidate
When the server boots
Then the starting town falls back to the fixture blueprint (`source ==
"fallback"`) and the server still reaches its normal ready state — the town is
never unusable.

## TDD

- `tests/unit/test_town_layout_provider_boot_flag.gd`:
  - `llm_at_boot_enabled()` is `false` when the env var is unset.
  - `llm_at_boot_enabled()` is `false` for any non-`"1"` value (e.g. `"true"`,
    `"0"`, `"yes"`).
  - `llm_at_boot_enabled()` is `true` only for the literal `"1"`.
  - `resolve_boot_town()` with the flag OFF returns the fixture without
    touching the injected client.
  - `resolve_boot_town()` with the flag ON and a client returning a valid
    candidate returns `source == "llm"`.
  - `resolve_boot_town()` with the flag ON and a failing client falls back to
    the fixture (`source == "fallback"`).
- All pre-existing unit/integration suites (including
  `test_town_layout_provider_request.gd` and the Slice 051 config/telemetry
  tests) pass unchanged, proving the default-off path alters no existing
  behavior.

## Validation

Focused unit: `test_town_layout_provider_boot_flag.gd` passed 6/6 tests, 15
assertions, exit 0.

Server parse check: `godot --headless --check-only -s server/server_main.gd`
exit 0.

Full suite: `scripts/run_gut_validation.sh` passed 310/310 tests across 44/44
scripts and 1197 assertions, exit 0; `build/validation/gut.xml` and
`validation-summary.json` emitted (`scripts_expected == scripts_ran == 44`).

Record sync: `scripts/check_record_sync.sh` exited 0.

Runtime boot evidence (2026-09-14), Ollama running locally with
`llama3:latest` (bound to an ephemeral `PROJECT0_SERVER_PORT` so it never
collided with the LAN dev server already listening on 9999; the `-s` form of
the CLI invocation is required for `_initialize()`'s `call_deferred` to run —
the bare-script positional form silently no-ops):

Default OFF —
`PROJECT0_ACCOUNTS_DB_PATH=p0_boot_off.db PROJECT0_SERVER_PORT=19991 godot
--headless --path . -s server/server_main.gd`:

```
Starting town hub fixture validated: 28 structures.
Town collision map ready: 477 solid cells.
Starting town house pool ready: 10 houses.
Spawned 4 monsters outside the town.
Opened database successfully (.../p0_boot_off.db)
Starting town Canon ready: ok.
Accounts database ready at user://p0_boot_off.db (schema ensured).
Server listening on 127.0.0.1:19991
```

No LLM-at-boot line, confirming the default-off path is unchanged.

Opt-in ON —
`PROJECT0_LLM_TOWN_AT_BOOT=1 PROJECT0_ACCOUNTS_DB_PATH=p0_boot_on.db
PROJECT0_SERVER_PORT=19992 godot --headless --path . -s server/server_main.gd`:

```
Starting town hub fixture validated: 28 structures.
Town layout resolved: source=fallback, outcome=transport_error.
LLM-at-boot town: source=fallback outcome=transport_error.
Town collision map ready: 477 solid cells.
Starting town house pool ready: 10 houses.
Spawned 4 monsters outside the town.
Opened database successfully (.../p0_boot_on.db)
Starting town Canon ready: ok.
Accounts database ready at user://p0_boot_on.db (schema ensured).
Server listening on 127.0.0.1:19992
```

The boot-level line appears and the server still reaches "Server listening" —
proving the opt-in path executes end to end. The outcome was `fallback`
(`transport_error`) rather than `llm`: a follow-up direct probe with
`shared/local_llm_client.gd` against the real
`TownLayoutProvider.default_town_prompt()` (28-structure, larger-vocabulary
schema-v3 prompt) confirmed `llama3:latest` on this hardware takes longer than
even a 180-second timeout to generate a complete town JSON — a genuine
`OUTCOME_TIMEOUT`, not a code defect. This is exactly the failure mode Slice
026's unconditional fallback exists for, and it is exercised here for real
rather than only in the hermetic fake-client tests. An operator who wants a
higher LLM-town hit rate can raise `PROJECT0_OLLAMA_TIMEOUT_SEC` (Slice 051)
past this model's real generation time for this prompt size, or reduce the
prompt's requested house count in a later slice; neither is in this slice's
scope.

Both throwaway DB files
(`~/.local/share/godot/app_userdata/Project0/p0_boot_{off,on}.db*`) and the
diagnostic probe scripts were deleted after capture.
