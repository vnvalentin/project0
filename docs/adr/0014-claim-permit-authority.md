# ADR 0014: Durable explicit claim and permit authority

Status: Accepted for the bounded #850 implementation in the authorized M3 session; runtime integration acceptance remains pending.
Date: 2026-10-02
Governing issue: https://github.com/vnvalentin/project0/issues/850

## Context
M3 must reject in-flight actions when explicit permits or active membership change after interaction start. An in-memory permission snapshot alone cannot provide a final atomic persistence gate. The user explicitly rejected implicit access through group/faction membership and required both start and final checks.

## Decision
Use server-only ClaimPermitAuthority on the existing world Canon SqliteStore. Add separate claim, explicit permit, membership projection/revision, and immutable operation-receipt tables. Keep plot claims and grants distinct from item identity. Only trusted upstream server code ingests membership projections; the network command surface never accepts client-authored roles or memberships. Membership projection updates, permissions and action writes serialize through the same SQLite transaction boundary.

Each plot has one primary owner. Named Character/Party/faction-role permits carry known positive permission bits. Explicit permit administrators act as stewards and cannot delegate rights they do not hold. Ownership transfer remains primary-owner-only. Revisions bind a server-held ephemeral interaction handle to both initial permission and membership observations. Final authority reads inside the write transaction reject stale/revoked state before invoking action writes. Process restart discards pending handles; committed audit receipts survive for deterministic replay rejection.

## Consequences and limits
This adds durable authority state and needs explicit schema setup outside action measurements. No schema migration or production wiring is performed by the component increment. Plot existence, Area3D bounds, authenticated dispatch, real upstream membership events and item/world integration remain their owning issue's work. Repositories are composed with the same SqliteStore; no nested transaction is permitted.

## Retention and rollback
Committed claim/permit changes and operation receipts remain durable audit history; revocation removes a current grant but retains its immutable audit receipt. Membership projections retain current membership and revisions; their update receipts retain change attribution without tokens or account secrets. No player secret is persisted. Ephemeral interaction handles are never durable. No automatic history deletion is introduced. Revert/disable consumers to roll back adoption, retaining authority/audit tables for recovery; never drop live tables as rollback. All validation uses temporary isolated databases and removes fixture files on teardown.
