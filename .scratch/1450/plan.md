# Owned prediction listener startup

Governing issue: https://github.com/vnvalentin/project0/issues/1450

This is bounded remediation of the listener-ownership facet of https://github.com/vnvalentin/project0/issues/1150 and blocks https://github.com/vnvalentin/project0/issues/1444. The controlled mechanism investigation is https://github.com/vnvalentin/project0/issues/1447. Owner: @vnvalentin. Cross-cutting shared validation Technical Debt; no milestone or new slice group is assigned. Broader historical peer-presence, disconnect and client-lifecycle criteria stay with #1150, open until their own acceptance evidence qualifies. This fix does not establish M3 acceptance.

## User outcome, scope and boundary

The prediction harness starts an owned real server on its OS-assigned loopback port, consumes qualified readiness after completed boot, and runs its unchanged clients against that listener. Replace the released-probe reservation sequence with one default-preserving resolver seam and fixture orchestration. All server/SQLite/native execution belongs to the owning Linux runtime. No client/Windows implementation changes.

Non-goals: new production configuration, second startup callback, port search, retries, serialization, altered prediction assertions/ticks/concurrency/deadlines, external boot service, host changes, dependency additions, persistence/executor decisions, broader #1150 closure, or milestone acceptance. Historical startup actor and cause remain unknown.

Unacceptable outcomes: publishing before completed startup; masking a failed boot/bind; connecting from stale, malformed, foreign or changed readiness; treating echoed identity or PID-only liveness as source/process proof; retaining a host alias through close; admitting unrelated engine/script errors; deleting unknown state or claiming cleanup while a child remains.

## Hypothesis and first discriminating check

Confirmed source liability: the current harness closes a UDP probe before the later server bind. A server-owned zero-port bind and actual bound-port readiness should remove that interval without changing application defaults.

The first regression is behavioral, with application startup unchanged. The test holds its own UDP loopback socket and passes that occupied port through the existing ordinary server-port resolver. The fixture already defines `_resolve_server_port() -> int` returning zero, and awaits actual `super._start_server()`; the unchanged base ignores this subclass method and attempts the occupied configured port. Require one matching readiness record before launching a client. The intended RED is one ordinary assertion, `1450 owned listener readiness precedes client startup`, with no ready record, a nonzero owned child exit, and only source-qualified intended bind-failure observations. A missing fixture, failed setup, parse/script error, unrelated engine error, timeout, missing child-exit observation or partial evidence does not qualify this RED. No separate presence tracer is needed.

After the narrow fix, the base calls the fixture's zero-port resolver, the server owns a different actual listener, and publishes readiness after complete boot. The selected startup case qualifies live listener ownership and positive release. Existing unchanged prediction wrapper cases separately prove client connection and every original prediction assertion for focused GREEN and canonical full acceptance. Hold the original UDP socket through the startup attempt; release it only in the common owned epilogue. This distinguishes the actual call seam without adding a production failure hook. It establishes the controlled mechanism only, not historical causal attribution.

## SDD and implementation boundary

Production change: add `_resolve_server_port() -> int`, delegating to `NetworkConfigScript.resolve_server_port()`, and replace the existing direct resolver call at its current startup point. Preserve all boot ordering, optional await, failure exits, peer attachment, signal wiring and health completion.

Fixture-only server: override the resolver to zero; await the existing base startup; publish once only for a non-null connected peer attached to root.multiplayer with a valid actual local port. Read host/local port immediately, without retaining an ENetConnection alias. There is no second production post-bind callback.

Readiness: exactly five fields—schema_version, run_id, source_revision, state, port—with version one, state ready, matching parent run/source and a valid nonzero integral port. Use existing qualified source metadata; missing/invalid identity fails closed. The parent independently qualifies prepared source/fixture bytes and the retained owned child; echoed metadata is correlation only.

Use an ordinary bounded canonical record in a fresh owned directory created once before launch. Check ordinary/link/canonical ancestry, absent leaf, closed inventory and exact write/readback; freeze and reread the record before clients start. Godot FileAccess does not supply ordinary O_EXCL: no atomic/exclusive file creation, inode attestation or hostile same-path replacement proof is claimed. Canonical duplicate-key/numeric rejection must be verified before implementation depends on it.

Use the existing contained prediction harness and lifecycle. Preserve both original wrapper tests, concurrent workload, every prediction assertion and tick, immediate environment restoration, and current startup/connection/stop deadlines. The initial fixture/test work may be committed against the unchanged application to observe behavioral RED; no old-source receipt is promoted after any later edit.

