# Slice 153 - Phase 16 (F-037): launcher updater orchestration

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Apply, restart, and rollback"),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md).
Consumes the transaction mechanics from [Slice 149](149-updater-transaction.md)
and the public hosting from [Slice 152](152-enrollment-patch-hosting.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the standing authorization in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). Claude CLI is interactive-only
on this machine; the full delivery gate was applied.

## User outcome

The launcher now has a persistent payload location and a separate updater mode.
A staged pack can be applied by a detached launcher process while the game is
closed, then the client can be relaunched through the same launcher-owned
payload. A startup recovery check runs before any client process starts.

## Scope and non-goals

In scope: persistent payload extraction under the launcher AppData directory,
startup transaction recovery, detached helper invocation, helper-side atomic
apply through `ApplyStagedPatch`, and a bounded client relaunch/readiness seam.

Out of scope: the HTTPS fetch itself (Slice 148's `UpdateStager` remains the
client-side fetch seam), wiring the version-gate rejection to trigger the fetch,
launcher LAN/WAN UI, onboarding, production release upload, and final packaged
Windows end-to-end evidence. This slice exposes the orchestration boundary those
later pieces call.

## Public seam

`native/windows_launcher/main.go`:

- `payloadDirectory()` — stable AppData-owned payload root; no temporary
  extraction is used for the running client anymore.
- `runUpdaterHelper(args)` — detached helper invocation boundary.
- `runClient(executable, args, env) -> exit code` — relaunch/readiness boundary.
- `--project0-update-helper` — separate process mode that applies a staged pack
  and exits without loading Godot.
- `--project0-run-client` — explicit relaunch mode used by the helper contract.

The helper accepts `--project0-staged-pack`, `--project0-pending-version`,
`--project0-previous-version`, `--project0-expected-sha256`, and
`--project0-payload-dir`. It applies the transaction, then launches the client
with `--project0-run-client`; a non-zero client exit invokes `Rollback` and
returns failure. The readiness signal is the client's process exit for now; the
pre-auth version handshake remains the authoritative server-side readiness check
when the next connection is made.

## Design notes

The old temporary extraction made updater recovery impossible: every launcher
run got a fresh directory, so `.bak` and the transaction marker could not
survive the process that created them. The persistent AppData payload is now the
rollback unit, and embedded payload extraction is idempotent: it fills missing
files but does not overwrite a patched payload on every launch.

The helper is the launcher itself in a separate process, not a child Godot
process. That preserves the critical property from Slice 149: the process doing
the swap does not depend on the `.pck` it replaces.

This slice does not claim that a real packaged client has completed a full
self-update. The HTTPS transport, release hosting, and process boundary are now
present, but packaged Windows runtime evidence still needs the operator runbook
and a published signed artifact.

## Validation

- `go vet ./...` in `native/windows_launcher` — clean.
- `go test ./...` — **ok**, including the new persistent-payload and
  helper-argument tests.
- Full GUT suite remains unchanged; no GDScript behavior changed.
- `bash scripts/check_record_sync.sh` exits 0.

## Root-cause learning

No unexpected failure. The controlling discovery was architectural: the prior
launcher extracted to `os.MkdirTemp`, then deleted that directory on return. A
transaction marker there could never support restart recovery. The countermeasure
is to make the launcher's AppData payload directory the explicit ownership and
rollback boundary before adding more network/update behavior.

## Follow-on

The remaining evidence slice must run a signed artifact through the packaged
Windows launcher: manifest fetch → staging → detached helper → relaunch →
version-handshake readiness, with a deliberately bad relaunch proving rollback.
