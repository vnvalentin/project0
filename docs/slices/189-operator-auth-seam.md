# Slice 189 - Operator assertion authentication seam

GitHub issue: #165

Status: **in progress**

Phase: 17 (Fleet operations console)

Feature: [F-041](../FEATURE-LIST.md#f-041-fleet-operations-console)

## Outcome

The operator control plane can independently verify a bounded Project0 assertion
for operator identity and scopes before accepting privileged requests.

## Public seam

`infra/operator/operator_auth.py::verify_operator_token` validates the existing
base64-payload/HMAC assertion shape, issuer/audience, time window, identity, and
scope bounds. `infra/operator/app.py` uses this verifier when
`PROJECT0_ASSERTION_SECRET_HEX` is configured; injected bearer-token mode remains
available for existing deterministic tests.

## Remaining work

The host helper and authoritative Godot control seam still need to independently
verify the same assertion and enforce action scopes. No privileged action is
claimed implemented by this slice alone.

## Validation

- Focused pytest: 8 passed for operator auth/app coverage.
- Python compilation and diff checks passed.

## Safety and rollback

No action is executed by the verifier. Rollback is reverting the slice and
removing the optional production configuration.

## Root-cause learning

No unexpected runtime failure occurred in this slice.
