---
status: accepted
---

# Server-Owned Interior Anchors And Initial Cells

Issue [#849](https://github.com/vnvalentin/project0/issues/849), under #838 / #749,
owns this bounded persistence increment of Milestone 3, Slice M3.1. The approved
implementation brief records its public seams and unresolved integration.

## Identity, Coordinates And Authority

A supported closed server descriptor binds an exterior canonical sector and
stamped structure GUID to a supplied bounded plot reference, entry point, first
integer XYZ cell coordinate, positive finite world-yard bounds containing entry,
and opaque streaming reference. The plot reference is unverified until #850
integrates plot/CLAIM/PERMIT authority; storing it grants no ownership or access.

The repository derives the opaque interior UUID through the existing UUIDv5
helper and a versioned ordered exterior sector/structure/plot tuple. An exterior
sector/structure has one anchor; changing its plot or geometry cannot silently
replace it. Initial anchor/cell revision is 1, with the observed exterior mutation
revision retained. Integer cell coordinates are stable addresses within an
interior, not a new world-grid conversion. World-yard coordinates retain
[ADR0003](0003-imperial-world-scale.md) and
[ADR0012](0012-sector-detail-placement.md). No existing geometry, sector identity
or blueprint placement is reinterpreted.

Clients may reference only an existing exterior sector and entity through a
closed entry intent. They cannot select an interior identity, plot, bounds,
revision or stream. Parsing that intent and resolving a persisted value does not
authorize entry, grant permissions or create an RPC.

## Persistence And Recovery

Two additive server-only tables store the anchor and first cell in the Canon
store. Bound queries, a unique exterior reference, and an anchor/cell foreign key
preserve the relationship. Registration validates the closed input before DML,
then uses one transaction for final effective-Canon reads and both INSERTs.
Effective existence comes from successfully loaded immutable Canon plus ordered
mutation history qualified by the existing CanonSectorIntegrity base/history
inspectors; unsupported versions, malformed payloads, incompatible replay, read
failure, absent/destroyed structure or conflicting anchor
fails closed. Neither Canon blueprint nor its mutation log is rewritten.

Exact registration replay returns the retained contract without another write.
Conflicting registration cannot replace history. Lookup validates the persisted
schema and deterministic identity; unsupported/corrupt records remain preserved
and produce explicit failure rather than being upgraded or guessed.

Only initial registration and read-only resolution are introduced. Additional
cells, mutable interior overlays, claim ledgers and runtime facility binding need
their own accepted transaction/revision behavior. #849 remains open for those
applicable acceptance and integration requirements.

## Validation And Rollback

Real Linux SQLite tests exercise registration, exterior resolution, exact reopen
parity, rejection/replay and injected second-write failure through the public
repository. Owned temporary XDG data and DB/WAL/SHM/journal state are cleaned;
evidence is retained outside temporary state. No live Canon DB is opened or
migrated during this increment. No Area3D, Windows or paired gameplay acceptance
is inferred.

Reverting/disabling a future consumer preserves durable anchor rows. No automatic
DROP, downgrade, base-Canon replacement or deletion of user state is introduced.
The additive schema shares SqliteStore's supported engine version; each interior
record carries its own supported schema version and incompatible records fail
closed. A future schema migration requires separately reviewed recovery evidence.
