# Map: Server Admin & Telemetry Console

## Destination

A locked, handoff-ready **spec + decision set for a fleet operator console**: a
standalone LAN service that shows **current-state telemetry** for every Project0
server (login, world/game, and any server built later) and performs a **bounded set
of authenticated control actions**. The map fixes the versioned ops-snapshot
contract, the per-server telemetry content, the transport, the server registry, the
admin-action catalog + operator-auth seam, and the console surface — ready for
downstream build slices to consume.

Planning only (plan-not-do): this map decides the contracts and shapes; it does not
build the console or the endpoints. The map is complete when every decision below is
sharp enough to open implementation slices safely, captured in a capstone ADR + spec.

## What Good Looks Like

- [x] A versioned ops-snapshot contract defines current-state telemetry for every Project0 server.
- [x] Tier-1 transport, server registry, and per-server telemetry content are decided.
- [x] Authenticated control actions are bounded, authorized, audited, and separated from public traffic.
- [x] The operator-console surface is specified and captured in a capstone ADR/spec for downstream slices.

## Notes

- **Domain:** Godot 4 GDScript 2.0 strict typing; server-authoritative per
  [CLAUDE.md](../../CLAUDE.md). "The server owns outcomes"; telemetry must be bounded,
  versioned, and server-owned; admin/control actions never bypass server authority.
- **Skills per ticket:** consult `grilling` + `domain-modeling` for every decision
  ticket (keep `CONTEXT.md` terms in sync inline); `codebase-design` for the
  contract-seam tickets (01, 02, 05, 07); `prototype` for the console-surface ticket
  (08); `research` for the auth/systemd ticket (03).
- **Tracker:** local markdown under `.scratch/server-admin-console/`. No native
  blocking, so each ticket declares a `Blocked-by:` frontmatter field; the **frontier**
  is every open ticket whose blockers are all resolved. The Flow Dashboard reads this
  map + its issues.
- **Settled premises (destination-naming + frontier grill, 2026-09-15):**
  - Plan-not-do: end state is a spec + decisions handed to downstream slices.
  - Tiered scope: **tier 1 = read-only telemetry** (ship first); **tier 2 =
    authenticated control actions**.
  - Surface: a **new standalone operator-console service**, separate image/port from
    the Flow Dashboard, reusing its patterns (Python **stdlib `http.server`**, Docker,
    LAN bind, read-only mounts) — the dashboard is `http.server`, not Flask.
  - One **reusable versioned ops-snapshot contract + a server registry** so any future
    server plugs in; extends the existing `ServerHealth` / `HealthReporter` seam.
  - **Tier-1 transport = extend the health-file snapshot**; promote to an HTTP read
    endpoint only if the file path proves insufficient.
  - **Admin actions in scope:** process lifecycle (systemd), peer kick/drain, tuning
    reload, degraded toggle. Auth via a **single bounded operator-token control seam**
    from day one, shaped so production RBAC is a later extension.
  - **Dev/LAN-only now** (single host `192.168.1.254`), not precluding production later.

  The capstone handoff is locked in [spec.md](spec.md) and
  [ADR 0010](../../docs/adr/0010-server-admin-console.md). Downstream work is
  reserved as Slices 184-190.
- **Existing anchors (go-and-see):**
  - `ServerHealth` snapshot — status / tick_rate / uptime / connected_peers /
    max_peers / app_schema_version / timestamp (`server/server_health.gd`).
  - `HealthReporter` writes the health JSON file (`server/health_reporter.gd`).
  - Both servers write health files: game (`server/server_main.gd`) + login
    (`server/login_server_main.gd`, `user://login_health.json`).
  - Flow Dashboard precedent — stdlib `http.server`, Docker, LAN bind
    (`dashboard/app.py`).
  - systemd units: `project0-login`, `project0-server`, `project0-host-firewall`,
    `project0-enrollment`; host `192.168.1.254` reports `SUDO_NOPASSWD=yes`.
  - Assertion secret infra: `/etc/project0/assertion.env`,
    `server/assertion_issuer.gd` / `server/assertion_validator.gd`.

## Decisions so far

<!-- one line per closed ticket: gist + link -->

- [03 — Research: auth & systemd control](issues/03-research-auth-and-systemd-control.md):
  **reuse the HMAC assertion primitive** for an operator token (new
  `project0-console` -> `project0-server` scope, `PROJECT0_OPERATOR_SECRET`); in-Godot
  control via an **authenticated ENet RPC** (no per-action auth exists today); host
  systemd control via a **mounted host-side helper** mirroring the firewall-helper
  precedent under the existing `SUDO_NOPASSWD`.
  [Findings](research/03-auth-and-systemd-control.md).

## Not yet specified

<!-- in-scope fog; graduates as the frontier advances -->

- **Andon / alert surfacing rules** — which emitted CLAUDE.md telemetry / Andon
  signals the console highlights as warnings vs. normal state. Sharpens after the
  per-server telemetry content ([04](issues/04-per-server-telemetry-content.md)).
- **Optional short rolling recent-window** in the ops snapshot (a few minutes of
  in-memory samples, not historical storage). Decide after the transport
  ([05](issues/05-tier1-transport.md)).
- **Downstream build-slice sequencing** — the ordered implementation slices and their
  SLICE-REGISTRY numbers. Graduates at the capstone
  ([09](issues/09-capstone-adr-spec-handoff.md)).

## Out of scope

<!-- ruled beyond the destination; never graduates -->

- Long-term **metrics history / time-series storage & charts** (this is a current-state
  console, not an observability platform).
- **Alerting / paging** routing & notification (signals are surfaced, not dispatched).
- **Multi-host orchestration** (single host now).
- **In-game GM / moderation tooling** and any **Canon / progression mutation**
  (gameplay domain, separate effort).
- **Full production RBAC** (the tier-2 operator-token seam is designed to extend into
  it, but RBAC itself is a later effort).
