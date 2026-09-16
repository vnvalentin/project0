# F-035 Secure Windows Launcher — Live WAN Validation Runbook

This runbook closes the only remaining evidence for
[F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage):
the Windows-launcher side of the secure tunnel, proven against the **live**
enrollment service at `https://enroll.valentin.vip`. Everything else in F-035 /
[P-024](FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
is already delivered and validated; the checks below are runtime evidence that
only a physical Windows machine on a real WAN can produce.

Record the results in the F-035 change history (and the
[Slice 054](slices/054-secure-windows-tunnel-enrollment.md) validation section)
once complete.

**Deployment prerequisite: completed 2026-09-16.** Slice 100's runtime files
were deployed to `okami`, the OPNsense enrollment proxy was backed up and
updated with exact POST-only locations for `/login`, `/register`, and all four
`/characters/*` routes, and the OPNsense web GUI reload completed successfully.
The loopback login authority remains private. Safe public checks returned 422
from FastAPI validation for empty POST bodies, while GET requests remained 403.

## Evidence this run must produce

- [x] **Fresh enrollment** — a clean machine provisions its own peer and reaches
  gameplay.
- [x] **Persisted restart** — a relaunch reuses the DPAPI-protected key with no
  re-enrollment.
- [x] **Malformed / expired invite rejection** — a bad or expired invite fails
  closed (no peer, no tunnel).
- [x] **DPAPI access scoping** — the stored private key cannot be unprotected by
  another user / machine.
- [x] **Revoked-peer rejection** — after an operator revoke, the client can no
  longer connect.
- [x] **One-launch WAN gameplay** — from off-LAN, a single launch brings up the
  tunnel and plays.

## Roles

- **Operator** — shell access to the Linux host `okami` (`192.168.1.254`), where
  `project0-enrollment.service` runs. Owns invite minting and peer revocation.
- **Tester** — the Windows machine running the launcher. Off-LAN for the WAN
  check (e.g. a phone hotspot or a different site).

They may be the same person with two devices.

---

## Part A — Operator prep (Linux host `okami`)

All commands run from the repo root (`/data/code/project0`) using the
enrollment virtualenv.

1. **Confirm the live service is healthy** (from anywhere):

   ```powershell
   curl.exe https://enroll.valentin.vip/healthz
   # expect: {"status":"ok"}
   ```

   Method guard (should both be 403): `curl.exe https://enroll.valentin.vip/`
   and `curl.exe -X GET https://enroll.valentin.vip/redeem`.

   The route publication was verified on 2026-09-16 with empty JSON bodies:
   each POST reached FastAPI validation (422), while the GET method guards
   remained 403. Do not include real credentials or assertions in this smoke
   check.

2. **Mint a single-use invite** (fallback path + the expiry test):

   ```bash
   # long-lived invite for the fresh-enrollment check
   python -m infra.enrollment.cli mint-invite
   # short-lived invite for the expiry-rejection check
   python -m infra.enrollment.cli mint-invite --expires-in-seconds 30
   ```

   Each prints a CSPRNG code. Treat codes as secrets — deliver out-of-band, never
   commit or paste into telemetry.

3. **Know the revoke command** (used in Part B, check 5):

   ```bash
   python -m infra.enrollment.cli revoke-peer <client_public_key>
   ```

   `revoke-peer` is the only revocation surface (operator shell only; no HTTP
   admin endpoint). You identify `<client_public_key>` from the enrollment
   allocation store by the tester's assigned tunnel address (see check 5).

---

## Part B — Tester checks (Windows)

### Package

Use a launcher build produced by `scripts/build_windows_oneclick.ps1` (embeds
the client payload; the `.exe` is not committed to git). The launcher reads:

- `PROJECT0_ENROLLMENT_URL` — defaults to the live service; leave unset to use
  `https://enroll.valentin.vip`.
- Self-service path (preferred): the launcher prompts for **username/password**
  and logs in over HTTPS to obtain an account assertion, then redeems the peer.
- Invite fallback: `--invite-code=<code>` or `PROJECT0_INVITE_CODE=<code>`.

Per-user state lives under the launcher's app-data folder (e.g.
`%APPDATA%\Project0\`): `peer.json` (server pubkey, endpoint, assigned address)
and `private-key.dpapi` (the DPAPI-wrapped X25519 private key).

### Check 1 — Fresh enrollment

1. On a machine with **no** prior state, delete any existing `%APPDATA%\Project0\`
   folder to force first-run.
2. Launch the launcher. Complete the credential prompt (self-service) **or** pass
   the long-lived invite (`--invite-code=<code>`).
3. Expect: the launcher generates a key, redeems a peer, brings up the tunnel,
   and the client reaches `Server: connected: player spawned`.
4. **Capture:** `peer.json` and `private-key.dpapi` now exist; note the
   `AssignedAddress` (e.g. `10.77.0.2/32`); a screenshot of the connected status
   and both capsules moving. No private key left the machine.

### Check 2 — Persisted restart

1. Fully close the client and launcher.
2. Relaunch (no `--invite-code`, dismiss/skip any prompt).
3. Expect: **no** re-enrollment — the launcher unprotects the existing
   `private-key.dpapi`, reuses `peer.json`, brings up the tunnel, and reaches
   gameplay with the **same** assigned address.
4. **Capture:** confirm no new allocation was minted (same `AssignedAddress`),
   and that gameplay works without any credential/invite.

### Check 3 — Malformed / expired invite rejection

1. **Malformed:** first-run (clear `%APPDATA%\Project0\`) with
   `--invite-code=not-a-real-code`. Expect a fail-closed error (`INVITE_NOT_FOUND`
   → HTTP 404), **no** `peer.json`, **no** tunnel.
2. **Expired:** wait for the 30-second invite from Part A step 2 to lapse, then
   first-run with it. Expect `INVITE_EXPIRED` (HTTP 410), fail closed.
3. **Capture:** the launcher error text for each; confirm no peer state was
   written.

### Check 4 — DPAPI access scoping

The private key is wrapped with user-scoped DPAPI, so only the enrolling Windows
user on that machine can unprotect it.

1. Copy `private-key.dpapi` to a **different Windows user account** (or a
   different machine) and attempt to launch there (point it at the same
   `peer.json`).
2. Expect: unprotect fails; the launcher does **not** bring up the tunnel with
   the copied key (it would have to re-enroll).
3. **Capture:** the failure under the foreign user; confirm the key is inert
   off its owning user context.

### Check 5 — Revoked-peer rejection

1. Operator looks up the tester's `<client_public_key>` from the enrollment
   allocation store by the `AssignedAddress` recorded in Check 1, then runs:

   ```bash
   python -m infra.enrollment.cli revoke-peer <client_public_key>
   # expect an outcome such as REVOKED
   ```

2. Tester relaunches (or keeps running past the next handshake).
3. Expect: the WireGuard handshake no longer succeeds and the client **cannot**
   connect to the game host; only a fresh enrollment restores access.
4. **Capture:** the revoke command outcome and the client's failure to connect
   after revocation.

### Check 6 — One-launch WAN gameplay

1. Put the Windows machine on a network **outside** the home LAN (phone hotspot
   or a different location). Re-enroll if Check 5 revoked the peer.
2. Single launch. Expect: tunnel comes up over the WAN and the client reaches
   `Server: connected: player spawned`, with the red (local) and blue
   (authoritative) capsules and W/A/S/D movement replicating over the tunnel.
3. **Capture:** a screenshot of connected WAN gameplay and the network context
   (confirming it is not the home LAN).

---

## Part C — Recording the evidence

### Recorded result — 2026-09-16

The user confirmed all six checks passed on the current off-LAN Windows client
using the current WAN launcher. Fresh enrollment, persisted restart,
malformed/expired invite rejection, DPAPI access scoping, revoked-peer
rejection, and one-launch WAN gameplay all passed. No passwords, invite codes,
private keys, DPAPI files, or assertion tokens were retained in the repository
or conversation.

Once all six boxes are checked, add a dated change-history entry to
[F-035](FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)
and the [Slice 054](slices/054-secure-windows-tunnel-enrollment.md) validation
section summarizing each check with its captured evidence, then flip F-035
`In Progress → Implemented` (and reconcile Phase 13 in
[PROJECT-TRACKER.md](PROJECT-TRACKER.md)). Chat/terminal logs alone are not
durable evidence — reference the screenshots/notes and the exact commands run.

## Safety notes

- Never commit or transmit a private key, invite code, or the DPAPI blob. The
  launcher already keeps the key out of Git, HTTP requests, telemetry, and the
  game environment; keep it that way in any manual step.
- Invite codes are single-use and (optionally) time-boxed. Mint fresh ones per
  session; don't reuse.
- Revocation is operator-shell only. There is no HTTP admin surface to protect.
