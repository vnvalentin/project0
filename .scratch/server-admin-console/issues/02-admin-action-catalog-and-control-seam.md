Type: grilling
Status: open
Blocked-by: none

## Question

Fix the **tier-2 admin-action catalog** (which control actions the console can perform)
and the **shape of the server-side control seam** that executes them — bounded, audited,
idempotent, and never bypassing server authority (CLAUDE.md).

Sub-questions to resolve here:

- **Action catalog.** Confirm the in-scope set and pin each action's exact semantics,
  inputs, and result: process lifecycle (**restart / stop / start** a unit), connection
  control (**kick a peer**, **drain** = refuse new connections), **reload versioned
  tuning data**, **toggle degraded** status. Which are per-server (in-Godot) vs.
  host-level (systemd)? Explicitly excluded: in-game GM powers, Canon/progression
  mutation.
- **Seam split.** Two distinct executors: (a) **host/systemd actions** (lifecycle) that
  live outside Godot — a host-side helper the console calls (see the
  `ci/host-firewall-helper.sh` + `scripts/project0-host-firewall.service` precedent);
  (b) **in-process actions** (kick/drain/reload/degraded) that must be an authoritative
  Godot control seam on the server. Confirm this split.
- **Result contract.** Each action returns a bounded typed result (accepted / rejected +
  reason enum), is **idempotent** under retry, and emits audit telemetry. What is the
  common action-request / action-result shape?
- **Ordering vs. auth.** This ticket owns *what the actions are and their result shape*;
  ticket 07 owns *who is allowed and how they authenticate*. Keep auth out of here.

Recommended direction: catalog = {restart, stop, start, kick_peer, drain, reload_tuning,
set_degraded}; split into a **host-helper executor** (systemd lifecycle) and an
**authoritative in-Godot control seam** (the rest); one versioned typed
`ControlAction` request → `ControlResult` (accepted/rejected + reason) contract, every
action idempotent and audit-logged. Confirm or revise at resolution.

## Answer

_Pending._
