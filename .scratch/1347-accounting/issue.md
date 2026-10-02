# #1347 — direct SQLite statement accounting prerequisite

Issue: https://github.com/vnvalentin/project0/issues/1347
Scope/acceptance brief: https://github.com/vnvalentin/project0/issues/1347#issuecomment-5953557168
M3.2, parent #951 / #950; owner vnvalentin. Full experiment remains blocked awaiting dependencies.
Baseline 4715092ecae5e7808c2fc019eb21002b0ce00955; Harness 77de008a0f28eb91726527d543adb435735a2157 actually read.
Foundation: checklist complete; marker absent, active placeholder scan clean, record-sync exit 0 (0 errors/warnings).

## SDD
Preserve canon_write_counters(). Add start_dml_observation() after schema setup, qualifying the connection's schema; dml_statement_counters() snapshots direct single-statement submission counts by operation/table and attempted/committed/rolled_back/failed. Windows have IDs, connection IDs and retained previous reports. Snapshots never reset counts. Coverage gaps yield NOT_OBSERVED complete totals/by_table, with partial_counts and static reason codes; no SQL, bindings or data in reports. Statement count is not an affected-row count. Unsupported SQL executes unchanged, invalidating evidence only. Known successful writes get transaction disposition only after observed successful commit/rollback.
Official addon v4.4 source fb17f67bbb1e12490565c8ff91dc2929adb01c92 src/gdsqlite.cpp _bind_methods has no native trace/update/preupdate/authorizer hook; lines320-324 recursively execute statement tails. Shipped binary/source equality is unqualified. No new dependency/migration/production authority. No ADR: bounded instrumentation at existing server store seam, preserving accepted architecture and Canon API.
Non-goals: implementing crafting, station/permission/item identity, durability derivation, definition schema, simulation lock measurement, <=150ms or Windows/paired/runtime acceptance; no dirty-candidate/live-server changes.

## BDD
Given schema setup and a qualified window, when each direct INSERT/REPLACE/UPDATE/DELETE executes, then exact operation/table attempt/disposition counts are observed, including zero-row statements.
Given a transaction, successful statements count committed only on commit, rolled_back only on confirmed rollback; failed statements are attempted+failed.
Given unsupported SQL/schema/multiple statements or uncertain disposition, execution is unchanged and completeness is NOT_OBSERVED with partial known counts.
Given snapshots/new windows/connection lifecycle, snapshots are immutable, previous invalid windows remain visible, and a window cannot silently cover a reopened connection.
Given Canon repository calls, existing Canon counters retain their lifetime behavior.

## TDD
First discriminating public-seam test expects start_dml_observation()/dml_statement_counters() and exact insert report against real isolated SQLite (red: API absent). Build minimal working report; incrementally cover other ops/tables, commit/rollback/failure, unknown coverage and history. A separate linked debt owns transaction query-failure contract remediation; retain its public-seam discriminating evidence before root's fix.

## Validation and safety
Owned Linux host192.168.1.254 via SSH vic@okami.tail02bdf2.ts.net. Focused selection tests/integration/test_canon_write_accounting.gd; dependencies godot/sqlite. Pass ownership preflight before runtime. Bounded import/GUT uses new owned XDG_DATA_HOME per run, no live database/dashboard; retained artifacts build/validation/1347-accounting/<run>/. Exact command in validation-plan.json. Fixture after_each closes store and removes DB/WAL/SHM/journal; runner finally removes owned XDG root. Full GUT is serialized by root and plan regenerated with exact test inventory; use owned DASHBOARD_RESULTS_DIR. Final record-sync and independent Standards+Spec review before merge. Rollback: revert branch/PR, remove only owned fixtures. Existing dirty /data/code/project0 preserved.

## Root-cause learning
First red: red-api import exit0, GUT exit1, 1 selected script ran, 5/6 passed; sole failure absent explicit observation API. Engine4.3.stable.official.77dcf97d8 on owning Linux host; fixture root removed by finally trap. Linked atomicity defect #1379 is owned by root in a separate branch/test file. Add actual red/green evidence and any unexpected validation outcome here before completion. Native row effects/external writers always NOT_OBSERVED; direct statement report alone does not satisfy full #1347.

## Delivery
Draft PR and final revision evidence pending. Full #1347 open / Missing / Awaiting dependency; next actor root coordinates review and remaining experiment contracts.

First green: green-api import/GUT exit0, 1/1 selected script, 6/6 tests passed including all five original Canon tests on Godot4.3. Artifacts build/validation/1347-accounting/{red-api,green-api}/result.json, gut.xml, gut.log, import.log; owned XDG root removed. Source/setup warning: vendored GUT resource UIDs fall back to text paths on4.3; no script skip/error. These are focused headless fixture checks, not full #1347 or native-row/Windows acceptance.
