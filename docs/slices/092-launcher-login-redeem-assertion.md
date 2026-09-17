# Slice 092 — Auth-gated onboarding C-launcher: Windows launcher login + redeem-with-assertion
GitHub issue: #95

Status: **delivered**

Tracker context: Phase 11 — Public game access; advances
[P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard)
under [F-035](../FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage)
per [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md). The launcher-side
completion of the auth-gated onboarding arc: the server `/login` + assertion
`/redeem` path (Slices 088/089) and the client scene wiring (Slices 091/093)
are done; this slice makes the Windows launcher obtain its WireGuard peer with
self-service credentials instead of a one-time invite. Implemented directly by
Copilot with the user's explicit authorization (Claude CLI rate-limited).

## User outcome

A new player can go from downloading the Windows launcher to bringing up the
tunnel using only their own username and password — no invite code obtained
from a third device. The launcher logs in over the public HTTPS enrollment
service, receives a signed account assertion, and redeems its WireGuard peer
with that assertion before starting the tunnel. An operator-supplied invite
code remains an explicit fallback.

## Problem

Before this slice the launcher's first run hard-required an invite code
(`--invite-code=` / `PROJECT0_INVITE_CODE`, or an interactive prompt);
`ensurePeerConfig` failed closed when none was present. That is the exact
"obtain a key from a third device" dead-end the user called out as
non-functional. [ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) and
Slice 089 made the enrollment `/redeem` accept a signed account assertion, and
Slice 088 exposed `POST /login`; the launcher had not yet been switched to use
them.

## Scope and non-goals

**In scope:** `native/windows_launcher/enrollment.go` (+ its test file) —
- `provisionPeer(publicKey)`: the first-run provisioning decision. Prefers the
  self-service login path (prompt credentials → `login` → account assertion →
  `redeemWithAssertion`); uses an explicit invite (`explicitInvite`) only when
  one is supplied.
- `login(username, password)`: `POST /login` → signed account assertion.
- `redeemWithAssertion(assertion, publicKey)`: `POST /redeem` with
  `{assertion, public_key}` (the Slice 089 assertion path).
- `credentialPrompter` (injectable package var, default `promptForCredentials`
  via PowerShell `Get-Credential`) — the same injectable-seam pattern the prior
  launcher fix established for the invite prompt, so tests never block on the
  Windows credential dialog.
- `enrollmentBaseURL()` + `postEnrollment()`: shared base-URL resolution
  (tolerating a trailing `/redeem` or slash) and one bounded POST helper reused
  by `login`, `redeem`, and `redeemWithAssertion`.
- `redeemRequest` gains an `Assertion` field; both `invite_code` and
  `assertion` are `omitempty` so exactly one is sent (the enrollment `/redeem`
  validator requires exactly one non-null).

**Non-goals:** the client scene/tunnel wiring (Slice 093, done); passing the
launcher's account assertion to the game to skip the in-game re-login (a UX
optimization — the game still performs its own HTTPS login to obtain the
**character** assertion, which the launcher's account assertion cannot provide);
public HTTPS account registration (still absent, tracked as DT-010); TLS
pinning; rate-limiting (DT-009); any live WAN tunnel proof (user-pending real
Windows run).

## Public seam

`native/windows_launcher/enrollment.go`: `provisionPeer`, `login`,
`redeem`/`redeemWithAssertion`, `explicitInvite`, and the injectable
`credentialPrompter`. `ensurePeerConfig` now delegates first-run provisioning
to `provisionPeer` after generating the client key.

## Safety invariants

- **Fail-closed provisioning.** With no explicit invite and empty credentials,
  `provisionPeer` returns an error (no peer, no tunnel). A rejected login
  (non-2xx) or a login response without an assertion is an error.
- **Exactly one credential on `/redeem`.** `omitempty` on both `invite_code`
  and `assertion` means the invite path sends only `invite_code` and the login
  path sends only `assertion`, satisfying the enrollment validator.
- **Secret hygiene preserved.** Credentials are read from the interactive
  prompt only (never env/args), the account assertion is held in memory only
  for the redeem call, and neither is forwarded to the game (`forwardedArgs` /
  `filteredEnvironment` continue to strip `--invite-code=` /
  `PROJECT0_INVITE_CODE`; nothing new is placed in the game environment).
- **Invite remains a fallback**, so existing operator/invite workflows and
  their tests are unchanged.

## BDD/TDD

`native/windows_launcher/enrollment_test.go` (Go `httptest`, injectable
`credentialPrompter`):
- provisioning fails closed with no invite and empty credentials;
- `login` posts `{username,password}` to `/login` and returns the assertion;
- a rejected login (401) returns an error;
- `redeemWithAssertion` posts `{assertion, public_key}` (no `invite_code`);
- `provisionPeer` uses login-then-assertion-redeem by default;
- `provisionPeer` prefers an explicit invite and never runs the credential
  prompt when one is supplied;
- `enrollmentBaseURL` tolerates a trailing `/redeem` and defaults correctly.
Existing DPAPI, key-derivation, invite-redeem, cached-peer-match, and
invite-hygiene tests are retained.

## Validation

`go test ./native/windows_launcher/` on Windows (the launcher is
`//go:build windows`; the GUT/pytest suites do not cover it).

## Validation evidence

- `go vet ./...` clean and `go test ./...` `ok project0/windows-launcher`,
  **12/12 tests passing** on Windows (up from the 6-test baseline: 5 retained +
  7 new; the invite-only fail-closed test was replaced by the
  credential-path fail-closed test). Verbose run confirms every case PASS.
- **Live WAN evidence is user-pending:** a real Windows launcher run that logs
  in, redeems a peer with the assertion, and brings up the tunnel to enter the
  world has not been executed here and must be confirmed by the user on a real
  remote Windows client.

## Root-cause learning

- **Concurrent-worktree reconciliation before implementing.** While this slice
  was queued, a parallel worker delivered Slice 093 (client scene wiring) and
  merged it (PR #52), and a stray **uncommitted** working-tree edit had deleted
  the merged Slice 093 change-history entry from `FEATURE-LIST.md` (the
  committed `origin/main` still contained it). The editor's file read cache also
  briefly served a pre-093 copy of `PROJECT-TRACKER.md`. Countermeasure applied:
  re-`git fetch`, compared the committed `HEAD` blob against the working tree to
  establish the true baseline, restored `FEATURE-LIST.md` to `origin/main`
  (fully reversible via history), and extracted exact on-disk tracker lines via
  the shell before editing. Lesson: with a parallel worker active, verify
  tracker state against the committed blob (`git show HEAD:<file>`), not the
  editor's cached view, before record edits.

## ADR link

[ADR 0004](../adr/0004-auth-gated-tunnel-provisioning.md) (self-service tunnel
provisioning).

## Record links

- [SLICE-REGISTRY.md](SLICE-REGISTRY.md) (092; 091 seam, 093 client wiring —
  both delivered).
- [F-035](../FEATURE-LIST.md#f-035-secure-windows-tunnel-enrollment-and-credential-storage),
  [P-024](../FEATURE-LIST.md#p-024-public-game-access-via-opnsense-native-wireguard).
