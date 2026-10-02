# #849 bounded interior anchor increment

Governing issue: https://github.com/vnvalentin/project0/issues/849
Parents: Feature #838, Theme #749, Vision #495.
Milestone 3: Authoritative Content Systems; Slice M3.1: Spatial Facility Authority.
Branch: slice/849-interior-anchor-contracts.
Base: 4715092ecae5e7808c2fc019eb21002b0ce00955.
Owning execution host: Linux server 192.168.1.254, reached through the verified equivalent okami.tail02bdf2.ts.net SSH endpoint.
Harness guidance consumed: main 77de008a0f28eb91726527d543adb435735a2157.
Foundation: checklist complete; marker absent; active-file placeholder scan has no matches. Existing original Linux checkout and unrelated dirty Mac lane are preserved.

## User outcome and current boundary

A server-authored interior anchor and first cell can be resolved from its exterior Canon structure and reload unchanged after SQLite closes and reopens. This is an executable persistence increment beneath #849, not acceptance of player entry, workshop authority, all #849 criteria, Slice M3.1 or Milestone 3.

Unacceptable outcomes: client-authored identity or bounds, orphan interior records, ambiguous exterior binding, partial anchor/cell storage, replacement of base Canon, permissive recovery from incompatible persisted records, or claiming spatial/permission runtime acceptance from schema tests.

Hypothesis: a small closed shared value contract and one server-owned repository can bind deterministic interior identity to effective Canon while making persistence, rejection and rollback observable at public seams.
Cheapest discriminating check: real isolated Linux SQLite registration, exterior-reference resolution and reopen parity, followed by a failed second INSERT proving neither anchor nor initial cell survives.

## Approved SDD

Public seams: shared InteriorAnchorContract.parse_server_descriptor()/parse_entry_intent() and typed normalized value; server InteriorAnchorRepository(store).ensure_schema(), register_anchor(server_descriptor), get_anchor(interior_id), resolve_entry(exterior_reference_intent).

Closed version 1 fields represent a bounded server-issued plot_id, canonical exterior sector_id and stamped structure GUID, server-authored finite entry anchor in world yards, initial integer XYZ cell coordinate, finite positive world-yard AABB containing entry, bounded opaque streaming reference, schema/revision metadata. Repository derives interior_id through existing UUIDv5 helper from a canonical ordered [sector_id, entity_guid, plot_id] tuple. Initial anchor/cell revision is 1; observed exterior mutation revision is derived from the successfully loaded ordered mutation log. Exact field spellings and representation are routine implementation choices; product/security rules are not inferred.

A client entry intent contains only supported schema_version and exterior sector/entity reference. Unknown fields, including any interior_id, plot_id, cell geometry, revision or streaming reference, are rejected. This does not add an RPC or authorize entry.

Two additive tables store anchors and cells. Exterior sector/entity reference is unique; cell has a foreign key to its anchor and unique interior/cell coordinate. Registration validates shape before DML, loads immutable Canon and mutation history, resolves live effective structure identity, detects existing anchor replay/conflict, then uses one SqliteStore.transaction for final authority reads and both parameter-bound INSERTs. Exact identical server registration returns existing record read-only; changed content conflicts. CanonRepository is used for reads only, never nested canonicalization, UPDATE or restore. SqliteStore is not modified.

get_anchor and resolve_entry use read-only lookups and validate persisted version/shape rather than guessing; destroyed or missing effective exterior structures do not resolve as valid entry references. Returned contract copies cannot alter persisted state.

## BDD / TDD sequence

1. Given immutable Canon with a live exterior structure, when the server registers its anchor and first cell, then resolving the exterior reference returns the server-derived identity and exact descriptor; closing/reopening returns the same value and unchanged base Canon.
2. Given the committed anchor, exact server replay returns idempotent read-only data; conflicting content or a duplicate exterior binding is rejected with no DML.
3. Given missing/destroyed exterior Canon or invalid/nonfinite/unsupported geometry, registration rejects before DML and no resolvable interior exists.
4. Given a forged client intent with interior_id or bounds, resolve_entry rejects before DML; a valid exterior reference cannot select a different identity.
5. Given an injected failure on the initial cell INSERT, registration reports rollback and neither anchor nor cell is observable through repository methods after reopen.
6. Given malformed/incompatible persisted data, lookup fails closed and leaves records preserved.

