# Slice 101 - Server deployment path in the current deployment pipeline
GitHub issue: #95

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing P-014.

## User outcome

A committed Project0 server revision can be deployed to the Linux host through one explicit, auditable pipeline command, with a remote backup and post-upload validation before the selected runtime is restarted.

## Scope and non-goals

In scope: `scripts/deploy_server.ps1`, the opt-in `-DeployServer` stage in `scripts/build_current_deployment.ps1`, commit-archive upload to the Linux host, timestamped remote backup, native systemd restart, Docker candidate startup, Docker split-candidate startup, and bounded health/identity output.

Out of scope: automatic production deployment on ordinary client builds, destructive cleanup of remote data, Docker-to-production cutover, database migration, secret generation, and WAN client validation.

## Public seam

`powershell -File scripts/build_current_deployment.ps1 -DeployServer -ServerMode native|docker-candidate|docker-split`. The default pipeline remains client-only. Server deployment requires a clean committed worktree unless `-SkipServerCleanCheck` is explicitly supplied.

## Safety invariants

- The server archive is made from `HEAD`, never an uncommitted working tree.
- The existing remote source is moved to a timestamped backup before extraction.
- Persistent data directories are outside the source path and are not deleted.
- Native restart and Docker modes are explicit choices; no mode is selected implicitly.
- Secrets are not generated, copied, or printed by the pipeline.
- Deployment stops on upload, extraction, source validation, build, health, or restart failure.

## Acceptance scenarios

1. Given a clean committed checkout, when native deployment is selected, then the remote backup is created, the exact commit archive is extracted, both native services restart, and both report active.
2. Given an uncommitted checkout, when deployment is attempted without `-SkipServerCleanCheck`, then it fails before remote changes.
3. Given Docker candidate mode, when deployment is selected, then only the candidate compose service is built/started; production systemd services are untouched.
4. Given a failed upload or validation, then the pipeline stops and reports the remote backup path.

## Validation

Focused validation: PowerShell parser checks for both scripts and a no-side-effect invocation that fails the clean-tree guard before SSH when the worktree is dirty. Full project GUT and record-sync remain required on the Linux branch checkout.

## Validation evidence

- PowerShell parser checks passed for `scripts/deploy_server.ps1` and
  `scripts/build_current_deployment.ps1`.
- Dirty-worktree safety check stopped deployment before SSH when the worktree
	was not clean.
- `git diff --check` passed.
- `scripts/check_record_sync.sh` passed with 0 errors and 6 warnings through
  the explicit Git Bash path.
- No live restart was performed by this slice; native and Docker modes remain
	explicit operator actions.

## Review outcome

Delivered. Server deployment is opt-in, commit-pinned, backed up, and mode
explicit. The default current deployment pipeline remains client-only.

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-10--authoritative-runtime-and-action-input)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 101
