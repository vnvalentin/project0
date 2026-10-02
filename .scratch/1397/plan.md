# Correct the fallback regression stopwatch

Governing issue: https://github.com/vnvalentin/project0/issues/1397
Parent goal: #204. Milestone 4 / M4.1; validation blocker for #1376 / PR #1378.

Outcome: measure the existing repair/schema/detail public seam against its unchanged strict 200 ms budget, without charging boot-only hub fixture setup to that runtime stage.
Scope: prepare Hub.blueprint before the stopwatch in the existing 14,400-tile test. No production code, candidate, assertions, threshold, client behavior, or deployment changes. No ADR is needed for a measurement-boundary correction.

Root cause and measured stage evidence are in #1397. Production server_main passes its boot-prepared hub, while the test originally created that fixture inside its fallback timer. The original 201.921 ms failure is preserved; profiling measured 64.311–66.146 ms for fixture construction plus generation-result metadata. Host scheduling contribution to the original failed run remains unknown.

BDD: given the existing boot fixture, the same Repair.repair, Schema.validate and Detail.prepare calls must yield valid placed output in less than 200 ms. TDD uses the existing failing public-seam timing regression and unchanged correctness assertions; no test of implementation syntax is added.

Foundation: checklist complete, marker absent, active-file placeholder scan clean at base b1734450ba03df7f1818b966409f14658dba2b93. Shared Harness guidance read at 77de008a0f28eb91726527d543adb435735a2157. Relevant source hashes match the profiled revision.
Validation: the adjacent JSON declares Linux-owned focused and full-suite tests. Preflight first, then focused GUT and ten independent numeric samples, full isolated GUT, and record sync at the final head. Use fresh XDG roots, a session flock held through cleanup, and process monitoring. Review and delivery evidence live in #1397 and its PR; passing this supporting correction does not complete M4 acceptance.
Rollback: revert the test-only PR; delete only owned temporary validation state. No production files, databases or services are changed.
