## Implementation kickoff — #1181

User authorized implementation. Branch: slice/1181-frontier-readiness, based on latest origin/main 9406e52c98c34dcaa452e3d69a35fd43ce4f061a. Foundation marker absent and active placeholder scan clean. Claude CLI is unavailable on 192.168.1.254 (command -v fails); using the standing authorized direct-edit fallback. GitHub #1181 remains governing record; parent #551, root-cause debt #1179; Outcome C, Milestone 1, existing Track B commitment unchanged.

User outcome: hold attempted unexplored-sector crossing safely until that player's validated geometry readiness, without blocking adjacent gameplay or the server tick. Public seam: collision-resolved movement candidate -> frontier admission -> background generation/replay/presentation -> validated ACK -> movement grant. No early return from simulation tick; held movement still acknowledges input. Readiness is per connection/player/sector and expected presentation, invalidated on disconnect or changed presentation/revision. Telemetry persistence is not movement authority.

Non-goals: client/Windows code, floor/mesh/nav redesign, fallback/timeout/Canon admission changes, four-second/60 FPS proof, production deployment, or starting two-player acceptance. SETSUJOKU remains the later Windows gameplay-proof target.

Hypothesis: a server admission resolver before position commit prevents unsafe movement while letting the existing async pipeline prepare a destination. Cheapest check: withhold ACK and attempt a crossing; generation must trigger once, position must remain safe, adjacent movement and ticks continue, and only the correct live pending ACK enables a later crossing. Wrong-peer/sector/stale/duplicate/disconnected ACK cases must fail closed. Cover null/failing telemetry independently.

Validation: record red public-seam regression first, implement smallest server-only integration, run focused tests, then full scripts/run_gut_validation.sh and scripts/check_record_sync.sh; review actual diff and CI before merge. No runtime completion claims from fixtures. Branch/PR is the rollback unit; production remains untouched.

## Bounded QA P2 - initial Canon-write recovery

Records-first authorization and SDD/BDD/TDD: https://github.com/vnvalentin/project0/issues/1181#issuecomment-5841026977

Existing seven-file frontier changes are preserved. Static evidence: failed Canon finalization clears request-owner bookkeeping; generator READY retains the result but re-request only returns its correlation without another signal. Hypothesis: retrying the cached completed result through unchanged coordinator/schema/archetype/Canon gates after the existing preparation cooldown recovers persistence without another LLM request. Existing mutation-read recovery tests do not cover initial writes.

Test first at movement -> generation completion -> failed Canon write -> restored persistence -> committed presentation -> valid ACK -> movement. Require one generation, bounded writes, no premature release, and invalid/fallback fail-closed. Demonstrate clean assertion RED before server retry edit; then focused GREEN and static/diff review. Claude remains unavailable; authorized fallback applies.

Validation uses only owned clean disposable snapshots and network-none containers, no production volumes/ports or foreign sessions. Inspect old 1181 artifacts for guidance; never use or write 1184 scratch/harness. Verify six dependency PNG hashes from 9f14587c5ec9d2a3c340f36595d5f36c71c7c6a8 in snapshot only. Retain both import logs; second must be clean, seven known UID warnings permitted under #1189. No stale wgnetstack cache, skips, engine-error green, or weakened assertions.

Delivery remains OPEN/BLOCKED on cleanup #1184 / #1192 and final integrated-base full validation. Commit only seven intended frontier files plus any strictly necessary server/test changes, exclude scratch, and return before push/PR. No merge/deploy/closing #1181, no Windows or four-second acceptance. SETSUJOKU target unchanged.

## P2 Verification and Local Checkpoint

Clean RED: p2-red-t5SGhr, one test / 20 assertions / five expected failures. GREEN: p2-green-87lwtg, one test / 22 assertions. Focused: p2-focused-mKxagB, six scripts / 50 tests / 281 assertions passing. Static: p2-static-21WhGs, all seven files parse clean; get_errors and diff whitespace checks clean. All runs cleaned their containers/snapshots and preserved source. Source diff SHA-256: 1a796d106f1542bf97bbd00f3cadf2a00cab96493fc8aa172ed782b177cd39af.

Detailed root-cause, SDD/BDD/TDD, exact commands/artifacts, fixture failure and correction, dependency hashes, review limits, and #1192 integration guidance are in p2-handoff.md for publication to #1181. Preserve exactly one SceneTree.free() when integrating the cleanup patch. Full-suite/record-sync validation remains pending on the final merged base. Local commit is an implementation checkpoint, not acceptance or independent QA approval.

Local checkpoint: a5fb9ec3168cf9a70253017f9b34b35c0a52422c. Exactly seven intended files committed, no scratch or dependency overlay. Branch slice/1181-frontier-readiness is ahead 1 / behind 4 relative to locally known origin/main; tracked worktree/index clean, only .scratch/1181 untracked. Issue #1181 body/comment 5841124330 and root-cause debt #1179 comment 5841124768 contain the evidence. Project Evidence = Focused validation, Blocked = Awaiting dependency, Status = In Progress. No push/PR/merge/deploy/closure.
