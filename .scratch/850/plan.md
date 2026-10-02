# #850 Durable claim and permit authority

Governing issue: https://github.com/vnvalentin/project0/issues/850
Accepted policy: issuecomment-5953622657. Implementation brief: issuecomment-5953856234.
Parent #838 / Theme #749. Milestone 3, slice M3.1.
Base a2785a27562670c80a5db37430555ecc9d9d3b20 includes item contracts and #1379 rollback enforcement.
Harness main guidance: 77de008a0f28eb91726527d543adb435735a2157. Foundation marker absent; active setup records complete. Existing dirty main checkout and Mac lane preserved.

## Outcome, SDD and scope
Explicit server-issued grants govern interaction start and final atomic writes. Membership alone never grants access. The server-only ClaimPermitAuthority owns closed permission bits, one primary owner per provisioned plot, explicit Character/Party/faction-role grants, durable versioned membership projections and immutable actor-scoped operation receipts. Membership projection ingestion is trusted server authority, never a player command. Start handles are server-held, ephemeral and revision-bound; final grant and membership reads share the same SQLite transaction with the write body. A steward is explicitly granted permit-administration rights and cannot delegate rights it lacks; only the primary owner transfers ownership.

## BDD / TDD sequence
1. Trusted plot registration authorizes its primary owner and rejects a visitor.
2. Explicit Character/Party/faction-role permits plus active membership; membership without a grant fails.
3. Permission revocation and membership revision changes after start reject before the write body.
4. Closed fields, unknown/zero/negative bits, stale revisions and steward escalation reject before DML.
5. Atomic grant/audit and ownership transfer; deterministic duplicate receipts without more writes.
6. Real SQLite failure rollback and close/reopen parity. Exact zero-DML assertions depend on accepted #1347 observation accounting; never substitute legacy Canon-only counters.
Each behavior retains RED then minimal GREEN at the public seam. Exact source validation and independent Standards/Spec review precede merge.

## Persistence / authority / rollback
ADR0014 records additive claims, grants, memberships/revisions and immutable receipts. No existing database is opened, migrated or deployed by this increment. Plot existence linkage, actual Area3D/authenticated RPC integration and upstream membership management remain separate governing-issue integration work. Revert/disable the consumer while retaining records; fixture tests close and delete DB/WAL/SHM/journal and own XDG_DATA_HOME under build/validation/850. #850 stays open pending complete integration evidence.

## Validation
Linux 192.168.1.254 through verified okami.tail02bdf2.ts.net only. Existing Godot4.3 and godot-sqlite; no dependency install. validation-plan.json explicitly selects focused tests and full GUT. Preflight before execution. Full-GUT slots serialized by coordinator. DASHBOARD_RESULTS_DIR is worktree-owned, never the live dashboard.

## Root-cause learning
No unexpected defect yet. New-seam absence is the planned first RED; later failures will be recorded with public-seam evidence and corrected before completion.

First owner/visitor seam: RED one test failed on absent public seam; GREEN one test passed with real SQLite. Evidence build/validation/850/{red,green}-owner.{xml,log}. No fixture databases remained. This is only the first vertical increment; explicit permits, final checks, audit and replay remain in progress.

Explicit Party grant increment: RED two missing-method assertions; GREEN2/2 real SQLite public tests. Membership alone, a nonmember, and ungranted bits reject. Evidence build/validation/850/{red,green}-party-permit.{xml,log}. Final-commit checks and immutable audit receipts remain the next vertical increments.

Final authority gate: RED one missing-seam assertion; GREEN5/5 public SQLite tests. Membership change after start returns stale_authority before the writer executes; cross-actor handle use, repeated completion, cancelled handles and ignored SQL failure are rejected/rolled back. Evidence build/validation/850/{red,green}-final-gate.{xml,log}. The callback is server-only, synchronous and uses the same store; nested transactions are explicitly unsupported.
