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

Batch composition refinement: closed item-operation batches may own the shared transaction and call authorize_commit(actor, server_handle), which requires SqliteStore.is_managed_transaction_active(), rechecks authority, consumes the actor-bound handle and performs no DML. commit_interaction remains a convenience for synchronous trusted server writers. No nesting or public arbitrary item/SQL mutation API is added.

Batch authorizer RED missing specific seam; GREEN6/6 with direct-statement observation OBSERVED and all attempt counts zero for the authorization-only transaction. Outside managed transaction returns transaction_required. Evidence build/validation/850/{red,green}-batch-authorizer.{xml,log}.

Permit revocation: RED retained the formerly admitted action after unsupported revoke; GREEN7/7. Revocation changes the claim revision; final rejection is stale_authority before writer invocation. New #1347 counters report OBSERVED with zero INSERT/REPLACE/UPDATE/DELETE attempts for rejection. Evidence build/validation/850/{red,green}-revoked-permit.{xml,log}.

Permit receipts: RED showed stale-revision retry instead of duplicate receipt; GREEN8/8 with immutable actor-scoped result lookup before current authority/revision checks, exact receipt recovery after reopen, changed-intent conflict, and OBSERVED zero replay DML. Grant/revoke + claim revision + receipt share one transaction. Runtime logs reject script/compiler errors even if GUT exits0. Evidence build/validation/850/{red,green}-permit-receipt.{xml,log}.

Membership receipts: RED9 exposed revision_mismatch for a previously accepted membership event; GREEN9/9. Trusted ingestion scopes are disjoint from player permit scopes, membership ordering is canonical, and receipt lookup precedes current revision checks. Replaying a join after a leave returns the original result without restoring membership; changed event payload conflicts and OBSERVED attempts remain zero. Evidence build/validation/850/{red,green}-membership-receipt.{xml,log}.

Durable audit payload: RED10/one missing request_json column; GREEN10/10. New additive, unreleased fixture schema retains canonical accepted intent beside its hash, actor scope, target and result revision. Restart reads preserve exact request bytes, and damaged receipt/hash pairs reject without DML. No existing database migration is performed. Owned focused runner now retains exact counts, runtime marker checks, isolated state and cleanup results for both RED and GREEN.

Provisioning receipts: RED11/four assertions exposed a second plot minted by reusing a provisioning operation ID plus missing immutable result/audit. GREEN11/11 now reads receipts and existing claim within the transaction and atomically stores the first claim + canonical provisioning audit. Reuse with different intent conflicts and all replay/conflict attempts remain zero DML. Provisioning receipt scope is server-only and disjoint from Character/membership operations.

Ownership-transfer scope refinement is recorded in #850 issuecomment-5954830842 before implementation: primary-owner-only, named different Character, existing explicit grants retained until revoked, claim revision invalidates pending handles, immutable actor-scoped audit/replay. No client identity assertion or live-state mutation is introduced.

Owner transfer: RED12 missing command; GREEN12/12. Steward/visitor rejection observes zero DML; primary owner update + receipt commits exactly one UPDATE and one INSERT. Old handles reject stale, old implicit owner rights end, named new owner gains rights and explicit visitor grants remain. Reopen returns exact transfer and original provisioning receipts, changed recipient conflicts, and all replay reads produce zero DML. No live database or client identity endpoint is involved.

Root-cause learning — receipt result corruption: independent ledger review exposed a shared failure hypothesis, then permission public-seam RED13 confirmed eight valid-shaped target/revision mutations were incorrectly returned as duplicate original results. Schema/type validation and matching request hashes did not bind retained result metadata to the original operation. Earlier tests covered damaged request hashes and clean replay, not independent receipt result damage. Every provisioning, membership, permit and transfer receipt now checks its target/revision against deterministic original request expectations, without recomputing current state. GREEN13/13 verifies recovery after reopen, retained corruption and OBSERVED zero DML for every rejection. Evidence build/validation/850/{red,green}-receipt-metadata.{xml,log}. Full suite/review and physical/action integration remain pending.

