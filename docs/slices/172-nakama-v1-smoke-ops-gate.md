# Slice 172 - Nakama v1 smoke and operations gate

GitHub issue: #361

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Operators have one repeatable, fail-closed gate that validates the Nakama v1
deployment contract and, when explicitly pointed at a live endpoint, probes its
health/API surface without claiming unimplemented auth, Character, world-entry,
or gameplay bridge behavior.

## Scope and non-goals

In scope: manifest-backed required smoke stages, static compose/runbook/secrets
posture validation, optional live Nakama health/API probe, and durable pass/fail
output suitable for deployment evidence.

Out of scope: provisioning Nakama, storing credentials in the repo, automatic
matchmaking, custom admin UI, or pretending the later auth/Character/ticket/
bridge paths are live before their implementation slices land.

## Public seam

`scripts/check_nakama_v1_smoke.py` and `deploy/nakama-smoke-checks.json` are the
public operational seam. Static mode is safe in CI; `--live` requires an
explicit `PROJECT0_NAKAMA_SMOKE_URL` and performs only a bounded unauthenticated
health/API request.

## Falsifiable hypothesis

If the v1 smoke stages are declared in a versioned manifest and static/live
modes fail closed, then operators can distinguish deployment readiness from
future player-flow readiness without exposing secrets or accepting a false green
health signal.

## BDD

1. Given the repository and manifest are intact, when static mode runs, then all
   required v1 stages and private-surface/secret/runbook invariants are checked.
2. Given live mode lacks an explicit smoke URL, when it runs, then it fails
   closed without making a network request.
3. Given live mode receives a healthy configured Nakama endpoint, when it probes,
   then it reports the bounded endpoint result and retains the static stage list.
4. Given the endpoint is unreachable or malformed, when live mode runs, then it
   exits non-zero with a bounded diagnostic and never prints credentials.

## TDD / validation

The executable seam is covered by direct static-mode, compile, and fail-closed
live-mode checks. Static mode validates the manifest and deployment foundation;
live mode rejects missing configuration before making a request and bounds the
HTTP probe.

## Safety invariants

- The gate never reads or prints Nakama server keys, database passwords, or
  Console credentials.
- Live probing is opt-in and bounded by a short timeout.
- Static success does not claim player auth, Character, world-entry, or bridge
  implementation is complete.
- A malformed manifest or unsafe public admin binding fails closed.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/172-nakama-v1-smoke-ops-gate`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (first full-suite run)**: okami validation reported one unrelated
   client movement replication assertion failure (`held move_back`) with 840/844
   tests passing and 3 risky/pending tests.
- **Falsifiable hypothesis**: the failure was transient runtime/test timing
   noise, not caused by the Python smoke gate or documentation-only changes.
- **Discriminating check**: recreated the same okami temp tree from the exact
   branch and reran `scripts/run_gut_validation.sh` without changing code.
- **Confirmed root cause**: the rerun had no failures, with 844 tests and 2633
   asserts completing; the first failure was transient.
- **Why existing tests did not catch it earlier**: the existing movement harness
   is timing-sensitive and the first run's failure was nondeterministic.
- **Countermeasure**: require a clean rerun before treating a transient full
   suite failure as a Slice 172 regression; retain the failure evidence here.
- **Regression evidence**: second okami run passed with no failure excerpts.

## Validation evidence

Focused local validation: `python scripts/check_nakama_v1_smoke.py` — exit 0;
`python -m py_compile scripts/check_nakama_v1_smoke.py` — exit 0;
`python scripts/check_nakama_deployment_foundation.py` — exit 0; static
`--live` mode without `PROJECT0_NAKAMA_SMOKE_URL` — exit 1 with bounded missing
configuration message; record sync — exit 0, 0 errors and 6 pre-existing
warnings; `git diff --check` — clean.

SSH-on-okami validation on the retained temp tree: smoke gate and Python compile
passed; record sync passed; `bash scripts/run_gut_validation.sh` — exit 0,
**116 scripts, 844 tests, 2633 asserts**, 3 risky/pending tests and no
failures.