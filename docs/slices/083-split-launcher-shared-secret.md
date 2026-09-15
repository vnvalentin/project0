# Slice 083 — One-command split launcher with shared-secret management

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
and the [login-boundary decision](../../.scratch/container-platform/issues/02-account-login-service-boundary.md).
The split topology is deployable ([081](081-deploy-login-server-compose.md)) and
proven in containers ([082](082-containerized-login-split-e2e.md)), but running it
correctly requires a **shared non-empty `PROJECT0_ASSERTION_SECRET`** across both
processes — the one thing a bare `docker compose up` cannot manage. Without it,
each process falls back to an ephemeral per-boot key and the handoff silently
fails. This slice provides the launcher that closes that gap.

## Why not just flip the defaults

The remaining "cutover" is often framed as flipping `PROJECT0_CLIENT_LOGIN_SPLIT`
and `PROJECT0_GAME_ASSERTION_ONLY` on by default. Doing that unconditionally
would break the single-process source-run dev flow and the Windows tester guide
(the client would dial a login port with nothing listening; the game would refuse
account RPCs) and would silently fail whenever the two processes do not share a
secret. The safe, reversible cutover is operational: a first-class one-command
split launch with correct secret handling, leaving the code defaults opt-in so
single-process development keeps working.

## User outcome

An operator runs `deploy/game-server/run-split.sh up` and gets the full split
topology — login container (accounts authority) + game container (assertion-only)
— with a correctly shared assertion secret, reporting healthy when both are up.
`run-split.sh down` tears it down. The default `docker compose up` and all code
defaults are unchanged.

## Scope and non-goals

In scope:
- `deploy/game-server/run-split.sh`: require-or-generate a shared
  `PROJECT0_ASSERTION_SECRET`, bring up the base+split overlay under the
  `login-split` profile, wait for both containers healthy; `down` tears it down.

Out of scope: flipping any code env-var default (`PROJECT0_CLIENT_LOGIN_SPLIT`,
`PROJECT0_GAME_ASSERTION_ONLY`) — those stay opt-in so single-process dev and the
tester guide keep working; secret persistence/rotation policy (the operator pins
`PROJECT0_ASSERTION_SECRET` for durable sessions); production host provisioning.

## Public seam

- `deploy/game-server/run-split.sh` (`up`/`down`).

## Safety invariant

The launcher adds no default behavior: nothing about `docker compose up` or the
code defaults changes. It only orchestrates the already-proven split overlay with
a correctly shared secret, failing closed (non-zero exit) if either container is
not healthy in the wait window. Reversible: deleting the script restores the
prior state exactly.

## Validation

- On the Linux host: `bash -n deploy/game-server/run-split.sh` clean and the
  file is executable (git `+x`). `run-split.sh up` (data dirs pointed at temp
  paths) generated an ephemeral shared secret and brought both containers to
  Docker health `healthy` (exit 0); `scripts/login_handoff_client_harness.gd`
  against the published ports (login 19998, game 19999) reported
  `session_established: ok` and **`world_entry: ok`** with
  `world_character_name: "Handoff Hero"`; `run-split.sh down` stopped and removed
  the topology cleanly.
- `scripts/run_gut_validation.sh` on Linux — passed, 58/58 scripts, exit 0
  (unaffected; no GDScript changed).
- `scripts/check_record_sync.sh` exit 0.

## Root-cause learning

None. No unexpected failure surfaced during delivery.