Initial fixture/test source scope is `tests/fixtures/prediction_listener_ready.gd`, `tests/fixtures/prediction_listener_server.gd`, `tests/fixtures/prediction_listener_startup.py`, and `tests/integration/test_prediction_listener_startup.gd`. Production startup remains unchanged for this logical edit. The dedicated fixture-only Python consumer owns the held socket, direct Popen child, pidfd, actual wait status, bounded child-output reduction and common teardown. Godot OS.create_process does not expose an actual exit status; no nonzero exit is inferred from missing readiness or a quit call. GUT captures only the Python consumer's closed boolean/nullable-boolean/fixed-enum report, never child text or runtime identifiers. Intentional child errors are reduced inside that owner; any raw unrelated error reaching GUT rejects qualification.

Readiness is written to the known pending leaf, closed and read back before an ordinary move to the absent final leaf. The parent consumes only final readiness plus the source-qualified postpublication marker and live owned child. Both known leaves are included in custody checks; unexpected files or substitutions preserve state. This ordering does not claim an exclusive or atomic file syscall. Before deleting its inner runtime, the consumer exclusively creates and reads back a closed source/run-bound prerequisite receipt in the fresh outer-owned user root. It retains only source pins, a readiness digest and the closed report with cleanup unobserved; successful final output changes only the documented cleanup field. A collision, changed proof, failed retention or unknown inventory preserves affected state. The outer collector must validate this private receipt against the final reduced report and retain it before outer cleanup. The selected consumer keeps existing startup and teardown bounds; it adds no client/Thread IPC, production stop callback or general process framework.

## BDD and validation

- Ordinary server configuration resolves exactly as before through the new default seam.
- With an occupied ordinary resolver port, the zero-resolving fixture reaches completed boot, supplies owned readiness and serves the unchanged client assertions. Before the seam fix, its intended bind failure yields the fixed ordinary RED.
- Concurrent prediction attempts have distinct owned namespace/listener state and pass all existing assertions.
- Missing/lost, wrong-source/run, stale/changed, extra-field, duplicate-key, malformed or wrong-type readiness, publication failure, source drift and early child exit launch no client and fail closed inside current bounds.
- Existing early boot-failure and controlled held-port failure seams publish no readiness, preserve nonzero failure, and reap all owned children. No production failure-injection hook is added.
- Awaited base startup is source-qualified, with an offline yielding control only where an existing seam permits it; no external boot service or unobserved optional-boot runtime claim.
- Normal teardown releases the listener; a positive same-port bind after close qualifies release. Unknown custody preserves affected state; process reaping remains mandatory on every outcome.

Root verifies foundation and owning-plan preflight before implementation. Initial static ownership uses the existing prediction-test anchor and does not qualify a not-yet-installed selected test. Once fixture/test files exist, freeze and pass the actual selected-test runtime plan before native RED. Source-bound expected-error controls must discriminate intended bind failures from unrelated errors before capture/execution. Detailed runtime evidence remains local; GitHub records status only.

Required final gates: current-source focused behavior and meaningful negatives, complete artifact readback, independent Standards and Spec, hosted checks, unchanged canonical full GUT and record sync, source/process/temp custody, and active issue/PR evidence. Dependent #1444 must be requalified at its actual integrated source; closing this debt is not dependent or milestone acceptance.

## Root-cause learning and rollback

Symptom and confirmed liability: prediction listener startup can fail, and a released probe is not a reservation. The completed controlled diagnostic confirms takeover susceptibility; historical actor/cause remain unknown. Existing successful runs did not prove ownership through the release-to-bind interval. Countermeasure hypothesis and regression are the held-port actual-startup test described above; no runtime outcome is claimed in this ticket.

Pre-execution source review found unsafe shell argument encoding, a post-hoc unbounded runtime inventory, a reader closure initialized after child acquisition, and proof deletion before retention. The corrections use base64 metadata with harmless argument syntax, an exact bounded layout with pre-created directory identities, reader initialization before launch, and source-bound prerequisite retention before cleanup. These are preventive source corrections; runtime regression and copied failure controls remain pending.

Record every unexpected failure and its public seam, discriminating check, confirmed cause or unknown hypotheses, correction, regression, limitations and next owner in #1450 before completion. Preserve the broader liabilities in #1150. Rollback is ordinary Git reversal of this bounded seam and fixture/harness work, with no deployment, database, default configuration or host rollback involved.

No ADR required: a default-preserving resolver seam and test fixture orchestration introduce no production architecture, ownership, persistence or executor decision. The proposed affinity ADR remains unadopted.

## Current frontier

Records-first foundation, Project and static ownership qualification are complete. The issue-owned fixture, dedicated consumer and public regression are authored for source review against unchanged application startup. Behavioral RED, the minimal application fix and every final-source runtime/delivery gate remain pending. No runtime outcome is claimed for these new files.
