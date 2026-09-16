# Unified Windows Launcher: LAN/WAN Selection, Patching, and Onboarding

Label: wayfinder:map

## Destination

Produce a handoff-ready spec, the supporting ADR(s), and a staged
implementation slice route for a **single unified Windows launcher** that
starts the Project0 client for both connection modes. The launcher must:

- let the user pick **LAN** (explicit checkbox, only valid when the server is on
  the same network) versus **WAN** (default, WireGuard tunnel) and launch the
  correct client path for that choice;
- check the installed client version against a server-owned manifest and
  **patch an out-of-date client payload** (integrity-verified, atomic, with
  rollback), replacing today's build-time embedded payload;
- guide a **first-time or new user** through account onboarding (login and
  enrollment; WAN self-service registration decided under a gated ticket).

The map is complete when mode selection, version/patch manifest, patch delivery
and integrity, onboarding, the registration decision, packaging/build changes,
and the integrated launcher state machine plus security boundaries are decided
well enough to create implementation slices without guessing.

## Notes

- Domain: Windows Go launcher, WireGuard tunnel enrollment, DPAPI-protected
  keys, signed account/Character assertions, HTTPS enrollment surface, ENet vs
  tunnel client paths, client versioning, patch delivery, atomic file swap, and
  first-run onboarding UX.
- Planning mode: this map produces **decisions and handoff material only**. It
  does not implement launcher, patch, or build code while charting; each
  resolved route becomes bounded SDD/BDD/TDD slices under the repo workflow
  (Copilot orchestrates; Claude CLI implements).
- Current reality: a Windows Go launcher already exists
  ([native/windows_launcher/main.go](../../native/windows_launcher/main.go),
  [enrollment.go](../../native/windows_launcher/enrollment.go)). It performs
  first-run self-service login (username/password -> signed account assertion ->
  WireGuard peer redemption) or an `--invite-code` fallback, stores a
  DPAPI-protected private key + `peer.json` in AppData, extracts an **embedded**
  payload (`Project0.exe`/`.pck`), sets `PROJECT0_TUNNEL=1`, and launches the
  client through the tunnel. There is **no version check or patch mechanism**.
- LAN vs WAN today is two separate modes: WAN = launcher + tunnel + HTTPS login
  (enrollment service, [infra/enrollment/](../../infra/enrollment/)) +
  assertion-only game server; LAN = raw client ZIP, direct ENet,
  `--server-host=<LAN IP>`, ENet login path
  ([docs/windows-client-tester-guide.md](../../docs/windows-client-tester-guide.md)).
  `client_https_login_enabled()` flips ON under tunnel mode
  ([shared/network_config.gd](../../shared/network_config.gd)).
- Standing constraints: reuse the existing WireGuard/DPAPI/enrollment/assertion
  plumbing rather than rewriting it; keep server authority over gameplay,
  Canon, and identity; never trust client-supplied Account/Character claims;
  keep OPNsense and client private keys out of any patch/manifest surface; keep
  the public surface minimal (relates to DT-009 rate limiting and DT-010
  deferred registration).
- Scope fixes: Windows-only; both LAN and WAN are first-class shipped modes;
  patch the **client payload** only (launcher self-update is beyond this
  destination).
- Skills every session should consult: `grilling` and `domain-modeling` by
  default; `research` for prior-art tickets; `prototype` when a concrete
  onboarding/patch-flow artifact would raise the discussion; `codebase-design`
  when defining the launcher's internal seams.
- Delivery rule: each resulting implementation slice needs a public seam,
  SDD/BDD/TDD evidence, bounded telemetry, rollback, and synchronized delivery
  records.

## Decisions so far

<!-- one line per closed ticket: gist of the answer, then the link for detail -->

- [Prior-art research: EQEMU login server and online-game launcher/patcher patterns](issues/01-prior-art-eqemu-and-launcher-patterns.md):
  EQEmu validates the login/world split (reuse its server-list -> select ->
  session-credential sequence; keep Project0's self-verifying assertion over
  EQEmu's opaque token); production updaters use a **signed version manifest
  (per-file size+hash) + staging-dir swap + retain N-1 rollback**, with
  delta patching only as a bandwidth optimization gated by a base checksum;
  account creation is a policy fork — operator/web-gated (like `mint-invite`)
  vs a public `/register` needing the full OWASP abuse-control set (extends
  DT-009). Findings: [research/01-prior-art.md](research/01-prior-art.md).

## Not yet specified

<!-- in-scope fog toward the destination; graduates into tickets as the
frontier advances -->

- **Launch-time diagnostics / repair**: if a patched or partially-applied
  payload is detected as corrupt on a later run, how the launcher self-heals
  (re-fetch vs prompt). Sharpens once patch delivery and integrity are decided.
- **Telemetry payload for launcher stages**: exact bounded fields for
  mode-selected / version-checked / patch-applied / onboarding-outcome events.
  Sharpens once the state machine ticket is worked.
- **Offline / patch-server-unreachable behavior**: whether a client with an
  up-to-date payload may launch when the manifest is unreachable, and the LAN
  case where no patch server exists. Sharpens after the manifest decision.

## Out of scope

<!-- ruled beyond the destination; closed, never graduates on this map -->

- Linux and macOS launchers (this effort is Windows-only; revisit as a fresh
  effort if needed).
- **Launcher self-update** (the launcher patching itself). This map patches the
  client payload; self-updating the launcher binary is a separate later effort.
- Replacing WireGuard/OPNsense or embedding OPNsense credentials anywhere in the
  launcher or patch surface.
- Gameplay, world-generation, or Canon changes.
- Internet-wide matchmaking / NAT traversal beyond the existing tunnel model.
