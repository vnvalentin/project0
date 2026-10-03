# Issue #1439: Full-GUT authoritative melee reach divergence

## Goal

Make the real Linux ENet melee socket test reliably observe the server-authoritative Player in reach before submitting the action, without weakening the real-socket assertion or substituting mocks.

## Delivery placement

- Governing issue: #1439, Technical Debt; user authorized diagnosis and correction on 2026-10-03.
- Project: Project0 Delivery #2; Outcome G, In Progress, Focused validation, Blocked No.
- Milestone/slice group: none; validation reliability debt has no committed product milestone.
- Related issue: #1432 is blocked on this issue's full-GUT gate.
- Branch: `fix/1439-melee-authoritative-reach`, from latest `origin/main`.

## Evidence and public seam

The failure occurred in `tests/integration/test_authoritative_melee_strike_socket_e2e.gd`, which runs the real two-process harness `scripts/test_authoritative_melee_strike_e2e.gd`. Full GUT on #1432 commit `f326251` ran 163 scripts and failed the server-position reach assertion while client prediction was in range. Exact-head hosted CI passed; one properly isolated run passed 1/1 unchanged. Root cause remains unknown.

The public seam is the authenticated ENet movement/action path and the harness's comparison of predicted position against the latest observed authoritative position before the melee intent.

Initial hypothesis: the fixed 15-physics-frame settle may expire before the authoritative position update reaches the client under full-suite scheduling. Discriminating check: correlate client/server position, authoritative sequence/tick, and elapsed frames at movement-loop exit and after settling.

## Ranked hypotheses

1. The reach loop and fixed settle observe client prediction without waiting for the final server-processed input sequence. Prediction: the failed full-suite checkpoint has an authoritative acknowledgement gap that closes later.
2. Unreliable/unordered movement intents are dropped or reordered under suite load. Prediction: sequence progression or server travel distance differs from the client's submitted intent history.
3. Client and server movement integration differ because the client uses `CharacterBody3D.move_and_slide` while the server resolves movement through its collision map. Prediction: acknowledged inputs align but trajectories diverge persistently.
4. World-entry journey restoration races the first movement input. Prediction: the authoritative position changes discontinuously around the entry acknowledgement while the client starts from an earlier position.
5. The configured Nakama gameplay bridge routes movement away from the local ENet server in this test environment. Prediction: the bridge reports available while the harness expects the local server to process the intents.

Current focused evidence: the correctly selected test passed 1/1 on both the #1432 candidate and latest `origin/main`; neither isolated pass reproduces the full-suite-only discrepancy.

## First diagnostic probe

With `PROJECT0_MELEE_DIAGNOSTICS=1`, the isolated real-socket test passed 1/1. The route was ENet. At predicted reach, client and authoritative positions both equaled `(-0.653386, 1, -0.653386)` and sequences were 122/122. After 15 settle frames, positions still matched, the client sequence was 137, the server acknowledgement was 136, and one input remained pending. This does not reproduce the suite-load discrepancy; it rules out an alternate bridge route and persistent trajectory mismatch in the isolated run.

## Confirmed cause and correction

The harness treated 15 local physics frames as proof that the server had processed released movement input. That assumption is false: the client sends unreliable movement samples and the authoritative position arrives asynchronously with the server's last-processed sequence. The original full-GUT failure showed client prediction in reach while the server snapshot was not. Correct the harness by waiting, with a 5-second monotonic deadline, for the first post-release input sequence to be acknowledged and for the authoritative position to be in reach. Keep both original client/server reach assertions and the real ENet action/hit checks. A timeout remains a failure; no fixed sleep, test skip, or weakened geometry predicate is introduced.

Focused post-correction evidence: the server acknowledged release sequence 158 after 2 physics frames; client/server positions matched at `(-0.653386, 1, -0.653386)`, both reach assertions passed, the real action/hit checks passed, and owned processes/databases were cleaned up.

## BDD scenarios

- Given the real client moves toward the target, the harness does not declare the authoritative reach precondition until the server-owned position observation is within the actual reach.
- Given client prediction is in range but authoritative state is not, the harness must expose that divergence and fail rather than submit the action as if the precondition were met.
- Given the server position is in range, the real action RPC and hit event still complete over ENet.
- Given full-suite scheduling delays movement replication, the acceptance condition remains based on authoritative state and does not depend on an arbitrary fixed settle count.

## TDD and diagnostic sequence

1. Run the exact one-test GUT selector with default `.gutconfig.json` disabled and retain unique JUnit evidence; verify only the target suite executes.
2. Inspect the real input, prediction, replication, and server position update paths. Present 3–5 ranked falsifiable hypotheses before further probes.
3. Add the smallest correlated observation at the owning test seam if existing reports cannot distinguish the hypotheses; keep it deterministic and machine-readable.
4. Establish a red-capable focused/full-suite loop, then fix only the confirmed cause. Preserve the reach assertion and ENet path.
5. Run focused test, full GUT, record sync, exact-head CI, and read back issue/Project evidence.

## Non-goals

- No skipped tests, mocks replacing ENet, retries-to-green, relaxed reach assertions, or arbitrary longer sleeps.
- No protocol redesign, combat changes, unrelated movement refactor, or changes to Windows client paths.
- Do not reopen closed #532; its startup frame-timeout defect is distinct unless new evidence proves otherwise.

## Validation and evidence

Pass the Linux-server validation ownership preflight before execution. Focused command uses `-gconfig=` and a full `res://` test path; the full gate is `scripts/run_gut_validation.sh`. Also run `scripts/check_record_sync.sh`. Capture command, host, revision, selected suites, assertion counts, cleanup, and artifacts on #1439. Full-GUT failure remains a blocker even if hosted CI or an isolated run passes.

## Rollback

Revert only the issue-specific harness/runtime correction through its PR. Preserve red and green evidence. Do not modify #1432 to hide the failure.