TDD starts with one failing public-seam repository test, then the smallest implementation, then additional behavior cycles. Pure contract tests cover only parsing and derivation that support the repository. Real SQLite integration proves storage; no private members or database-side assertions substitute for repository behavior. Statement evidence uses the independently owned database-wide SqliteStore accounting when available; old canon-only counters do not prove zero new-table DML.

## Dependency and ownership boundaries

Own: shared/interior_anchor_contract.gd, server/interior_anchor_repository.gd, tests/unit/test_interior_anchor_contract.gd, tests/integration/test_interior_anchor_repository.gd, docs/adr/0016-interior-anchor-and-cell-persistence.md, .scratch/849 planning/validation evidence references.
Do not edit SqliteStore, #1341 item contracts, existing workshop experiment files, clients, Windows launcher/packaging, Canon base or mutation repositories.

Plot ID existence/ownership and CLAIM/PERMIT evaluation depend on #850. Active Area3D initialization/final-commit binding and station authority depend on #951/#1347. Streaming references are persisted identity data, not loading/geometry assembly. This increment does not publish player entry, grants, station actions or loot/crafting behavior. #849 remains open for the remaining acceptance and integration.

## Persistence ADR and rollback

A linked ADR will record additive schema, deterministic identity, immutable first registration and fail-closed recovery. Existing ADR0003 world yards and ADR0012 exterior placement remain unchanged. No live database is opened or migrated. Tests use isolated XDG_DATA_HOME and unique bare user-relative database names; close handles and remove owned DB/WAL/SHM/journal files after each test and remove the owned temporary directory in shell cleanup. Evidence is retained outside temporary state. Production rollback disables the consumer/reverts code while retaining durable anchor records; no automatic DROP, downgrade, Canon rewrite or user-state deletion is introduced.

## Validation plan

Required plan preflight: python3 scripts/check_validation_ownership.py --plan .scratch/849/validation-plan.json --output build/validation/849/plan-ownership.json, after the selected first failing test exists. No Godot execution before preflight and root design review.
Focused: bounded GUT selection of only the new integration/public contract scripts on the owned Linux host, with JUnit, command/result and cleanup evidence under build/validation/849 and isolated XDG_DATA_HOME/DASHBOARD_RESULTS_DIR.
Full: scripts/run_gut_validation.sh, serialized with root; then scripts/check_record_sync.sh; exact final revision Standards + Spec review before delivery.
No native Windows or paired gameplay acceptance claimed. Missing observations remain NOT_OBSERVED.

## Evidence and root-cause learning

Design review: approved by coordinating agent before product edits. Runtime validation: NOT_OBSERVED. Focused/full/review gates: NOT_OBSERVED. No product edit yet.
No runtime failure has occurred in this increment. Source/path discoveries are not runtime evidence. Record any unexpected validation/runtime failure and its discriminating check here and additively on #849 before completion.

Root-cause learning: initial plan preparation used documented `python`, which is absent on this Linux host (exit 127); no preflight or Godot execution occurred. Existing `python3` resolves and is used explicitly. This is host command naming, not missing SQLite or a client dependency. Countermeasure: exact interpreter pinned in command/plan evidence.

First red evidence: build/validation/849/20261002T134051Z-red-1-30399/focused-result.json and focused.xml. Linux192.168.1.254, Godot4.3.stable.official.77dcf97d8, baseline4715092ecae5e7808c2fc019eb21002b0ce00955; one test ran, one expected failure because repository public seam is absent, exit1, cleanup_verified=true. Ownership preflight passed before execution. This is expected TDD red, not a product/runtime regression.

First green evidence: build/validation/849/20261002T134414Z-green-1-37728/focused-result.json. One repository test ran/passed with exact registration/exterior resolution/reopen parity and unchanged Canon; exit0, cleanup_verified=true. Report captures baseline revision plus SHA256 of the actual test/shared/server sources. Remaining rejection/replay/fault behaviors and full/review gates are not accepted yet.

Replay/conflict red: build/validation/849/20261002T134548Z-red-2-43642/focused-result.json. Two tests ran; new replay/conflict assertions fail because registration currently reports transaction_failed on uniqueness violation. Cleanup verified. Countermeasure is explicit read-only retained-record comparison before any INSERT, not swallowing a failed INSERT.

