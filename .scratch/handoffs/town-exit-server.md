# Server Handoff: Blocked Town Exit

Governing issue: https://github.com/vnvalentin/project0/issues/1242
Parent issue: https://github.com/vnvalentin/project0/issues/1213
Related capsule correction: https://github.com/vnvalentin/project0/issues/1230
Parent feature: #551. Milestone: M0 Solo Playable Foundation.
Owner: server-side Copilot on `192.168.1.254`; Windows owner handles client work and paired acceptance.
Status: user approved this investigation and requested this handoff; server work has not started.
GitHub owns live status. This document is an intake snapshot, not a replacement tracker.

## Outcome and Boundary

An authenticated player can walk through the visible town-wall opening into valid,
navigation-ready adjoining terrain. In development client `0.14.14`, the player
instead stopped against an invisible wall at the only visible opening, roughly
screen-right. That is not a confirmed compass direction or world coordinate.

Keep the capsule correction separate: normal in-town movement and capsule grounding
were accepted. The test started at `(3, 1, 3)`; all 143 captured positions had Y=1.
Town-exit acceptance remains blocked. This is an unreleased development application,
not a production environment. Temporary state is for reproducibility and cleanup.

Public seam: collision-resolved movement candidate -> frontier sector/ingress ->
provisional generation and Canon -> client local-ingress validation/navigation ACK
-> authoritative movement admission.

## Observed Evidence

- Run: `9396a6e342f449c9886c06f51d3a7878`; client `0.14.14`, Godot 4.7.2 on SETSUJOKU;
  backend Godot 4.3 on the Linux host. Authentication, collision and frontier gates enabled.
- Outside sectors: `sector--1--1` and `sector-0--1`.
- Each has `llm_generation_latency` status `ERROR`, lasting about 3002/3001 ms,
  followed by schema-validation and Canon-commit status `OK`.
- Server repeatedly presented/reloaded these sectors. Client logged `fallback_selected`.
- Only `starting_town_hub` has a captured successful `client_presentation_ack`;
  neither outside sector has one. The player described a stop, not snapback.
- No console runtime errors were found, but generation ERROR telemetry exists:
  these are different evidence categories.
- Client exited 0; owned server processes and temporary runtime data were removed.
  Logs, telemetry, package fingerprints and assessment remain available.

Confirmed root cause: **not yet established**. The three-second spans alone do not
prove an Ollama timeout. Missing ACKs and an invisible-wall sensation do not alone
distinguish collision from frontier admission. The exact rejected blueprint and
ingress pair were not retained, so recover them in a bounded reproduction.

## First Discriminating Check

1. Read current issue records and repository instructions; establish a server-only
   baseline. Do not assume the captured development package was built from a clean commit.
2. Identify the actual opening from the starting-town fixture and captured trajectory.
   Record desired position, collision-resolved candidate, frontier sector and admitted position.
   Completion: show whether physical collision or the readiness gate first prevents exit.
3. Capture the generation outcome/reason, original blueprint identity and walkable bounds,
   world ingress, sector coordinate/offset, local ingress, and client presentation result.
   Exclude credentials, assertions and tokens. Completion: explain why this exact ingress
   is accepted or rejected, rather than inferring from `fallback_selected` alone.
4. Reproduce at the owning public seam with a deterministic failing test, including
   unavailable/failed generation if that is causal. Then make the smallest server-owned
   correction and rerun the same test. Return to Windows if client changes are necessary.

Ranked hypotheses: the generation fallback does not cover the translated entry;
sector/ingress coordinate handling is inconsistent independently of generation failure;
physical collision at the apparent opening also contributes. Preserve alternatives until tested.

## Code Anchors

- `server/server_main.gd`: `_request_sector_from_boundary`, `_sector_generation_prompt`,
  `_present_frontier_sector`, `_frontier_sector_at`, `_resolve_frontier_movement`.
  The request stores the actual ingress separately; inspect what reaches generation/admission.
- `server/provisional_sector_generator.gd`, `server/sector_blueprint_service.gd`,
  `server/sector_archetype_admission.gd`: generation, fallback and admission ownership.
