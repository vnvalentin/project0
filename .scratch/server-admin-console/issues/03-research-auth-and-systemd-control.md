Type: research
Status: resolved
Blocked-by: none

## Question

Surface the facts two decisions wait on (feeds ticket 07 operator-auth and ticket 02
control seam). Read-only investigation of the existing repo + known host facts; capture
findings as a Markdown file under `.scratch/server-admin-console/research/` and link it
here.

Investigate:

1. **Reusable auth infra.** How `server/assertion_issuer.gd`,
   `server/assertion_validator.gd`, and `/etc/project0/assertion.env`
   (`scripts/assertion.env.example`) work — the secret shape, HMAC/signing approach,
   issuer/audience/expiry model — and whether an **operator-token** for console control
   actions can reuse the same primitive (shared secret in an env file, validator seam)
   rather than inventing a new mechanism.
2. **In-Godot control transport.** How the servers currently receive RPC
   (`client/network_client.gd`, ENet on 9998/9999) and what the cheapest authoritative
   way is for the console to submit a control action: an authenticated RPC on a
   dedicated control channel, a watched command file, or a small localhost control
   endpoint. Note what already exists vs. what must be built.
3. **systemd / host control feasibility.** Host `192.168.1.254` reports
   `SUDO_NOPASSWD=yes`. How would a **Dockerized console** invoke `systemctl
   restart/stop project0-*` — SSH to host, a mounted host helper, or a privileged
   sidecar? Review the `ci/host-firewall-helper.sh` +
   `scripts/project0-host-firewall.service` precedent as the likely pattern.

## Answer

Resolved 2026-09-15 via read-only research subagent. Full findings:
[research/03-auth-and-systemd-control.md](../research/03-auth-and-systemd-control.md).

- **Auth:** reuse the existing HMAC-SHA256 assertion primitive
  (`server/assertion_issuer.gd` / `server/assertion_validator.gd`,
  `shared/session_assertion.gd`). Add an operator-scoped issuer/audience
  (`project0-console` -> `project0-server`) keyed by a new `PROJECT0_OPERATOR_SECRET`
  (co-locatable in `/etc/project0/assertion.env`). Exclude password/PBKDF2, session
  registry, and account-in-DB checks (operator auth is stateless).
- **In-Godot control transport:** cheapest authoritative path is an **authenticated
  ENet RPC** (new `receive_operator_control_intent(token, action_kind, payload)` on
  `NetworkClient`), validated before dispatch. No new network stack. Reject the watched
  command file (polling latency) and localhost HTTP endpoint (needs an HTTP stack).
  There is **no per-action authorization today** — any connected peer can call any RPC;
  the control seam must add it.
- **systemd / host control:** use a **mounted host-side helper script** mirroring the
  `ci/host-firewall-helper.sh` + `scripts/project0-host-firewall.service` precedent, run
  under the host's existing `SUDO_NOPASSWD`, exposing `restart|stop|start|status <unit>`
  for `project0-server` / `project0-login`. Reject SSH-from-container, privileged
  sidecar, and D-Bus mount (heavier, no precedent). Servers run non-root `godot`
  (UID 10001) via `deploy/game-server/docker-compose.yml`; `stop_grace_period: 20s`.

Feeds ticket 07 (operator-token auth) and ticket 02 (control-seam split).
