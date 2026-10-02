---
status: proposed
---

# Typed atomic item ledger in world Canon

For [#1341](https://github.com/vnvalentin/project0/issues/1341), implement
[decision #306](https://github.com/vnvalentin/project0/issues/306#issuecomment-5736961246)
with a server-only repository over the world Canon SQLite store. One transaction
commits an item change, every affected owner/location revision and the original
bounded actor-scoped operation receipt. Retired GUIDs remain reserved forever.

Use typed columns for closed definition/instance fields and receipts. Reconstruct
and validate integer values exactly; JSON float coercion must not weaken the
closed contract or silently lose values above 2^53. Preserve fixed effect numeric
type with storage metadata rather than adding a domain field. Public real-SQLite
boundary tests must establish this representation before other ledger behavior
depends on it.

An immutable receipt binds logical intent, identifiers and expected revisions,
excluding only server-assigned processing/acquisition/retirement ticks. Retry
returns the original typed result before checking subsequently changed state.
Changed intent conflicts without writes. Retirement validates its expected active
snapshot against persisted state before DML.

Compared with JSON-only snapshots, typed columns require more explicit mapping
but preserve integer identity and SQL uniqueness/revision constraints. Compared
with generic Canon mutation callbacks, explicit creation/retirement commands
keep transaction ownership and atomic receipts in one module.

This increment admits Equipped and LootPosition creation; Carried fails
capacity_not_configured until a separate immutable authored capacity profile is
specified. Validated server commands remain responsible for authentication,
recipient, permission and acquisition facts. Existing ItemContract, closed
ItemInstance, #306 and the approved static creation property are unchanged.
Production startup, live schema adoption, crafting, transfers and duplicate-result
presentation remain later integration. Rollback is a reviewed revert before
adoption; no existing database is migrated by this increment.
