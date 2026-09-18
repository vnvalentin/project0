# Slice 155 - Phase 16 (F-037): `CLIENT_OUTDATED` handoff to the launcher update loop

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md).
Consumes [Slice 146](146-version-gate-enforcement.md), [Slice 154](154-launcher-signed-update-download.md),
and [Slice 153](153-launcher-updater-orchestration.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the standing authorization in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). Claude CLI is interactive-only
on this machine; the full delivery gate was applied.

## User outcome

An outdated packaged client now hands its server-provided update URL and required
version back to the launcher, exits with a bounded update-required code, and lets
the launcher fetch, verify, stage, apply, and relaunch it. A direct client run
without the launcher handoff remains presentation-only and does not exit.

## Scope and non-goals

In scope: the client rejection-file handoff, bounded exit code, Go launcher
handling, `DownloadAndStageUpdate` invocation, and helper invocation.

Out of scope: packaged Windows runtime proof against a live HTTPS release,
launcher UI/progress, publish/upload automation, and controller support.

## Public seam

- Client: `PROJECT0_UPDATE_REJECTION_PATH` environment path and exit code `20`
  when the launcher is present; writes the bounded rejection dictionary as JSON.
- Launcher: `updateRequiredExitCode`, rejection-file parsing, HTTPS download/
  staging, and helper invocation.

## Security boundary

The client writes only the server's bounded rejection fields. The Go launcher
validates the server-supplied URL through the HTTPS-only downloader and verifies
the manifest signature and pack digest before staging. The rejection file is
transient and removed before each launch; it is never treated as trusted update
metadata by itself.

## Validation

- `go vet ./...` clean.
- `go test ./...` passes, including rejection parsing, bounded exit-code behavior,
  and launcher update-loop seams.
- Full GUT suite: **106 scripts / 774 tests / 774 passing / 2451 asserts, exit 0**;
  direct-client rejection tests remain presentation-only because no launcher
  handoff path is configured in the test process.
- `bash scripts/check_record_sync.sh` exits 0.

## Root-cause learning

No unexpected failure. The key boundary is explicit: the Godot client cannot
invoke the Windows updater directly because it must not own the process that
replaces its pack. The bounded rejection file plus exit code keeps the client
presentation layer and launcher process authority separate.

## Follow-on

Packaged Windows runtime evidence must now run this loop against a published
signed release, then deliberately serve a bad release to prove rollback.
