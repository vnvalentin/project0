# Prediction validation at the authoritative movement boundary

Governing issue: https://github.com/vnvalentin/project0/issues/1452
Owner: @vnvalentin. Cross-cutting technical debt without a milestone or new slice group. Remediates one validation facet of https://github.com/vnvalentin/project0/issues/1150; preserves the movement contract originating in https://github.com/vnvalentin/project0/issues/95; blocks https://github.com/vnvalentin/project0/issues/1450 and https://github.com/vnvalentin/project0/issues/1444. Broader historical and client liabilities remain open with their own evidence requirements.

## Outcome, boundary and non-goals

The prediction fixture observes actual authoritative movement while input remains held, captures the original predicted-distance assertion at that boundary, and releases afterward. Preserve immediate prediction, monotonic acknowledgement, forced correction, smoothing, independent concurrent attempts and cleanup. This is fixture-only work owned by the Linux Godot/server validation runtime.

Non-goals: production input queues, acknowledgement semantics, transport or client implementation changes; new production callbacks; listener-readiness work from the dependent issue; a general process or RPC framework; new deadlines, sleeps, retries, weaker thresholds, serialized concurrency, skipped cases, broader historical-cause attribution or milestone acceptance.

Unacceptable outcomes include treating receipt acknowledgement as proof of elapsed movement, using the blue rendered node or red prediction as server authority, accepting a missing/stale/foreign snapshot, releasing before the selected authority boundary, admitting partial capture or cleanup, or promoting earlier-source proof to a changed source.

## SDD and falsifiable hypothesis

The existing public server method accepts a newer input for its owner and replaces the current intent immediately. Its independent physics step integrates that current intent and emits position; a connected server also sends the current sequence through the real authoritative-position RPC. The client resets to that snapshot and replays only newer pending inputs. Thus client-held frames do not establish how many server integrations occurred while held. Release may supersede held input before an integration. This mechanism is source-confirmed; it is not confirmed causal history of the failed concurrent attempt.

The frozen specification supports the current unreliable latest-intent behavior. This issue does not reinterpret its broader replay prose as authorization for queued simulation.

## Cheapest diagnostic and regression seams

First, use an actual ServerPlayerState node, start_for_peer, apply_input_intent, set_physics_process(false), the existing physics method and position_updated signal. Use the established ordinary fixed delta and no sleeps. Compare: held then release before one integration; held integrated before release; a stale release; a foreign-owner release. The first case must remain stationary; the positive case moves; rejected inputs do not replace the legitimate held intent. Cleanup disconnects only its own signal and frees only its own node on every path. No private sequence inspection or fabricated acknowledgement qualifies this control.

The standalone node has no connected root peer, so its position signal is a displacement mechanism check, not evidence of a delivered RPC or acknowledgement. The smallest real-connection observation uses the existing prediction harness and NetworkClient.authoritative_position_received. Subscribe before gameplay/input, retain only this attempt's typed snapshot values internally, and disconnect the owned callback in the common epilogue. Its real connection and session admission supply the authoritative owner context. Do not add a second paused-server process protocol just to restate the node mechanism.

Subscribe before admission and accept the first genuine authoritative snapshot from this attempt as its fixed baseline; it may arrive during the existing held-input window. Allocate a sequence boundary through the existing public next_input_sequence method before pressing input; do not read its private counter. While input remains held, require a subsequent actual received snapshot with sequence beyond that boundary and positive Z displacement above 0.5 from the fixed authoritative baseline. Capture `player.position.z - start_position.z` while still held and retain the original >0.5 assertion; Euclidean distance does not qualify it. Observed acknowledgement sequences may remain equal or increase because the same held intent can integrate on multiple server physics steps. Every qualifying snapshot must have sequence strictly above the held sequence floor; equality with that floor or a decreasing observed sequence is rejected. Observe the boundary in the ordinary harness loop after existing callbacks, not by treating a pre-reconciliation callback sample as a settled player state. Then release and continue the original acknowledgement, forced correction and smoothing work. A synthetic direct call may qualify the client's public reconciliation seam, but is labeled separately from genuine RPC delivery.

