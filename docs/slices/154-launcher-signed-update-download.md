# Slice 154 - Phase 16 (F-037): launcher signed-update download and staging

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md).
Consumes the signing key from [Slice 150](150-trusted-signing-key.md), staging from
[Slice 148](148-https-update-staging.md), and transaction mechanics from
[Slice 149](149-updater-transaction.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the standing authorization in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). Claude CLI is interactive-only
on this machine; the full delivery gate was applied.

## User outcome

The Windows launcher now has the native Go path needed to retrieve a signed
release: manifest bytes and detached signature over HTTPS, followed by the pack
URL from the verified manifest, with all three artifacts staged only after RSA,
version, size, and SHA-256 checks pass.

## Scope and non-goals

In scope: Go HTTPS retrieval and fail-closed verification/staging, using the
same public key embedded in the Godot client; local fixture tests; no change to
normal launch behavior yet.

Out of scope: interpreting the server's `CLIENT_OUTDATED` RPC, automatic update
policy/UI, detached helper invocation, relaunch/readiness, and production host
upload. Those are the next integration/runtime step; this slice proves the Go
launcher can safely produce the staged input the helper consumes.

## Public seam

`native/windows_launcher/update_download.go`:

- `DownloadAndStageUpdate(client, baseURL, currentVersion, payloadDir) -> UpdateDownloadResult`
- `verifyManifest(raw, signature, publicKey) -> manifest`
- `downloadToFile(client, url, path)`

The manifest is verified over raw bytes before JSON parsing. The client refuses
non-HTTPS URLs, a manifest for the current version, malformed fields, a foreign
signature, wrong size, or wrong SHA-256. Temporary files are removed on every
failure. The verified pack is staged under the launcher's persistent payload
boundary for Slice 153/149 to consume.

## Security boundary

The Go launcher embeds the same public key fingerprint as the Godot client. The
private signing key is not copied, read, or referenced by this code. TLS is
transport only; RSA signature and pack digest decide trust. The pack URL is read
only after the manifest signature verifies, so a compromised host cannot redirect
an unsigned artifact into the staging path.

## Validation

- `go vet ./...` clean in `native/windows_launcher`.
- `go test ./...` passes, including real RSA signatures over raw manifest bytes,
  tampered manifest refusal, foreign-key refusal, HTTPS-only refusal, up-to-date
  handling, wrong-size/wrong-digest refusal, and successful staging into a real
  temporary directory via an in-process TLS fixture.
- Full GUT suite remains unchanged; no GDScript changed.
- `bash scripts/check_record_sync.sh` exits 0.

## Root-cause learning

No unexpected failure. The key design constraint is that the Go launcher cannot
reuse the GDScript verifier directly because the launcher must continue running
when the `.pck` is corrupt or being replaced. The verifier is therefore a native
Go implementation of the same raw-bytes/RSA-3072/SHA-256 contract, tested against
real keys and the same signed manifest shape.

## Follow-on

The next slice wires `DownloadAndStageUpdate` to the server's `CLIENT_OUTDATED`
response and invokes the detached helper, with packaged-Windows runtime evidence
for successful update and deliberate rollback.
