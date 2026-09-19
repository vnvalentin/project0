# Slice 071 — Shared assertion secret across the game + login units
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md)
(signed assertions issued by the login process are validated by the game
process). Seventeenth delivery of the [container-platform map](../../.scratch/container-platform/map.md);
it is the **prerequisite for the client cutover** (Slice 072): the login
process's issuer and the game process's validator must share one HMAC secret, or
the game server silently rejects every login assertion.

## User outcome

An operator can configure one shared assertion secret that both the game server
and the login server load, so assertions minted by the login process validate on
the game process. Boot logs state clearly whether a configured (shared) secret
or an ephemeral per-boot key is in use, so a missing shared secret is obvious
rather than a silent handoff failure.

## Scope and non-goals

In scope:
- Both systemd units (`scripts/project0-server.service`,
  `scripts/project0-login.service`) load a shared
  `EnvironmentFile=-/etc/project0/assertion.env`.
- `scripts/assertion.env.example`: a template documenting
  `PROJECT0_ASSERTION_SECRET` (32 random bytes hex) and that BOTH units must load
  the same file.
- `LoginRuntime.resolve_assertion_secret()` reports its source (`configured` vs
  `ephemeral`) via a pure, unit-tested helper.

Out of scope (later sub-slices): the client connection-UX cutover that actually
presents login assertions to the game server (Slice 072); a fail-closed
"require secret" mode; secret rotation; moving the secret into a secrets manager.
This slice only guarantees the two processes can be configured with one secret
and makes the in-use source observable.

## Public seam

- `server/login_runtime.gd` (`resolve_assertion_secret()`,
  `resolve_assertion_secret_details(raw)`).
- `scripts/project0-server.service`, `scripts/project0-login.service`,
  `scripts/assertion.env.example`.

## Safety invariant

The secret is never hardcoded or logged: only its source (`configured` /
`ephemeral`) is printed, never the value. The `EnvironmentFile` is optional
(`-`) so bring-up still works with a per-boot ephemeral key; production sets the
shared file. The pure resolver trims a configured value and, only when empty,
generates a fresh 32-byte key — it never returns a short or malformed secret.

## ADR rationale

No new ADR. A shared HMAC secret between the issuing login process and the
validating game process is exactly what the login-boundary decision's signed
assertions require; this makes that configuration explicit and observable.

## BDD / TDD

`tests/unit/test_assertion_secret_resolution.gd`: a configured raw value
(including surrounding whitespace) resolves to `source == "configured"` with the
trimmed secret; an empty/whitespace value resolves to `source == "ephemeral"`
with a 64-hex-character key; two ephemeral resolutions differ. The full GUT suite
proves the entrypoints still boot.

## Validation

- Focused + full suite: `scripts/run_gut_validation.sh` on the Linux host —
  **passed, 53/53 scripts, exit 0** (+1 new
  `tests/unit/test_assertion_secret_resolution.gd`).
- `scripts/check_record_sync.sh` exit 0 (6 pre-existing WARN).

## Root-cause learning

None yet.