## Exact budget and preserved acceptance

The existing startup and connection deadlines remain 5000 ms each. Immediate local responsiveness remains fewer than three observed physics frames. Held input has at most the original 30 additional client physics frames; the authoritative predicate receives no extra waiting window. The original 30-frame release/settle phase, ten-frame packet drain and at most 60 smoothing frames remain. The accepted source has no separate wall-clock movement deadline: do not borrow a fresh startup/connect deadline or silently extend the hold. A missing baseline or missing subsequent authoritative progress by the held limit fails with a fixed assertion and enters the same cleanup path. Baseline acquisition consumes that same window; it receives no extra wait. Source orientation must qualify the existing stop budget before any native plan is frozen.

Keep the >0.5 predicted-distance threshold, forced-correction distance <0.01 and smoothing distance <=0.05. Keep both existing wrapper methods and their two overlapping attempts. Focused and canonical outer lifecycles retain their previously qualified deadlines; a source-only plan is not approval to launch.

## TDD and required gates

The controlled node cases establish the latest-intent mechanism with a positive and rejection controls; their expected stationary case is not a production defect or proof of historical causality. Before changing release behavior, expose the existing frame-only release policy at one tiny fixture-only public observation seam consumed by the real harness. Its initial implementation retains the current frame-only behavior. The ordinary RED asks that seam to reject release after the original frame budget when controlled public server updates show no authoritative progress; the old policy instead permits release. This must be an actual assertion failure, not an absent symbol, parse error or simulated runner failure. A positive integrated-held case and stale/reordered or unqualified-sequence snapshots discriminate the corrected authority policy. The controlled server updates can be delivered through the existing public NetworkClient receive/signal seam, explicitly labeled direct simulation rather than genuine wire RPC. The existing real harness independently qualifies actual RPC delivery afterward. If that cannot fit the existing bounded seam, stop and refine this issue's test shape; do not add a protocol or relax the budget.

Root first qualifies foundation, targeted Project state, the issue branch and the records-only ownership plan. Static ownership initially selects an existing registered anchor and explicitly does not qualify the future test. After the minimal test exists, freeze its actual selection, controller/source/capture/artifact pins and pass configured ownership before native work. Independent Standards and Spec review precede each immutable native freeze. Root owns native execution.

Final acceptance requires current-source public-seam controls, both unchanged prediction wrappers, complete canonical GUT, record sync, hosted checks, complete retained-artifact correspondence, owned process reaping and known temporary-state custody. A mechanism control or narrow pass alone does not close the issue or its dependents.

## Integration, learning and rollback

Use the issue-owned branch from freshly verified accepted main. Change only the movement-observation section in scripts/test_prediction_reconciliation.gd, one minimal fixture-only observation value if needed for the public regression, its minimal test and this planning record. This value object is specific to held movement, with no process, generic event or RPC framework. Keep listener startup code out of this branch. After an isolated logical commit and its narrow checks/reviews, integrate that commit into the dependent listener candidate with a bounded reviewed resolution if needed. Qualify each actual final source; no dependency cycle requires listener delivery first.

The discovery is an unbound fixture timing assumption. Actual causal input/snapshot history of the failed full-context attempt remains unknown; detailed evidence is retained privately. Existing passing checks did not prove authoritative progress before releasing input. The proposed countermeasure observes that progress within unchanged limits. Regression and native acceptance remain pending.

Rollback is the ordinary reversal of this fixture/test correction. No dependencies, host changes, production protocol, live state or deployment are affected. No new ADR is required for a fixture-only repair preserving the existing authority contract; any production semantics change requires a separate decision.

## Current frontier and next actor

The governing issue is established and the accepted movement contract has been read. This ticket and ownership plan are authored proposals only; no product edit, test installation, native result or final-source acceptance is claimed. Root completes source-branch/Project/foundation and owning preflight, then author shapes the minimal public-seam regression with independent review. Missing causal history stays unknown.
