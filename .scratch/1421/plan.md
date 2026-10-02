# Compatible standalone Windows client

Governing GitHub issue: #1421
Parent goal: #158
User approval: 2026-10-02, build and validate a matching standalone replacement.
Outcome: select an owned Character and enter the existing authoritative world.
Cross-cutting incident correction; no new milestone or launcher commitment.

## Scope And Safety

Build immutable version 0.14.21 from merged source on SETSUJOKU. Preserve
0.14.20, all other worktrees, the deployed server image and persistent data.
No gameplay code, authentication, launcher, auto-update or server changes.
Use the existing builder, dependency audit and compiled package probe.

## Hypothesis And Checks

The published 0.14.20 pack has an incompatible RPC contract. Current merged
source includes the server's newer declarations. Compare all annotated RPC
declarations against deployed revision 4715092ecae5e7808c2fc019eb21002b0ce00955;
then build and run the real release EXE's native package probe on Windows.
The original symptom is only resolved when native Character selection reaches
gameplay without RPC checksum errors against both deployed services.

SDD: keep the transport/authentication contract unchanged; replace only the
client artifact using an explicitly versioned, immutable archive and manifest.
BDD: an authenticated player selects their Character and enters gameplay;
an altered archive/PCK must be rejected before execution.
TDD: reuse existing package checks, including the compiled RPC/geometry probe;
there is no application-code change or new unit test in this packaging slice.

## Validation And Evidence

Run validation-plan.json preflight on 192.168.1.254 before native checks.
Use the qualified Godot 4.7.2 editor and existing Windows export templates.
Retain the builder result, boundary audit, manifest, archive/member hashes and
native windowed verifier evidence. Do not count offline package verification,
container health or a source comparison as authenticated gameplay acceptance.
Record the exact source revision, host, commands and artifacts on #1421.
Delivery/review gates and real Character-to-world evidence remain required.

## Root-Cause Learning

Symptom: 0.14.20 hangs at Selecting character while both native client and
login server report NetworkClient RPC checksum failures. Login dispatch also
misidentifies client calls as unrelated authority-only methods.
Boundary: Windows client -> Linux login ENet RPC -> authenticated world entry.
Discriminating evidence: the installed PCK matches the published hash; the
servers share image 937e863ee7288d569ce0d5a74d3d118f28e64e17056f7f9aac24fd40ee25cdec.
Commit 221a910 added receive_sector_entry_denied after 0.14.20 was built.
Confirmed failure: incompatible method tables; the exact compiled old table
and why prior acceptance missed the incompatible pairing remain unverified.
Countermeasure: build a matching immutable client and require native evidence.
Regression: ownership preflight, all 51 source RPC declaration comparisons,
immutable export/dependency audit and native windowed compiled-package probe
passed. World-entry result: pending. No workaround bypasses authentication.

An unexpected delivery gate failed when main advanced concurrently to 638b62c:
the route's merge-base ancestry check rejected the original branch head.
Refreshing PR #1422's base repairs the stale identity; the new main commit
changes an unrelated planning record, not the package's application inputs.
CI confirmation remains pending. The existing package keeps its original
clean f84edee264e1d0c052aa5344893a6f90fb4c41a2 identity, never a new identity.

## Rollback And Completion

Rollback is selecting the untouched old client; never overwrite a version.
Existing build/verifier tools own temporary state and teardown. A failed gate
leaves the issue blocked with evidence and a next action. Keep #1421 open until
the package, review/record gates and authenticated world-entry evidence pass.