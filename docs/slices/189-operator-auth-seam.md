# Slice 189 - Operator assertion authentication seam

GitHub issue: #506

Status: **delivered**

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

The host helper independently verifies the same assertion and lifecycle scope
in `infra/operator/host_helper.py`, then executes only fixed
`systemctl start|stop|restart` vectors for allowlisted units with
`shell=False`. The authoritative Godot control seam is deployed and the
reversible authorized control proof is recorded in Slice 190.

## Validation

- Focused pytest: 10 passed for operator auth/app/host-helper coverage.
- Python compilation and diff checks passed.
- Deployed invalid bearer proof returned HTTP 403; authorized `set_degraded`
	enable and clear both returned HTTP 200 without restarting gameplay services.

## Safety and rollback

No action is executed by the verifier. Rollback is reverting the slice and
removing the optional production configuration.

## Root-cause learning

No unexpected runtime failure occurred in this slice.
