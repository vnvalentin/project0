# Project0 operator control plane (Slice 061)

Private, operator-authenticated **read-only status** service for the Project0
host services, per the
[operator control-plane decision](../../.scratch/container-platform/issues/04-operator-control-plane-and-telemetry.md).
It is loopback-bound and separate from the public enrollment path. Mutating
actions (restart, invites, revoke, update) are follow-up slices behind an
audit/job model.

## Endpoints

- `GET /healthz` — unauthenticated liveness.
- `GET /status` — all allowlisted services' state (bearer token required).
- `GET /status/{name}` — one allowlisted service (404 if not allowlisted).
- `POST /services/{name}/restart` — restart an allowlisted service; returns an
  audited job (bearer token required; optional `X-Operator` header for identity;
  404 if not allowlisted).
- `GET /jobs` — recent operator jobs (bearer token required).

Authentication is a bearer token compared with `hmac.compare_digest`: missing →
401, wrong → 403.

Every mutating action is wrapped in an audited job (`requested → running →
succeeded/failed`) with a correlation id, operator identity, target,
timestamps, and a bounded outcome. Restarting a systemd unit as the non-root
service user needs a polkit/sudoers grant for that unit; docker restarts work
for a user in the docker group.

## Allowlist

Only these names are inspectable (`config.py::DEFAULT_SERVICES`):

| name | kind | identifier |
| --- | --- | --- |
| `game-server` | systemd | `project0-server` |
| `enrollment` | systemd | `project0-enrollment` |
| `dashboard` | docker | `project0-flow` |

Every state read is a fixed argument vector (`systemctl is-active <unit>` /
`docker inspect -f {{.State.Status}} <container>`) — no shell, no
caller-supplied command, no mutation.

## Run (Linux host)

```sh
sudo install -m 600 infra/operator/operator.env.example /etc/project0/operator.env
# Edit /etc/project0/operator.env: set a long random OPERATOR_TOKEN, then:
sudo install -m 644 infra/operator/project0-operator.service /etc/systemd/system/project0-operator.service
sudo systemctl daemon-reload
sudo systemctl enable --now project0-operator.service
curl -fsS -H "Authorization: Bearer $OPERATOR_TOKEN" http://127.0.0.1:8099/status
```

## Tests

```sh
.venv-enrollment/bin/python -m pytest infra/operator/tests
```
