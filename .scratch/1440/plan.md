# #1440 — pinned authored item capacity

Governing issue: https://github.com/vnvalentin/project0/issues/1440
Milestone 3, M3.2 Item Ownership and Transaction Ledger. Parents: equipment Epic #1341 and Feature #950. Decision #310 keeps its native parent #302. Assigned owner: Philip Rabe's M3 agent. Project #2 remains In Progress / Evidence Missing / Awaiting dependency. The issue and milestone own delivery state; frozen archives are untouched. Draft pull request: https://github.com/vnvalentin/project0/pull/1442 (Refs #1440).

## Outcome and scope

Given a fixture-authored profile set and a pinned bag definition, return its exact immutable capacity profile or a bounded rejection. Two pure shared values, ItemCapacityProfile and ItemCapacityBindings, own validation, independent snapshots and read-only exact-pin resolution. The server chooses the authored set; parsing grants no recipient, ownership or carrying authority.

This preparation owns records and one public tracer only. No capacity application module is implemented before qualified RED. No catalog/database adoption, ledger enforcement, existing item/stat schema change, transfers, equipment movement, GUID/revision/receipt mutation, production tuning, nested bags, mass/volume, client/Windows change or executor belongs here. Capacity 4 and boundary examples are fixture data only.

Unacceptable outcomes: coercion or fallback, neighboring revision selection, open wire fields, aliases to retained values, conflicting partial bindings, rejected payloads echoed in details, parse/load failure substituted for RED, or static checks presented as runtime acceptance.

## Foundation, SDD and no-ADR rationale

Foundation closure and applicable shared/project guidance have been confirmed. The precise orientation and execution-plan bindings are retained privately under the user's disclosure boundary. No new ADR is needed: the approved pure contract changes no authority, persistence, threading, schema or production adoption.

ItemCapacityProfile.from_wire_dict(value: Variant) returns bounded outcome/detail/profile; to_wire_dict() returns an independent snapshot. ItemCapacityBindings.from_wire_profiles(value: Variant) returns bounded outcome/detail/bindings; resolve(definition: ItemDefinition) returns outcome/detail/profile. Values are typed or null; success detail is empty and error details are fixed harmless strings.

The exact String-keyed fields are schema_version, profile_id, profile_revision, definition_id, definition_revision and slot_count. Version is integer 1; identifiers are nonblank Strings of at most 128 characters, preserving exact spelling. Count is an integer in 1..1024. Outcomes are ok, malformed, unsupported_version, out_of_bounds, missing_profile, definition_mismatch and immutable_profile_conflict.

Bindings validate/snapshot the entire supplied Array and use unambiguous composite pins without mutators. Exact repeated content is idempotent; changed content under either definition pins or profile pins rejects before a partial bindings value exists. Empty sets are valid. Resolution revalidates the supplied definition using its existing factory, requires slot bags and exact pins, and never falls back. Inputs, returned snapshots and independent resolved values cannot mutate retained state.

## BDD and vertical sequence

Given a validated fixture bag definition and one six-field authored capacity profile with count 4, when the profile is parsed, bound and resolved for that exact definition revision, then its six-field snapshot and count round-trip exactly.

Subsequent vertical cycles cover bounds and independent snapshots; malformed/open fields and unsupported schema/count types; null/invalid/non-bag definitions and absent exact pins; then duplicates, conflicts and independent definition revisions. Existing item definition, instance and creation-profile compatibility checks preserve their closed schemas. These scenarios are not implemented or observed by preparation alone.

## TDD public seam

Hypothesis: validated pure values and immutable exact-pin bindings express fixture capacity without expanding schemas or authority. First tracer: test_pinned_capacity_profile_resolves_authored_bag_definition in test_item_capacity_bindings.gd. Its fixed first RED label is: 1440 authored capacity profile parses and resolves pinned bag definition.

The test guards module presence before dynamic loading and declared factories before calls. It never preloads or annotates either absent capacity class. An absent module/factory produces one fixed failed assertion and immediate return. Subsequent steps exercise the agreed public factories, resolve and to_wire_dict. Crashes, script/parse/load errors, timeouts or setup failures cannot qualify RED. GREEN requires the selected public round-trip to pass.

The two proposed shared values and their capacity unit files remain subject to one test/implementation cycle at a time. Only the initial binding round-trip tracer is prepared at this checkpoint; no implementation scaffold is added. Script factory detection uses the Godot 4.3 public Script method-list API before invocation; native parse and behavior remain unobserved.

## Validation status and next action

Static records and ownership preparation passed; the single parse-safe tracer is now prepared for review. The exact machine-readable plan, selected commands, host/tool/source bindings, private reports and execution/capture/teardown contract are retained locally rather than published. A successful static plan check grants no native execution.

After qualified RED, implement the smallest pure behavior, then verify GREEN. Subsequent focused validation includes both capacity unit files and existing item definition, instance and creation-profile compatibility coverage. Final delivery still requires the full standard GUT gate, record synchronization and independent Standards/Spec review at the final revision. A separate exact private full inventory is required; a short focused list never represents the full suite.

Native preparation/parse, RED/GREEN, focused compatibility, full validation and final review remain NOT_OBSERVED. Coordinator reviews the frozen tracer and isolated lifecycle, grants the serialized RED window, and authorizes implementation only after qualified RED. Public records contain status, scope, dependencies and next action. This increment does not establish playable inventory, workshop acceptance, affinity, latency or Milestone 3 completion.

## Rollback and root-cause learning

Rollback is a reviewed revert of additive values/tests before adoption; no database or deployment change occurs. No unexpected native failure is observed during preparation. The known gap is absent capacity modules at the approved public seam; the next discriminating check is the named parse-safe tracer. Any unexpected check failure must be captured and classified before continuation.

Automatic approval review rejected publishing internal execution details in the initial record layout. The exact plan remains private, while this public record preserves approved product scope and the next validation gate. This placement follows the user's explicit local-evidence boundary.
