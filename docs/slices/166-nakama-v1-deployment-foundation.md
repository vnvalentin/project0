# Slice 166 - Nakama v1 deployment foundation

GitHub issue: #355

Status: **delivered**

Phase: 12 (Authoritative runtime and action input)

Feature: [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation)

## User outcome

Project0 operators have a safe, repeatable foundation for adding Nakama to the
existing Docker deployment before any player auth, Character, or realtime bridge
code depends on it.

## Scope and non-goals

In scope: a single-node Nakama plus PostgreSQL compose foundation, private
admin/console/metrics posture, host-side secret/config locations, PostgreSQL vs
CockroachDB pre-implementation verification note, backup-before-migration
runbook expectations, and an executable static validation seam for the
deployment foundation.

Out of scope: Godot Nakama login, Project0 Character migration, world-entry
ticket issuance, Nakama socket gameplay bridge code, live deployment to the
server, automatic matchmaking, friends/groups/chat, custom admin UI, and moving
Canon/Sector persistence into Nakama.

## Public seam

`deploy/compose.yml` and the Nakama deployment foundation validation command
are the public seam for this slice. The seam is intentionally operational and
static: it proves the deployment contract can be reviewed and validated before
any live server mutation.

## Falsifiable hypothesis

If Nakama is part of the single deployment stack as a single-node service with
durable PostgreSQL storage, private admin surfaces, host-side secrets, and an
explicit backup-before-migration runbook, then the deployment foundation can be
validated without starting a live Nakama service or exposing destructive admin
surfaces.

## BDD

1. Given the default compose deployment is rendered, when the foundation is
  inspected, then Nakama depends on a durable PostgreSQL service and stores
  data outside the image.
2. Given the Nakama service is configured, when its public ports are inspected,
   then only the client API/socket surface is eligible for public binding while
   Console/admin/metrics surfaces stay private or unbound.
3. Given operators prepare a playtest deployment, when they follow the runbook,
   then default Nakama credentials/keys must be rotated and stored outside the
   repo/images before use.
4. Given a Nakama version/runtime/storage change is planned, when the deployment
   gate is followed, then database/config backup happens before migration and
   rollback is schema-aware rather than image-only.

## TDD / validation

`scripts/check_nakama_deployment_foundation.py` is the executable public-seam
check for this slice. It inspects the committed compose/runbook contract for
the Nakama services, mandatory default-stack membership, durable PostgreSQL storage, private
Console/admin posture, host-side secret/config paths, explicit migrations, and
documented backup/rollback expectations.

## Safety invariants

- Nakama default keys/passwords are never accepted as playtest-ready
  configuration.
- Nakama Console, gRPC/admin APIs, metrics, and destructive operator surfaces
  are not publicly exposed by the v1 foundation.
- A Nakama schema migration is never treated as safely reversible by image tag
  rollback alone.
- This slice does not grant clients direct Character or Canon write authority.

## Ownership note

Copilot is implementing this slice under the standing authorization because the
local Claude CLI is unavailable/interactive-only on this Windows machine (see
repository memory `implementation-ownership.md`). Implemented in an isolated
git worktree (`slice/166-nakama-deployment-foundation`) because the user's main
workspace has unrelated dirty changes.

## Root-cause learning

- **Symptom (validation environment mismatch)**: local Windows full GUT
  validation ran 110/111 scripts, then failed 12 tests with peer-replication,
  prediction/reconciliation spawn assertions, missing native GDExtension
  libraries, and a skipped SQLite-store script due to parse/stale-cache
  behavior.
- **Falsifiable hypothesis**: the failures were environment/native-library
  limitations of the Windows checkout, not regressions from this slice's
  deployment YAML, Markdown runbook, or Python static check.
- **Discriminating check**: copied the same working tree (excluding generated
  caches) to the Linux host validation path and reran the focused checks,
  record sync, and full GUT validation there.
- **Confirmed root cause**: Windows lacked the native runtime/dependency shape
  used by this repo's full Godot validation; the same slice passed on the Linux
  host with the expected native dependencies.
- **Why existing tests did not catch it earlier**: this slice's focused seam is
  operational/static and does not load Godot native extensions; the failure only
  appears when the whole project suite is run in the Windows checkout.
- **Countermeasure**: treat Windows full-suite output as a local environment
  limitation for this slice and use Linux-host full-suite evidence as the
  completion gate, while keeping focused static validation runnable locally.
- **Regression evidence**: Linux host validation passed focused deployment
  check, Python compile, record sync, and the full GUT suite.

## Validation evidence

Focused local checks: `python scripts/check_nakama_deployment_foundation.py` —
passed; `python -m py_compile scripts/check_nakama_deployment_foundation.py` —
exit 0. Docker Compose was unavailable in the Windows environment, so compose
rendering was not run locally.

Full validation on the Linux host temp tree copied from this branch:
`python3 scripts/check_nakama_deployment_foundation.py` — exit 0;
`python3 -m py_compile scripts/check_nakama_deployment_foundation.py` — exit 0;
`bash scripts/check_record_sync.sh` — exit 0, 0 errors and 6 pre-existing
warnings; `bash scripts/run_gut_validation.sh` — exit 0, **811/811 tests
passing**.