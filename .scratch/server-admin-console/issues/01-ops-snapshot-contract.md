Type: grilling
Status: open
Blocked-by: none

## Question

Define the **versioned, server-owned "ops snapshot" contract** — the read model the
operator console consumes — as an extension of the existing `ServerHealth` snapshot
(`server/server_health.gd`), and fix its **extension mechanism** so any future server
type plugs in.

Sub-questions to resolve here:

- What is the **generic core** every server reports? Baseline from `ServerHealth`:
  `snapshot_schema_version`, `status`, `tick_rate`, `uptime_seconds`, `server_tick`,
  `connected_peers`, `max_peers`, `app_schema_version`, `timestamp`. What must be
  added to the core (e.g. `server_type`, `server_id`, `server_version`/git sha,
  `bind_address`/`port`, `pid`, degraded-reason)?
- What is the **extension mechanism** for per-server-type fields (ticket 04 fills the
  content)? A bounded typed sub-dictionary keyed by `server_type`? A separate versioned
  `extension_schema_version`? How does the console render an unknown extension safely
  (fail-open display, never crash)?
- How does this **relate to `ServerHealth`**? Extend `ServerHealth.build_snapshot`
  in place, or wrap it in a new `OpsSnapshot` deep module that composes the health
  snapshot + extensions? Keep it pure/server-only per CLAUDE.md Shared Contracts.
- **Versioning + fail-closed rules:** finite/bounded fields, unknown enums rejected,
  incompatible `snapshot_schema_version` handled by the console how (skip vs. show as
  "unreadable")?

Recommended direction: a new pure server-only `OpsSnapshot` module that **composes**
the existing `ServerHealth` core (unchanged) plus a bounded, typed, per-`server_type`
extension block carrying its own `extension_schema_version`; the console renders the
core generically and each known extension with a small typed view, degrading to a raw
key/value display for unknown/incompatible extensions. Confirm or revise at resolution.

## Answer

_Pending._
