## Latest Dev Status: Focused Green, Delivery Blocked

Local checkpoint: `a5fb9ec3168cf9a70253017f9b34b35c0a52422c`, exactly seven intended server/test files; scratch and overlays excluded. Tracked worktree/index clean; only `.scratch/1181/` remains untracked. No push or PR.

The seven-file frontier implementation and bounded QA P2 correction are ready for the user-authorized local checkpoint on `slice/1181-frontier-readiness`. This supersedes the initial "not started" status below. This is Dev evidence and self-review, not independent QA approval or delivery acceptance. No push, PR creation, merge, deployment, or issue closure is authorized in this handoff.

Parent #551; root-cause debt #1179; primary Outcome C, Milestone 1, existing Track B commitment unchanged. Delivery remains blocked awaiting cleanup #1184 / PR #1192, integration of current main, and full validation on that final base. SETSUJOKU remains the later Windows target; no Windows, four-second, frame-time, or multiplayer acceptance is claimed.

### Root-Cause Learning / SDD

Independent clean regression confirmed: movement starts one real provisional request; validated completion reaches the unchanged coordinator and real Canon repository; one injected SQLite transaction failure leaves Canon absent. The generator stays READY. Previously the cooldown re-request only returned the cached correlation, without another signal/finalization, permanently holding movement.

Countermeasure: six added lines in server preparation re-finalize the cached READY result through the existing coordinator, schema, archetype, and Canon gates. Cached result is copied, completed generation spans are not re-emitted, and retry telemetry uses the requesting peer. No generator, schema, archetype, Canon repository, client, dashboard, Windows, fallback, or product-timeout changes. One LLM request only. Existing per-peer/sector preparation cooldown bounds persistence attempts; persistent failure remains fail-closed. This is not a global cross-peer retry budget.

Existing tests missed the defect because recovery coverage injected mutation READ failure against already-persisted Canon rather than initial generation WRITE failure. Rollback is the bounded server retry and its three tests; never bypass readiness or weaken admission. No new ADR is needed because authority/contracts remain unchanged.

### BDD / TDD Evidence

Commands, all through `ssh -o BatchMode=yes vic@192.168.1.254` from `/data/code/project0`:

- `node .scratch/1181/validate-p2.cjs red`: `.scratch/1181/p2-red-t5SGhr/`; GUT exit 1, 1 test / 20 assertions, exactly 5 expected assertion failures (no write retry, absent Canon/presentation, no release). No engine/script errors or leaks. Wrapper exit 0 means the expected clean RED was verified, not that tests passed.
- `node .scratch/1181/validate-p2.cjs green`: `.scratch/1181/p2-green-87lwtg/`; same test GUT exit 0, 1/1 test / 22 assertions. The two extra assertions inspect the now-existing committed presentation and reject a wrong-peer ACK. Existing assertions were not weakened.
- `node .scratch/1181/validate-p2.cjs focused`: `.scratch/1181/p2-focused-mKxagB/`; 6 scripts, 50 tests / 281 assertions, all passed. Orchestration 24/194; movement collision 6/13; ACK tracker 5/16; boundary detector 7/31; journey registry 3/10; Canon coordinator 5/17.
- `node .scratch/1181/validate-p2.cjs static`: `.scratch/1181/p2-static-21WhGs/`; all 7 intended files pass Godot `--check-only`. VS Code `get_errors` reports no errors on all 7. `git diff --check` passes.

The new public-seam regression drives movement -> real loopback HTTP generation -> failed Canon transaction -> restored write -> presentation -> wrong/valid ACK -> movement. It asserts one HTTP request/completion, two total write attempts, no retry before 1000ms, no release before committed Canon plus matching ACK. Two additional movement tests verify continued failures are cooldown-bounded and cached fallback, invalid schema, forbidden classification, and wrong-sector results cannot reach Canon or presentation.

Each artifact directory contains `run.json`, source patch, exact source hashes, command lines, logs and XML. Final focused/static source diff SHA-256: `1a796d106f1542bf97bbd00f3cadf2a00cab96493fc8aa172ed782b177cd39af` against `9406e52c98c34dcaa452e3d69a35fd43ce4f061a`.

### Isolation and Fixture Learning

Every run used a fresh tracked-source snapshot and uniquely named read-only-root container with network `none`, no published ports, no production volumes, bounded processes/time/memory, and an isolated writable HOME. Only snapshot/evidence directories were mounted. All owned containers and snapshots were removed; source remained unchanged during each run. No foreign sessions or #1184 scratch/harness were modified or used.

Six PNGs only were overlaid into snapshots from merged `9f14587c5ec9d2a3c340f36595d5f36c71c7c6a8`, verified against all six SHA-256 values published in that commit. Each `run.json` records their exact hashes. No working-tree asset edits or main merge. No `.godot` cache was copied; no stale wgnetstack extension cache was restored.

Both import logs are retained. First-pass cold-bootstrap diagnostics remain known #1189 debt, not a clean import claim; each second pass exits 0 with zero errors and the seven known UID warnings. Focused tests have only the three applicable known font UID warnings, no skips, engine errors, or leaks.

Initial `.scratch/1181/p2-red-9tBLpR/` is deliberately excluded as clean RED: GUT tried to free the generator while its completion signal was still emitting. One process-frame wait after completion unwinds that stack and the queued service cleanup; the repeated RED proved this fixture-only countermeasure without changing product timing or assertions. Evidence and root-cause learning were recorded before repair in issue comment 5841077023.

### Self-Review and Integration Handoff

Standards/scope self-review: only the original seven server/test files are intended for commit; this correction changes only server_main and its existing orchestration test. Existing unknown work is preserved. No independent review approval is claimed.

Spec self-review: recovery is fail-closed, uses unchanged gates, does not retry LLM generation, and retains all original frontier behavior. Remaining review risks are interactions with later main admission changes, clean-import debt, and end-to-end client/runtime behavior on the final base. The fixtures do not prove Windows geometry/navigation or timing acceptance.

PR #1192 was inspected remotely only: OPEN DRAFT, head `594ec6e87828c82dd705360cd756544cb15599ca`. After its owner obtains acceptance and cleanup merges, preserve the local frontier commit, then integrate the merged main history without replacing whole files. Its Canon reentry test adds `server.free()` already present here: retain exactly ONE free, not two. Preserve its FakeBridge.unbind/autofree relay changes and the frontier tests/retry. Preserve intervening authenticated-admission changes in server_main when resolving any merge overlap.

Rerun focused regressions, the full GUT suite, record sync, and review/CI on the exact integrated base. Current focused results cannot certify that future tree. Return for coordination before push or PR; do not close #1181 or its parent/debt based on this checkpoint.