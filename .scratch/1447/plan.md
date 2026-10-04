# Prediction listener ownership diagnostic

Governing issue: [#1447](https://github.com/vnvalentin/project0/issues/1447). Related validation: #1444; original discovery: resolved #1339. Owner: vnvalentin. Cross-cutting unscheduled technical debt, without a milestone or named slice-group commitment.

## Goal and scope

Distinguish a selected UDP port number from an actual owned ENet listener. One fixed public GUT case and fixture exercise controlled takeover after probe release, successful binding after controlled release, and actual-listener ownership through OS-assigned binding. Historical listener startup cause remains UNKNOWN.

Scope is fixture-only native networking on the owning Linux runtime. No production server hooks, client or Windows behavior, database/authentication operations, deployments, dependency additions or host-wide network/process discovery.

Unacceptable outcomes include relaxed prediction assertions, retry-as-pass, fallback ports, serialized concurrent regression, shared host changes, unknown error output qualifying, lost source/custody binding or leaked fixture resources.

## Hypothesis and public seam

The prediction fixture closes its UDP probe before the child binds the selected port. A fixture-owned takeover can make the fresh ENet bind fail. Binding the actual ENet listener at port zero and reading its bound port should retain ownership until close.

Public case: `test_probe_release_gap_and_bound_port_ownership` in `tests/integration/test_prediction_port_ownership.gd`. Future fixture public API: `run() -> Dictionary` in `tests/fixtures/prediction_port_ownership.gd`.

Given a held fixture takeover, the fresh ENet bind must fail; after releasing that occupier, a fresh bind must succeed. Given a held actual OS-assigned ENet listener, a second fresh peer targeting the actual port must fail while the first remains active. Every operation executes once; setup failure stops the case.

## TDD and validation

The first tracer asserts that the fixed fixture exists and returns after one ordinary missing-fixture assertion. Initial RED establishes presence only. It performs no loading, threading, networking or measurement. Initial presence GREEN is never complete diagnostic acceptance.

After qualified RED, implement only the fixed controlled workload and complete public assertions. Preserve the tracer guard. Narrow source-derived classification permits only the deliberately induced engine errors within their exact phases; unrelated errors fail closed. No global error suppression or canonical-runner modification is allowed.

Ignored private execution plans bind the actual source, controller, preparation and selected case before ownership preflight. Copied positive/negative controls and independent Standards/Spec reviews precede Root's native execution. Reuse unified preparation, evidence retention/readback and owned-process teardown. Unknown fixture/source/evidence custody preserves the owned stage. Private exact commands and runtime evidence remain local; public records contain status only.

Canonical full GUT and record sync remain required before delivery. Focused results do not waive them or establish milestone acceptance, historical cause or production adoption.

## Status, rollback and learning

Status: initial presence RED and complete retained evidence readback qualified. The fixed three-phase fixture and complete public assertions are now authored for source review; native diagnostic behavior and canonical delivery remain pending.

Rollback removes or reverts only issue-owned diagnostic files and records, preserving owner changes and historical evidence. Root coordinates qualification and next implementation; reviews do not grant execution authority.

Historical symptom: listener startup failure. Historical cause: UNKNOWN. Confirmed source liability: probe release before child bind. Existing coverage verifies selection and normal success without a controlled takeover or retained actual-listener ownership check. Countermeasure and regression results remain unobserved. Production default-preserving hooks and readiness handshake remain proposals outside this diagnostic.

## Fixed implementation boundary

The diagnostic uses only new loopback PacketPeerUDP and ENetMultiplayerPeer objects. Every setup or result failure reaches a common close/release epilogue. Host references are read only through immediate get_host().get_local_port() expressions; no host alias survives close. The closed result reports fixed enums and observational booleans that remain null until attempted, with no address, port or process values. Positive same-port ENet rebinds after the common close observe actual release of both selected and OS-assigned listener ports; they execute once and close their own peers.

The public case preserves its original missing-fixture guard and asserts the exact typed closed result, every controlled positive/negative outcome and both release controls. Historical cause remains UNKNOWN and production adoption remains NOT_OBSERVED. Fixed expected-error begin/end markers surround only the two intentionally rejected create_server calls; the private classifier must validate their exact source-authored engine marker, phase order and count. Missing, duplicated, out-of-phase or unrelated errors fail closed. Canonical GUT error handling is unchanged.

Root-cause learning for validation preparation: review found an omitted unrelated-engine-error verdict guard in the inherited initial adapter. A bounded copied-command counterexample established the false green; strict rejection and the regression control were independently reviewed and qualified. The private plan now declares the existing consumer deadline accurately. Pre-dispatch source review also corrected a status-prefix capture guard without executing the flawed supervisor. Detailed evidence remains local; these validation corrections establish neither port behavior nor historical cause.

ADR rationale: this fixture-only diagnostic introduces no production architecture, ownership, routing or persistence decision. No new ADR is required or adopted; proposed production readiness hooks remain outside this issue.
