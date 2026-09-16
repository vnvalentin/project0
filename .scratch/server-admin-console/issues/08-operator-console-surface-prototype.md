Type: prototype
Status: open
Blocked-by: 02-admin-action-catalog-and-control-seam, 04-per-server-telemetry-content, 06-server-registry-and-onboarding

## Question

Decide the **operator-console surface** — what the admin screens look like and the
console's own tech shape — by making a cheap, rough, concrete artifact to react to
(call the `prototype` skill). Premise (settled): a new standalone service, Python
**stdlib `http.server`**, Docker, LAN bind, read-only mounts, reusing the Flow
Dashboard's patterns (`dashboard/app.py`) but a separate image/port.

Sub-questions to resolve here:

- **Screens / layout.** A fleet overview (one card/row per registered server: type,
  status, liveness, key gauges) plus a per-server detail view (full core + typed
  extension + action buttons). Sketch it with mock snapshot data.
- **Refresh model.** Poll interval for reading snapshots (align with the ~0.5 s write
  cadence?), and how staleness/dead servers render.
- **Action UX.** How tier-2 actions appear (buttons per server), the confirm step for
  destructive actions (restart/stop), and how the operator token is supplied to the
  console (env var / mounted secret) — display only, real auth is ticket 07.
- **Tech shape.** Confirm stdlib `http.server`, separate Dockerfile/compose + LAN-bind
  env pattern mirrored from the dashboard, read-only mounts of the snapshot dir; no new
  framework dependency.

Recommended direction: prototype a two-view stdlib-HTTP console (fleet overview +
per-server detail) rendering mock `OpsSnapshot` data, with disabled/confirm-gated action
buttons, packaged like the Flow Dashboard (own Dockerfile, own port, LAN-bind env,
read-only snapshot mount). Link the prototype as an asset; capture the accepted layout +
tech decisions in the answer. Confirm or revise at resolution.

## Answer

_Pending._
