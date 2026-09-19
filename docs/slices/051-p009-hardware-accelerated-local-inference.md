# Slice 051 — Hardware-accelerated local inference (P-009)
GitHub issue: #95

Status: **delivered**

Phase: 8 (JIT world generation and local inference), advancing P-009.

## User outcome

The server-side LLM client resolves its Ollama host/model/timeout from
environment configuration (falling back to the existing local Tesla P100 /
`llama3:latest` defaults) with no cloud dependency, classifies every
`generate_json()` call into a bounded outcome with non-sensitive telemetry, and
the repository proves structurally that the game client never contacts Ollama.

## Scope and non-goals

In scope:
- `LocalLLMClient.resolve_config()`: a static, pure resolver reading
  `PROJECT0_OLLAMA_HOST`, `PROJECT0_OLLAMA_MODEL`, `PROJECT0_OLLAMA_TIMEOUT_SEC`
  with the existing defaults as fallback; non-finite/`<= 0` timeout falls back
  to the default.
- `LocalLLMClient.configure_from_env()`: an explicit opt-in the server boot
  path may call after `.new()` and before the node enters the tree, applying
  env values only to exports the caller has not already set. Existing callers
  (`SectorBlueprintService`, `ProvisionalSectorGenerator`) that assign
  `ollama_host`/`model_name`/`request_timeout_sec` directly are unaffected
  because they never call it.
- A bounded `request_outcome` enum (`success`, `http_error`,
  `malformed_envelope`, `invalid_json`, `transport_error`, `timeout`) added to
  the existing `generate_json()` result Dictionary alongside a `duration_ms`
  field, and a new `request_outcome_reported(telemetry: Dictionary)` signal
  carrying only `{outcome, response_code, duration_ms, model, host}` — no
  prompt text, no raw model body, no secrets, per CLAUDE.md's Telemetry and
  Andon Signals section.
- Hermetic GUT coverage using `scripts/fake_ollama_http_server.gd` for every
  outcome, plus a structural test proving no file under `client/` references
  `local_llm_client`, `LocalLLMClient`, or the Ollama port.

Out of scope: boot wiring of town/sector generation (Slice 052 / F-026), new
prompt content, geometry, SQLite/Canon, retries beyond the existing single
bounded `HTTPRequest` timeout, and any change to `client/` code or the
network/authority model. No GPU/driver code is added; hardware use is
evidenced by a live probe run, not new code.

## Public seam

`shared/local_llm_client.gd`: existing `generate_json(prompt)` behavior and
result keys (`success`, `data`, `raw`, `error`) are preserved; `outcome` and
`duration_ms` are additive result keys. New static `resolve_config()` and
instance `configure_from_env()`. New `request_outcome_reported` signal.

## Safety invariant

Telemetry payloads never carry prompt text, raw model output, or request
bodies — only bounded enum/numeric/identifier fields. The client process tree
has no reference to the Ollama client or its default port, which the
structural test enforces by scanning `client/` at test time.

## BDD / TDD

- `tests/unit/test_local_llm_client_config.gd`: env-driven `resolve_config()`
  defaults, overrides, and invalid-timeout fallback; `configure_from_env()`
  leaves explicitly-set exports untouched.
- `tests/integration/test_local_llm_client_telemetry.gd`: fake-Ollama-backed
  coverage of `success`, `http_error`, `malformed_envelope`, `invalid_json`,
  and `timeout` outcomes, asserting `duration_ms >= 0` and telemetry field
  shape via the `request_outcome_reported` signal.
- `tests/integration/test_client_never_contacts_ollama.gd`: structural scan of
  `client/` for forbidden references.

## ADR rationale

No new ADR. Server-only LLM access, bounded telemetry without sensitive
payloads, and env-driven server configuration are already normative in
`CLAUDE.md` ("The LLM proposes; it never authorizes", "Telemetry And Andon
Signals", Runtime Ownership) and consistent with the existing Slice 008
request seam.

## Validation

Focused unit validation: `test_local_llm_client_config.gd` passed 5/5 tests,
16 assertions, exit 0. Focused integration validation:
`test_local_llm_client_telemetry.gd` passed 5/5 tests, 50 assertions, exit 0;
`test_client_never_contacts_ollama.gd` passed 1/1 test, 2 assertions, exit 0.
Broader focused runs: full `tests/unit` passed 193/193 tests across 24 scripts
and 714 assertions, exit 0; full `tests/integration` passed 111/111 tests
across 19 scripts and 468 assertions, exit 0 (including the pre-existing
sector blueprint contract, provisional sector generation, and town layout
provider suites unchanged).

Full suite: `scripts/run_gut_validation.sh` passed 304/304 tests across 43/43
scripts and 1182 assertions, exit 0; `build/validation/gut.xml` and
`validation-summary.json` were emitted (`scripts_expected == scripts_ran ==
43`).

Record sync: `scripts/check_record_sync.sh` exited 0 with the same 6
pre-existing warnings noted in Slice 047 (unrelated slice records with no
named feature) and 0 errors.

Live hardware-inference evidence (2026-09-14): `godot --headless -s
scripts/probe_ollama.gd` against the locally running Ollama instance serving
`llama3:latest` on the Tesla P100 returned a successful parsed JSON dungeon
blueprint (`start_room`, `tiles`, `quest_item` fields), proving
`LocalLLMClient.generate_json()` completes a real local model round trip with
no cloud dependency.