Replay/conflict green: build/validation/849/20261002T134704Z-green-2-48465/focused-result.json. Two tests passed, exit0, cleanup_verified=true. Exact replay returns retained anchor and a changed plot reference conflicts before any INSERT attempt; database-wide count evidence will bind to the reviewed accounting dependency.

Real SQLite rollback characterization: build/validation/849/20261002T135134Z-rollback-58063/focused-result.json. Three tests passed, cleanup verified. Owned cell CHECK constraint rejected the second INSERT; public lookup/resolution after close/reopen found no anchor, and immutable Canon matched. No trigger or hidden writes were used. This confirms the transaction behavior already implemented in the first green, rather than inventing another red claim.

Orphan characterization: build/validation/849/20261002T135300Z-orphan-60846/focused-result.json. Four tests passed. Missing sector, missing structure and destroyed effective structure reject; the immutable base is preserved. Cleanup verified.

Approved SDD adjustment: InteriorAnchorRepository(store) will construct CanonRepository and CanonMutationRepository bound to that exact store. Removing the two injected repositories prevents qualification from another database and guarantees final authority reads share the write transaction. The coordinator approved this bounded strengthening; it changes no product policy or other module.

Root-cause learning: cross-store composition red report build/validation/849/20261002T135402Z-cross-store-red-65457/focused-result.json (five tests ran, two assertions failed, cleanup verified). Symptom/public seam: injecting Canon/mutation repositories from store A into InteriorAnchorRepository writing store B admitted and resolved a target absent from B. Hypothesis/check: seed Canon only in A, create empty Canon tables in B, attempt registration/resolution through the mixed constructor. Confirmed cause: caller-owned repositories can read a different transaction/handle. Existing tests used only same-store composition and missed it. Countermeasure: simplify constructor to one SqliteStore and internally bind the existing Canon/mutation repositories to it. No live consumer or database was involved; regression will re-run the two-store public seam after the API change. Plot authority and runtime entry remain unresolved integrations.

Cross-store green regression: build/validation/849/20261002T135449Z-cross-store-green-1833/focused-result.json. Five tests passed, including separate-store registration/resolution rejection; exit0, cleanup verified. Constructor now owns both existing read repositories bound to the supplied store. No private Canon dependency or SqliteStore change was added.

Canon-read-failure characterization: build/validation/849/20261002T135533Z-read-failure-3680/focused-result.json. Six tests passed; owned missing history table yielded query_failed on registration/resolution, no anchor was returned, base Canon preserved and cleanup verified. No fallback revision getter is used.

ADR identity corrected to0016 at coordinator request to preserve the unrelated active Mac0013 and other M3 ADR identities. Only the owned anchor ADR/links changed.

Malformed/forged characterization: build/validation/849/20261002T135746Z-malformed-8416/focused-result.json. Seven tests passed; nonfinite/zero bounds, out-of-cell entry, fractional or malformed cell coordinates, unknown/versioned/missing fields and forged client identity/plot/bounds/revision/stream fields reject; existing anchor remains unchanged. Cleanup verified.

Blank-reference TDD RED: build/validation/849/20261002T135905Z-blank-red-14094/focused-result.json. Two scripts ran: one new pure-contract test failed four blank-reference assertions; all seven repository tests passed. The boundary treated whitespace-only opaque fields as nonempty. Countermeasure: reject blank identifiers without changing their opaque spelling. Updated two-script ownership preflight passed; cleanup verified.

Blank-reference GREEN: build/validation/849/20261002T140254Z-blank-green-22200/focused-result.json. Two scripts/eight tests passed, cleanup verified. Identifier admission now rejects whitespace-only fields while preserving nonblank opaque spelling. No authoritative grant or plot verification was added.

Independent identity/alias characterization: build/validation/849/20261002T140432Z-identity-28096/focused-result.json. Two scripts/nine tests passed; known independently computed UUIDv5 fixture matches, JSON parse/serialize parity holds, input/output arrays do not alias, and forged persisted identity/revision fails. Cleanup verified.

Stamped Canon identity characterization: build/validation/849/20261002T140621Z-stamped-33884/focused-result.json. Two scripts/ten tests passed; a committed stamped structure GUID registers/resolves while its legacy derived identifier rejects, and base Canon is unchanged. Cleanup verified.
