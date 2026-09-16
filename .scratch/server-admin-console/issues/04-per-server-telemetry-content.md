Type: grilling
Status: open
Blocked-by: 01-ops-snapshot-contract

## Question

Using the extension mechanism from ticket 01, decide the **per-server-type telemetry
content** — what each server surfaces beyond the generic core.

Sub-questions to resolve here:

- **Login server** (`server/login_server_main.gd`): what ops-relevant fields? e.g.
  accounts-DB open/health, active sessions, register/login RPC accept/reject counts,
  assertion issuance count/last-error.
- **World/game server** (`server/server_main.gd`): e.g. current sector count,
  provisional sector-request queue depth + last outcome, monster/peer counts, action
  accept/reject counters, Canon insert/conflict counters (from CLAUDE.md's telemetry
  catalog — only what exists or is cheap now, not speculative).
- **Host-firewall / enrollment** units: are these first-class in the console (their own
  extension) or shown as bare systemd status only? Decide their tier-1 depth.
- **Bounded-cardinality rule:** every counter/gauge finite and bounded; no unbounded
  lists, no sensitive player text or secrets (CLAUDE.md telemetry hygiene). Which fields
  are cheap to emit **today** vs. flagged as fog for when the underlying system exists?

Recommended direction: define a small bounded extension per active server type (login,
world) with only presently-cheap fields, mark future-system counters (Canon, magic,
Meridian, etc.) as **Not yet specified** fog rather than speculative fields, and show
host-firewall/enrollment as systemd-status-only for now. Confirm or revise at resolution.

## Answer

_Pending._
