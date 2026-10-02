# #1379 Transaction query failure rollback

Governing issue: https://github.com/vnvalentin/project0/issues/1379
Parent: #1347 / #950. Milestone 3, M3.2 persistence prerequisite.
Base: 4715092ecae5e7808c2fc019eb21002b0ce00955.
Harness guidance: 77de008a0f28eb91726527d543adb435735a2157.
Foundation: marker absent; active setup records complete. Literal Docker templates and the instruction describing placeholders are not unfilled delivery records.

## SDD
The public SqliteStore.transaction callback may return true after a query error. The store promises any query failure rolls back. Add a transaction-scoped failure latch if the public-seam regression proves this gap. Both query entry points must participate. Reset at transaction entry and completion, preserving normal query results, legacy write counters and subsequent transactions. No schema or consumer API changes.

## BDD and TDD
Given a valid insert followed by a failed query, when the body still returns true, then the transaction fails and close/reopen shows no row. Exercise both query APIs. Given an error outside a transaction or a previous failed transaction, a subsequent valid transaction commits. First retain actual RED, then minimal GREEN; full suite and independent Standards/Spec review precede merge.

## Validation and rollback
Use validation-plan.json on Linux 192.168.1.254 via okami.tail02bdf2.ts.net. Godot user storage is this worktree's build/validation/1379/userdata; dashboard output is build/validation/1379/dashboard. Each database test closes and deletes its DB/WAL/SHM/journal; retain only nonsecret test evidence. Do not read or alter live databases, containers, the dashboard, or the existing dirty checkout. Revert code through a PR if necessary; no migration or deployment.

## Root-cause learning
RED: 12 focused tests ran; the added public-seam test failed both transaction outcome and durable row assertions (2 assertion failures), while 11 existing tests passed. GREEN: the unbound query failure latch passed 12/12. Evidence: build/validation/1379/red-query.{xml,log} and green-query.{xml,log}. Cause: only the callback bool was checked; SQLite statement ABORT does not abort the enclosing transaction. Prior coverage returned false after the error. The transaction now retains the failed-query condition until rollback; the bound-query behavior is the next increment. Test fixture database cleanup verified (zero remaining files).
