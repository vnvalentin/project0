# #1425 — immutable item creation companion

Governing issue: https://github.com/vnvalentin/project0/issues/1425.
Parent Epic #1341 → Feature #950; Milestone 3, group M3.2 Item Ownership and Transaction Ledger. Related #951/#1347 retain workshop authority and integration. Decision #306 and the accepted authored-rule decision https://github.com/vnvalentin/project0/issues/1342#issuecomment-5956781081 remain unchanged.

Status: records-first freeze only. Root created and read back the issue, Slice label, milestone and Project #2 entry before this plan. Foundation setup is closed; no marker or active foundation placeholders were found. Shared Harness NORTH_STAR/AGENTS guidance already consumed at the verified continuation revision is reused. GitHub issues and Project #2 remain the active records; frozen archives are untouched. Source identities, exact orientation observations and validation results remain in private local evidence.

## Outcome, bounds and hypothesis

The user outcome is durable deterministic creation-time properties associated with one server-owned item GUID, surviving restart without wear or regeneration. Scope is one closed ItemInstance plus an immutable creation companion, immutable authored profile identity, existing owner/location revisions and an actor-scoped committed receipt in one Canon transaction.

The boundary is the existing Linux server ItemLedgerRepository over SqliteStore. Client outcomes, authentication, acquisition and recipient authorization remain caller responsibilities. No live Canon database or production startup is wired. No bag capacity, equip/unequip journey, craft input deduction, physical workshop journey, loot/source/cross-owner policy, random drops, #310 resolution, Windows/client change, production tuning, runtime dependency or deployment is included.

Unacceptable outcomes are partial/orphan records, duplicate GUIDs, DML on rejected/conflicting/replayed intent, altered ItemInstance fields, changed authored content under the same profile revision, numeric coercion, creation-property mutation or rederivation during recovery, live-state access, unqualified evidence or cleanup, and claims of parent/milestone acceptance from this primitive.

Hypothesis: reusing the existing managed transaction and query-failure latch can commit the missing creation companion with the instance, revisions and receipt while preserving the existing logical retry contract. The cheapest discriminating RED is one real-SQLite public creation call followed by close/reopen parity. No application or test edit and no native execution is authorized at this checkpoint; root must first qualify the validation frontier and release the implementation/runtime window.

## One atomic command and one reader

Add `ItemLedgerRepository.create_instance_with_properties(actor, operation_id, active_snapshot, expected_owner_revision, expected_location_revision, authored_profile, creation_inputs)`. It owns exactly one SqliteStore transaction. Validate the authored wire using ItemCreationProfile.from_wire_dict and derive from its closed inputs; clients cannot supply output values. Reuse a private managed-transaction creation body for the existing identity, definition, address, revision and receipt checks rather than nesting the existing create_instance transaction wrapper.

Preserve the current create_instance/retire_instance contracts and legacy records. The new command returns the existing bounded command/receipt shape with operation_kind=create; its fingerprint explicitly discriminates creation-with-properties and includes profile content identity and creation inputs. The existing logical retry rule excludes acquisition server_tick; this slice does not turn a later tick into new intent. A plain legacy creation cannot be silently upgraded on replay. Exact accepted intent returns its original validated receipt with zero DML; conflicting intent rejects. Receipt-result corruption is preserved and rejected rather than repaired.

Add `get_creation_properties(instance_id)` as the bounded server reader, returning a closed stored property payload or an explicit not-found/corrupt-record outcome. Its payload is exactly the existing ItemCreationProfile.derive result: schema_version, profile_id, profile_revision, blueprint_id, blueprint_revision, tuning_version, arithmetic_version, profile_sha256, inputs, values and units. The companion table associates that payload with the instance GUID; ItemInstance's eleven fields remain unchanged.

Persist immutable authored profile identity/content and the companion in additive server-owned tables. A profile ID/revision with different validated content or units rejects before command DML. Use typed INTEGER persistence/reconstruction for arithmetic versions, inputs and derived values; do not round-trip these through permissive JSON floating-point parsing. The companion is written once, never updated by retry, retirement or recovery. Do not invent defaults for older records without companions. SqliteStore already qualifies the ordinary table inventory for statement observation and latches query failures; use those seams without adding triggers, attached databases or observer exceptions. Architecture record rationale: this implements the explicitly accepted separate creation-property interpretation alongside the existing ledger, without changing #306 or granting new authority. Preserve ADR 0015's actual recorded status; any required additive clarification belongs to implementation review.

## Exact fixture and first behavior

Extend the existing tests/integration/test_item_ledger_repository.gd public integration fixture; reuse tests/fixtures/item_creation_profile.gd and tests/unit/test_item_creation_profile.gd. No new production profile exists.

