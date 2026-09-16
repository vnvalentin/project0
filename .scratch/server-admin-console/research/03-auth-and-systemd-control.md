# Research findings: operator auth & systemd control

Resolves [03 — Research: auth & systemd control](../issues/03-research-auth-and-systemd-control.md).
Captured as a file (not a throwaway `research/` branch) per the world-scale map's
deviation note: the working tree is active and branch-switching would be disruptive.

## 1. Reusable auth infra — VERDICT: reuse the assertion HMAC primitive

- Secret: `PROJECT0_ASSERTION_SECRET` (64 hex chars, `openssl rand -hex 32`), loaded via
  `EnvironmentFile=-/etc/project0/assertion.env` by both
  `scripts/project0-server.service` and `scripts/project0-login.service`.
- Crypto: HMAC-SHA256 over a base64 JSON payload; token = `<payload_b64>.<sig_b64>`;
  constant-time verify (`Crypto.constant_time_compare`).
  - Issuer: `server/assertion_issuer.gd` (`issue(...)`).
  - Validator: `server/assertion_validator.gd` (`validate(token, now)` → `{outcome, claims}`).
  - Claim schema + bounded encode/split: `shared/session_assertion.gd`.
  - Issuer/audience constants `project0-login` / `project0-game` in `server/login_runtime.gd`.
- **Reusable for an operator token:** the HMAC + shared-secret + env-file + issuer/
  audience/expiry/validator pattern is directly reusable. Add a distinct scope, e.g.
  `AssertionIssuer(secret, "project0-console", "project0-server")`, keyed by a new
  `PROJECT0_OPERATOR_SECRET` (separate or co-located in the same env file), with bounded
  `action`/`scope` claims.
- **Not reusable / exclude:** password PBKDF2 hashing, session registry/CRUD, account-
  in-DB presence — operator auth can be stateless (validate once, act).

## 2. In-Godot control transport — VERDICT: authenticated ENet RPC (Option A)

- Transport today: ENet/UDP; game `9999`, login `9998` (`shared/network_config.gd`); max
  10 peers. RPCs flow through the `NetworkClient` autoload (`client/network_client.gd`,
  ~36 `@rpc` receivers); server routes via `rpc_id(peer_id, "method", ...)`.
- Auth today: peer identity = ENet connection only; **no per-action authorization** —
  any connected peer can call any public RPC. Session registry checked only for
  login/character ops.
- **Cheapest authoritative path:** a new `receive_operator_control_intent(token, action_kind,
  payload)` RPC on `NetworkClient`; the server calls `AssertionValidator` on the operator
  token before dispatching to a privileged action handler (kick/drain/reload/degraded).
  Reuses existing ENet + RPC + validator plumbing; gate on a reserved operator peer_id.
- **Exists:** ENet peers, RPC routing, validator seam, server root/autoload access.
  **To build:** the control RPC, an operator-scoped issuer, and a server-side action
  dispatcher.
- Alternatives considered & rejected as heavier: (B) watched signed command file — no new
  port but adds polling latency + a writable shared volume; (C) localhost HTTP control
  endpoint — needs an HTTP stack in Godot.

## 3. systemd / host control — VERDICT: mounted host-side helper script (Option B)

- Units: `project0-server.service`, `project0-login.service`,
  `project0-host-firewall.service` (+ enrollment). Host `192.168.1.254`: `SUDO_NOPASSWD=yes`
  for `vic`.
- Deploy: `deploy/game-server/docker-compose.yml` runs servers as non-root `godot`
  (UID 10001); host dirs `/var/lib/project0` → `/data`, `/var/backups/project0` → `/backup`;
  `stop_grace_period: 20s`; health at `/data/health.json` (`deploy/game-server/healthcheck.sh`).
- **Precedent:** `ci/host-firewall-helper.sh` + `scripts/project0-host-firewall.service` —
  a root-requiring idempotent shell helper invoked via sudo. The operator console should
  mirror this: a host-side `operator-helper.sh` (owned by `vic`, invoked under the existing
  `SUDO_NOPASSWD`) exposing `restart|stop|start|status <unit>`, called by the console only
  after operator-token validation.
- Alternatives rejected as heavier / no precedent: SSH-from-container, privileged sidecar,
  D-Bus socket mount.

## Feeds

- Ticket 07 (operator-token auth): reuse the assertion HMAC primitive; enforce independently
  at the in-Godot control seam **and** the host helper.
- Ticket 02 (control seam): confirms the two-executor split — in-Godot RPC dispatcher +
  host-helper for systemd; both behind token validation; idempotent + audited.
