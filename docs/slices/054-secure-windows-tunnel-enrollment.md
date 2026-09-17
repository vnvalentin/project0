# Slice 054: Secure Windows tunnel enrollment and credential storage
GitHub issue: #95

**Status:** Delivered (secure launcher, live enrollment service, and real off-LAN Windows validation complete)
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
ASGI service. After DNS and TLS are live, set the Windows launcher
build/runtime value `PROJECT0_ENROLLMENT_URL` to
`https://enroll.valentin.vip/redeem`.

## Live enrollment-service deployment (deployed and validated)

The enrollment service is now deployed and publicly reachable, operationally
delivered and validated by Copilot:

- systemd unit `project0-enrollment.service` runs uvicorn `infra.enrollment.asgi:app`
  bound to `192.168.1.254:8095` on the okami Linux host (port 8080 was already
  taken by docker-proxy). Config lives at `/etc/project0/enrollment.env`
  (mode 600); OPNsense API secrets are sourced from the host without exposure,
  and `ENROLLMENT_SERVER_PUBLIC_KEY` is pulled live from the `project0-game`
  WireGuard server.
- `ENROLLMENT_WIREGUARD_ENDPOINT=192.69.180.236:51900` — the WireGuard tunnel
  endpoint uses the static WAN IP directly. There is no `game` DNS record and
  no DNS dependency for the WireGuard tunnel itself, by design.
- OPNsense nginx TLS vhost `/usr/local/etc/nginx/opnsense_http_vhost_plugins/enroll-proxy.conf`
  (listen 443 ssl, `*.valentin.vip` wildcard cert) reverse-proxies to
  `192.168.1.254:8095`. The original deployment published only `GET /healthz`
  and `POST /redeem`; Slice 100 now requires adding `POST /login`,
  `POST /register`, and `POST /characters/{list,create,delete,select}` to the
  explicit proxy allowlist before WAN self-service validation. The loopback
  login authority remains private and is never published.
  every other path/method returns 403.
- OPNsense Unbound host override `enroll.valentin.vip → 192.168.1.1` (LAN
  split-horizon) and a Cloudflare-proxied CNAME `enroll → valentin.vip` (the
  public path rides the existing WAN-443-from-Cloudflare-IPs rule; no
  firewall change was needed).

On 2026-09-16, the OPNsense proxy was backed up and updated through the
`okami` jump host. Its exact POST-only locations now publish `/login`,
`/register`, and `/characters/{list,create,delete,select}` to the enrollment
service; `configctl webgui restart` returned `OK`, and `nginx -t` passed. The
live public checks returned FastAPI validation responses for empty POST bodies
(422) and retained 403 responses for disallowed GET methods. The six Slice 100
runtime files were deployed to `okami` with timestamped backups, and both
`project0-login` and `project0-enrollment` were restarted successfully.

Validation evidence:

- `.venv-enrollment/bin/python -m pytest infra/enrollment/tests` → 55 passed.
- `https://enroll.valentin.vip/healthz` through Cloudflare → HTTP/2 200
  `{"status":"ok"}`.
- `POST /redeem` through the Cloudflare edge → HTTP 200 with a valid peer
  bundle (`assigned_address 10.77.0.2/32`, `endpoint 192.69.180.236:51900`),
  i.e. a real OPNsense peer registration; then `revoke-peer` → `REVOKED`,
  allocation released.
- Method guard verified: `GET /redeem` → 403, `GET /` → 403.
- No private key was ever transmitted (the client sends only the public key).

This closes the service-deployment gap described above; the DNS-resolution
failure noted earlier no longer applies. The user confirmed all six F-035
real-WAN checks passed on 2026-09-16 using the current launcher: fresh
enrollment, persisted restart, malformed/expired invite rejection, DPAPI
access scoping, revoked-peer rejection, and one-launch off-LAN gameplay. No
credential, private key, invite code, DPAPI blob, or assertion was recorded.

## Live WAN validation evidence

- Fresh enrollment: passed; peer state was created and gameplay reached the
  connected Player state.
- Persisted restart: passed; the protected peer was reused without
  re-enrollment.
- Malformed/expired invite rejection: passed; invalid enrollment failed closed.
- DPAPI access scoping: passed; the protected key was not usable outside its
  owning Windows user context.
- Revoked-peer rejection: passed; the revoked peer could not reconnect.
- One-launch WAN gameplay: passed from an off-LAN Windows network.
