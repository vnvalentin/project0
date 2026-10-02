# Authored item creation rules — #950

Milestone3/M3.2; related #1341/#1342; parent #749/#495. Issue-first brief: https://github.com/vnvalentin/project0/issues/950#issuecomment-5956825268 . Formula decision: https://github.com/vnvalentin/project0/issues/950#issuecomment-5956780515 . Foundation closed on accepted b173445; Harness77de008a consumed. Server-authoritative deterministic creation properties are the player outcome.

## SDD / public seam / non-goals

Closed ItemCreationProfile.from_wire_dict, to_wire_dict and derive; profile/blueprint/tuning pins and explicit authored units/bounds/coefficients/offset/divisor/clamps. Fixed v1 floor arithmetic with nonnegative bounded integers. Tuning exists only under tests/fixtures. No default/live balance, client authority, registry/expression engine, ItemInstance fields, decay, DB migration or deployment. Atomic persistence/authority integration is a later dependent increment.

## BDD / TDD

One tracer first: authored material81/catalyst60/station40 yields literal purity81/quality65/durability206. Missing module must cause exactly one assertion RED with no compile errors, then minimal evaluator GREEN. Expand vertically for malformed inputs/profiles, unknown versions, arithmetic bounds and defensive copy behavior. Native results pending. Required full GUT/record-sync/reviews before merge; #950 stays open.

## Validation / safety / rollback

Linux192.168.1.254 via strict SSH. Validated ownership plan .scratch/950-rules/validation-plan.json; focused wrapper owns XDG/dashboard and cleanup. Shared native flock /tmp/project0-m4-01a0fcfa-validation.lock. No concurrent native commands. No DB opened by evaluator; sqlite declared because godot-server suite requires it. Revert additive evaluator/tests; no live adoption.

## Root-cause learning

Preflight rejected initial plan before runtime: suite dependency declaration omitted sqlite. Public seam check_validation_ownership.py; hypothesis mandatory godot-server suite requires sqlite even for a pure server helper. Report build/validation/950-rules/preflight.json confirms missing declared dependency. Countermeasure: declare existing server-owned sqlite in the plan, then rerun preflight; no install or platform relocation. Runtime was not executed. Narrow plan validation, not product tests, detects this metadata omission. Superseding passed preflight retained separately below.

Corrected preflight: build/validation/950-rules/preflight-corrected.json passed, runtime_executed=false. Tracer/runtime RED pending shared host window; no behavior claim.
