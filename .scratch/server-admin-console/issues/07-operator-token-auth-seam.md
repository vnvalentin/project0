Type: grilling
Status: open
Blocked-by: 02-admin-action-catalog-and-control-seam, 03-research-auth-and-systemd-control

## Question

Decide the **operator-token auth + authorization seam** that guards tier-2 control
actions (ticket 02) — the single privileged boundary, sized minimally for LAN use but
shaped so production RBAC is a later extension (not a rewrite).

Sub-questions to resolve here:

- **Credential mechanism.** Reuse the assertion-secret primitive (findings from ticket
  03) — a shared operator secret in an env file verified by a validator seam — or a
  distinct operator token? One secret for all actions, or per-action-class scopes?
- **Where auth is enforced.** At the in-Godot control seam (for kick/drain/reload/
  degraded) and at the host helper (for systemd lifecycle) — confirm both executors
  independently verify the operator credential; the console is never trusted to
  self-authorize.
- **Audit + idempotency.** Every accepted/rejected action logged with actor, action,
  target, timestamp, result; retries idempotent. What is the audit record shape and
  where does it land?
- **Extension path to RBAC.** What seam is left so multi-operator roles/permissions drop
  in later without changing the action contract (e.g. an `operator_identity` +
  `granted_scopes` abstraction that today resolves to a single all-scopes token)?

Recommended direction: a bounded `OperatorAuth` seam reusing the assertion-secret
primitive — one signed operator token carrying `operator_identity` + `granted_scopes`
(today: a single all-scopes local operator), verified **independently** by both the
in-Godot control seam and the host helper, every action audit-logged and idempotent;
RBAC later swaps the token issuer without touching `ControlAction`/`ControlResult`.
Confirm or revise at resolution.

## Answer

_Pending._