Additional public acceptance controls passed16/16 without production changes (characterization, not a claimed RED). Faction access requires the exact explicitly permitted role plus current membership; role replacement invalidates the final gate with zero DML. A limited steward can delegate entry but cannot escalate its own rights or revoke rights it does not possess. Native CHECK failure on the final audit INSERT rolls back the earlier grant INSERT and claim UPDATE; OBSERVED attempted2INSERT+1UPDATE, failed1INSERT, rolledback1INSERT+1UPDATE, committed0. Reopen confirms unchanged ownership/revision/grants/audit, and a healthy new operation succeeds. Evidence build/validation/850/green-policy-and-rollback.{xml,log}.

Closed/corrupt-state RED18 confirmed non-String subject kind and control-bearing IDs could pass the closed contract, an out-of-domain claim revision was accepted, and a contradictory two-Party membership projection could be silently replaced. GREEN18/18 enforces exact subject kind type and control-free bounded IDs, fully validates retained claim identity/revision, and shares one bounded membership snapshot validator between access and trusted updates. Damaged state is retained and rejected before DML, including after reopen. Prior happy-path/revision tests did not include these adversarial types or cross-row projection violations. Null/closed stores now fail not_open, and failed/colliding entropy fails closed before allocating a handle. Evidence build/validation/850/{red,green}-closed-and-corrupt.{xml,log}; integration/full/review remain pending.

Transaction/handle controls: GREEN20/20 public tests. Raw BEGIN and an already ended native transaction cannot satisfy the managed final gate; closed/null stores return not_open; a recreated authority after database reopen rejects the old ephemeral handle while allowing a fresh owner interaction. Membership set ordering is canonical for immutable replay with zero DML. These are additional passing characterization controls, not claimed RED cases. Real process restart and actual station/session teardown remain integration gates.

Scoped write evidence is now retained for every asserted permission observation when the owned evidence environment path is set. The focused20/20 run emits the explicit manifest in observation-manifest.json, checking every report OBSERVED and native row effects NOT_OBSERVED; assertions remain at the public store/authority seam. This adds test evidence capture only, with no product behavior change.

Final validation preparation integrates accepted main b1734450ba03df7f1818b966409f14658dba2b93 (anchor PR1385 plus docs-only ADR0013 PR1395). The full new domain decision was read: it preserves existing v1-v5 Canon and excludes dungeon interiors, so no permission contract changes. A moving-main guard stopped before any initial integration; fresh remote read established the exact accepted revision. Explicit full plan enumerates157 scripts and passes ownership preflight; captured native preparation is script-error-free, focused20/20 and25 retained OBSERVED reports pass, record-sync exits0. The owned full wrapper invokes the standard script, captures import/runtime diagnostics, checks exact script coverage/JUnit/observation manifest, binds start/end source and clean tree, and records teardown on success/failure. Full and independent Standards/Spec review remain required at the ensuing frozen revision.

Accepted-main521 inventory correction: full ownership plan had157scripts and omitted the newly accepted M4parity integration test. Static preflight checks ownership but did not detect inventory completeness. Countermeasure: exact set equality against current unit/integration test discovery (158scripts) before final execution; refresh plan without changing application or test behavior. Native validation remains pending.


### Owned evidence lifecycle status

The owned validation evidence correction and reproducible copied controls are prepared. Copied checks and static delivery checks passed; detailed records remain local. Initial preparation failed and was corrected before the passing check. Application behavior is unchanged. Final-source independent review and native/full delivery gates remain pending; no milestone completion is claimed. The governing correction is recorded on #850, with the coordinator owning review and runtime scheduling.

Accepted main is integrated. Static delivery checks passed after integration; application and owned evidence logic are unchanged. Final-source independent review and native/full validation remain pending. Detailed evidence remains local.

### Preparation gate correction status

The owned preparation gate correction is prepared and reproducible source-only controls passed. Static delivery checks passed. Application behavior is unchanged. Detailed evidence remains local; independent review and native validation are pending. No slice or milestone acceptance is claimed.

### Accepted integration status

The accepted main integration is preserved with the owned evidence correction. The full validation inventory and static ownership checks are refreshed. Application behavior is unchanged by this correction; independent review and native validation remain pending. Detailed evidence stays local.