- `server/starting_town_hub_fixture.gd`, `server/sector_boundary_detector.gd`,
  `server/server_player_state.gd`: opening geometry, sector identity, collision/admission ordering.
- `shared/sector_identity.gd` and `shared/world_scale.gd`: signed coordinates and offsets.
- Read-only client reference: `client/network_client.gd`, `present_sector_blueprint` and
  `render_sector_blueprint`. Unsafe ingress selects fallback; non-valid presentation removes
  the sector root/readiness node. `_on_geometry_assembly_completed` ACKs valid presentation only.
- Existing tests: `tests/integration/test_provisional_sector_generation.gd`,
  `tests/unit/test_sector_archetype_admission.gd`, `tests/unit/test_starting_town_hub_fixture.gd`.

## Validation and Return Contract

Run on Linux against the approved server-only source, with import/cache preparation:

```sh
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_provisional_sector_generation.gd -gexit
bash scripts/run_gut_validation.sh
bash scripts/check_record_sync.sh
```

Add the narrow regression for the demonstrated cause; require real test/assertion counts,
zero unexpected failures/skips, command results, exact source fingerprints and cleanup proof.
Use an owned private-network validation container: shared-host runs collided on UDP 50001,
UDP 9999 and TCP 8097. A private-network run passed all 140 scripts for the capsule fix;
that is prior evidence, not proof for the town-exit correction. Host unprivileged `unshare`
was denied; do not attempt interactive elevation or stop another agent's processes.

Return the confirmed causal chain, red/green evidence, changed files/commit, full gates,
rollback, remaining limitations, and a bounded paired-retest plan. Final acceptance requires
the Windows player walking through this opening into ready terrain and confirming normal feel.
Keep the issue blocked if the cause, validation or player acceptance remains missing.

## Safety and Source Provenance

- Preserve authentication, version checks, physical walls, navigation validation and frontier
  ACK binding. Do not solve the symptom by allowing movement into unready/unsafe geometry.
- No blanket Canon rewrite, capsule-fix undo, arbitrary client mesh offset or timeout increase
  without evidence. No unrelated refactor, launcher work, public publication or deployment.
- Rollback only the bounded server correction and owned test resources. Retain failure evidence.
- No Claude use. Linux owns server-only work; Windows owns client/package/Windows-only tests.
  Do not pull or run the Windows-required #1213 branch on Linux. Previous one-time #1230
  validation exceptions do not authorize new Windows-required work here.
- Capture provenance: `695dbcb0ba1e639cfde1f40f56a1724a58f028fb` plus five capsule
  source/test files, fingerprinted in the retained result. That overlay was uncommitted
  during the capture. Its delivery is tracked by #1230 and PR #1224; use the merged
  revision recorded there as the server baseline, and verify it before implementation.
- Package ZIP SHA256: `5E03DA94D77E0A45657A41D9900C0B1588CBFEA13D80F7D455B6D4035042E728`.
  Keep comparison candidate `0.14.13` and accepted height candidate `0.14.14` unchanged.

## Evidence Locations

- Server-readable handoff bundle: `/tmp/project0-handoff-1242-G3KnopGo/` on `192.168.1.254`.
  Start with `HANDOFF.md`; `handoff.tgz` and the issue's transfer receipt identify the bundle.
  `files.sha256` verifies individual retained files. Runtime databases and executable packages
  are not included. This directory is intentionally retained evidence, not a running service.
- Linux retained backend evidence: `/tmp/project0-1213-paired-3hx7ipon-evidence.jsonl`.
- Windows raw logs/assessment/fingerprints:
  `D:/code/project0-1213/build/validation/paired-runtime-9396a6e342f449c9886c06f51d3a7878/`.
- Windows accepted capsule full-validation result:
  `D:/code/project0-1213/build/validation/remote-gates-96f58ece13e2464abce90bab1da4e659/`.
- Parent evidence: https://github.com/vnvalentin/project0/issues/1213#issuecomment-5852309194
  and https://github.com/vnvalentin/project0/issues/1213#issuecomment-5852320361.
- The linked issue records the verified server-readable handoff bundle location and SHA256.