Use the existing character:one owner, equipped/right_hand address, definition:sword@edition:one and active revision-zero instance fixture, with expected owner/location revisions zero. This is a supported creation address, not equipment movement or loot policy. Reuse the authored fixture pins and the already independently worked material_purity=81, catalyst_quality=60, workstation_parameter=40 inputs: purity81, quality65 and durability206. These are authored validation values only, not runtime observations or live balance.

First RED safely checks availability of the named public command, then calls it through the fixture, verifies one instance and companion plus receipt/revisions, closes/reopens the uniquely owned database and asserts exact typed instance/property parity. A missing command is an ordinary failing assertion, not a parse/load failure or silently skipped script. Implement only this behavior, run focused GREEN, commit/push, then take the next logical cycle.

Subsequent cycles cover: failure after instance write before companion completion; failure after companion write before receipt completion; exact replay after reopen; changed profile/input intent; immutable profile-content conflict; malformed/unsupported inputs; stale revisions, illegal address and duplicate GUID; typed corruption rejection without repair; immutable recovery and ordinary retirement. Start qualified DML observation after schema/seed setup and assert zero INSERT/UPDATE/DELETE attempts on every pre-write rejection and retry. Faults use ordinary real-SQLite constraints at the public command boundary, not triggers that invalidate observation coverage. Assert reopened Canon parity after rollback and include all item/profile/companion/receipt/revision tables in the observed inventory.

## Planned commands and execution custody

The ownership JSON declares future selected GUT consumers and full delivery validation. It is not runtime authorization. Before any engine launch, integrate/rebase only the coordinator-qualified preparation/runner corrections from #1396/#1423 and refresh source/platform bounds while clean. Accepted main at this freeze still carries the earlier import runner; its unchecked import path must not be used as a fallback. Root reviews the exact final source and grants the native window.

The future focused job owns a fresh source copy and HOME/XDG directories, source-bound successful two-phase preparation, exact restored configuration, a controlled disabled file-logging override before consumers, bounded child execution, structured verdicts on success/failure and finally cleanup. Preserve unknown source/configuration custody rather than deleting it. Retain evidence outside the temporary database/source root. Use the existing qualified preparation helper; no new framework/dependency is authorized. The private coordinator job must be frozen/reviewed before invocation; the consumer command below alone does not own setup/teardown.

Focused public consumer, only after preparation into the qualified owned_prepared_root:

`timeout --kill-after=15s 180s godot --headless --path "$owned_prepared_root" -s addons/gut/gut_cmdln.gd -gconfig= -gdir= -gtest=res://tests/integration/test_item_ledger_repository.gd,res://tests/unit/test_item_creation_profile.gd -gjunit_xml_file="$owned_result_dir/focused.xml" -gdisable_colors -gexit`

Both selected scripts must appear in JUnit; skipped scripts, script errors, nonzero exit, timeout, missing artifacts, unavailable DML observations or cleanup failures fail closed. Retain a machine-readable focused command verdict, canonical payload parity and attempted/committed/rolled-back/failed DML classifications. Every fixture owns setup and finally closes its store and removes only its uniquely named database/WAL/SHM/journal files. Worktree/runtime temporary state is private and freshly owned.

Full gate, on the actual final source with the qualified standard runner:

`RESULT_DIR=build/validation/1425/full DASHBOARD_RESULTS_DIR=build/validation/1425/dashboard scripts/run_gut_validation.sh`

Source record gate: `bash scripts/check_record_sync.sh`. Ownership plan preflight and source-only record sync may run now; GUT, imports, engine metadata queries, native/Docker jobs and application/test edits may not.

## Acceptance and continuation

Independent Standards and Spec review, focused real-SQLite evidence, unchanged full GUT/record sync, source custody and verified cleanup are required before #1425 closure. Public updates carry status/scope/dependencies/next action only; exact commands, revisions, counts, timing, diagnostics and root-cause evidence stay local. Root owns external issue/Project/PR checkpoints and shared native scheduling.

This primitive does not prove #1347's Area3D-to-commit <=150ms or main simulation-thread lock0.0ms; both remain mandatory and unwaived. #1256's separate Canon timing liability and #1407's historical unresolved cause remain separate. Parent #1341, Feature #950 and Milestone 3 stay open until their wider equipment/crafting/recovery outcomes are evidenced.

Rollback is a reviewed revert of this additive ledger/schema/test increment. No live schema is migrated, no host settings change and no production database is touched. Root-cause learning records unexpected failures privately with symptom, seam, hypothesis, check, cause, missed coverage, countermeasure, regression evidence and limitations; none has been investigated or attributed by this shaping step. Next owner: root qualifies the validation frontier, reviews this freeze and authorizes the first behavior cycle.
