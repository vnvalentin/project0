# Slice 054: Secure Windows tunnel enrollment and credential storage

**Status:** In Progress (secure launcher implemented; live enrollment validation pending)
**Linked Feature:** F-035
**Parent Feature:** P-024
**Related Slices:** 035 (Windows tunnel package), 048 (enrollment service), 049 (revocation lifecycle)

## Purpose

Replace the temporary one-click WAN verifier's embedded shared private key with
per-client enrollment and Windows-protected credential storage. The normal
user flow remains one launch after first-run enrollment; no batch file or
separate WireGuard application is required.

## Scope

- Generate a WireGuard client keypair locally on Windows.
- Redeem a single-use invite through the existing `POST /redeem` service,
  transmitting only the client public key.
- Persist the private key with user-scoped Windows DPAPI protection.
- Persist the non-secret peer configuration separately from the protected key.
- Start the existing in-process `wgnetstack` tunnel automatically at client
  startup after enrollment has completed.
- Provide bounded first-run, enrollment, missing-credential, and revoked-peer
  outcomes without logging key material.
- Retire the currently shared `windows-tester.key` after migration evidence.

## Non-goals

- Changing OPNsense tunnel topology or firewall policy.
- Replacing the existing `wgnetstack` transport adapter.
- Embedding private keys in Git, the Godot PCK, or a distributable executable.
- Password recovery, account authentication, or a new game-server protocol.
- Automatic revocation decisions; operators continue to use Slice 049.

## Security boundary

The private key is generated and retained on the tester's Windows machine. The
client sends only the public key to enrollment. DPAPI protects the private key
against ordinary file copying under another Windows user, but it does not
protect a key from a fully compromised local user account. Invite codes are
single-use and must be treated as enrollment credentials, not permanent secrets.

## Public seams

- Windows enrollment client: `generate_keypair`, `redeem_invite`, and
  `load_protected_peer`.
- Existing service seam: `POST /redeem` in `infra/enrollment/app.py`.
- Existing tunnel seam: `NetworkClient.connect_to_server()` and
  `WgNetstack.start(config)`.
- Existing operator seam: `RevocationService.revoke()` and its CLI.

## Acceptance checks

1. A fresh install generates a new keypair without writing the private key to
   the repository or sending it over HTTP.
2. A valid invite returns a peer configuration and persists the private key
   only in DPAPI-protected storage.
3. Restarting the client reuses the protected peer without asking for another
   invite.
4. Invalid, expired, redeemed, or malformed enrollment input fails closed with
   bounded user-visible status and no partial credential state.
5. A revoked peer cannot complete the tunnel handshake after the configured
   propagation interval.
6. The user launches one application and reaches the login screen without a
   batch file, external WireGuard app, or administrator rights.
7. No private key appears in logs, telemetry, HTTP payloads, Git history, or
   the packaged executable.

## Validation

- `go test ./...` under `native/windows_launcher` passes on Windows, covering
   DPAPI round-trip behavior, WireGuard public-key derivation shape, the
   missing-invite fail-closed path, and an HTTP proof that only the invite code
   and public key are sent to enrollment.
- The Windows launcher builds with `go build -trimpath -ldflags "-H=windowsgui"`
   and produces `dist/Project0-WAN-enrolled.exe`.
- The launcher lifecycle smoke test exits cleanly after extracting and
   launching the embedded client without a shared tester key.
- Enrollment integration tests against the existing fake OPNsense client and
  temporary SQLite store.
- Windows runtime test covering first enrollment, restart, revoked peer, and
  one-launch WAN gameplay.
- `scripts/check_record_sync.sh` and the standard project validation commands.

## Rollback

Keep the current embedded-key WAN verifier available as a temporary test
artifact while Slice 051 is developed. Do not revoke the existing tester peer
until the replacement enrollment and revocation evidence is complete.

## Current implementation

`native/windows_launcher/` now owns the secure Windows bootstrap path. It
generates an X25519 keypair locally, sends only the public key to the existing
`POST /redeem` service, protects the private key with Windows DPAPI under
`%LOCALAPPDATA%/Project0`, and writes a temporary private-key file only while
the embedded Godot client is running. The build script no longer accepts or
embeds `windows-tester.key`.

First-run enrollment currently accepts `--invite-code=<code>` or
`PROJECT0_INVITE_CODE`; subsequent launches reuse the protected peer state.
The live enrollment URL defaults to `https://enroll.valentin.vip/redeem` and
can be overridden with `PROJECT0_ENROLLMENT_URL` for staging validation.

## Separated Linux deployment

The enrollment API is deployed independently from the Windows client. The
Linux host owns `infra/enrollment/`, its SQLite allocation store, OPNsense API
credentials, and the HTTPS reverse proxy for `enroll.valentin.vip`. The
Windows launcher only receives the enrollment URL and a one-time invite; it
does not build, start, or configure the enrollment service.

On the Linux host:

```sh
cd /data/code/project0
python3 -m venv .venv-enrollment
.venv-enrollment/bin/pip install -r infra/enrollment/requirements.txt
sudo install -m 644 infra/enrollment/project0-enrollment.service /etc/systemd/system/project0-enrollment.service
sudo install -d -m 700 /etc/project0
sudo install -m 600 infra/enrollment/enrollment.env.example /etc/project0/enrollment.env
# Edit /etc/project0/enrollment.env with real values, then:
sudo systemctl daemon-reload
sudo systemctl enable --now project0-enrollment.service
curl -fsS http://127.0.0.1:8080/healthz
```

The HTTPS reverse proxy should publish only `/redeem` and `/healthz` to the
ASGI service at `127.0.0.1:8080`. After DNS and TLS are live, set the Windows
launcher build/runtime value `PROJECT0_ENROLLMENT_URL` to
`https://enroll.valentin.vip/redeem`.

Remaining evidence is deliberately blocked until the enrollment service is
deployed behind its live HTTPS endpoint and a fresh invite can be redeemed.
The configured endpoint `https://enroll.valentin.vip/redeem` currently fails
DNS resolution from this Windows environment, so no live invite or OPNsense
mutation was attempted.
