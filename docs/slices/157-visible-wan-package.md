# Slice 157 - Phase 16 (F-037): visible WAN package and opt-in stable-directory updates

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **in progress**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

## User outcome

The WAN download is a visible package containing the launcher, Godot client,
PCK, and native DLL. The launcher installs those files into the stable
`%LOCALAPPDATA%/Project0` directory and asks for confirmation before downloading
or applying a signed update.

## Scope and non-goals

In scope: external package files instead of Go-embedded payloads, stable local
installation, explicit update confirmation, and release packaging of the
visible WAN folder.

Out of scope: Authenticode certificate acquisition and Microsoft Defender
submission, which require operator-owned identity and portal actions.

## Invariants

- Signed manifest and PCK verification remain unchanged.
- Updates still use the existing atomic swap and rollback transaction.
- The enrollment container remains read-only over release artifacts.
- LAN users continue using the portable client ZIP.

## Validation

- `GOOS=windows GOARCH=amd64 go test ./...` passes in `native/windows_launcher`.
- `GOOS=windows GOARCH=amd64 go vet ./...` passes.
- `bash -n scripts/package_client_linux.sh scripts/publish_client_downloads.sh` passes.
- `git diff --check` passes.