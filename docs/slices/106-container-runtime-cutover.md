# Slice 106 - Container runtime cutover

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing P-014.

## User outcome

Every Project0 service now runs from an image published by CI, deployed by
pulling an immutable tag. The deployment host no longer supplies build
artifacts, so the runtime can be reproduced on any Docker host instead of only
on okami.

## Scope and non-goals

In scope: `deploy/compose.yml`, `scripts/deploy_containers.sh`, the
`deploy-servers` job in `.github/workflows/release.yml`, and the live cutover
of the game, login, and enrollment services from systemd units to containers.

Out of scope: splitting the login authority into its own image
([DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase)),
zone-server sharding
([deferred ticket](../../.scratch/zone-sharding/issues/01-zone-server-sharding-model.md)),
deleting `scripts/deploy_all.sh` (kept until a tag deploy has run end to end),
and migrating historical account data — the user confirmed data loss was
acceptable at this stage, so the cutover started from empty volumes.

## Public seam

`scripts/deploy_containers.sh --tag <image-tag> [--profiles a,b] [--dry-run]
[--no-rollback]`. The release workflow calls it on a `v*` tag.

## Design notes

- Images are pulled **before** anything stops, so a missing or bad tag fails
  the deploy while the current stack is still serving.
- A tag push starts the image build and the deploy concurrently, so the pull
  retries on a bounded schedule to absorb registry propagation instead of
  failing a legitimate release.
- Images are tagged `type=ref,event=tag` as well as semver, because
  `{{version}}` strips the leading `v` while `GITHUB_REF_NAME` keeps it. Without
  the raw ref tag the deploy would never resolve its own release.
- The rollback target is written **only after** health passes, so it always
  names a tag observed healthy on this host.
- Health is the proof of a deploy: declared healthchecks must report `healthy`,
  and containers without one must still be `running` after the wait, which
  catches a crash loop.
- Persistent data stays in host volumes under `/var/lib/project0`; a deploy
  never writes there.

## Safety invariants

- No secret is in the compose file or in any image; they are read from
  `/etc/project0/*.env`, outside the repository and the images.
- The operator and dashboard services are profile-gated, so a default
  `up` cannot expose the internal control plane.
- The operator service is bound to loopback only.
- A failed health gate redeploys the previously healthy tag unless
  `--no-rollback` is given.

## Acceptance scenarios

1. Given a published tag, when the deploy runs, then all services reach health
   and the tag is recorded as the rollback target.
2. Given a tag that does not exist, then the pull fails after bounded retries
   and nothing is changed.
3. Given a service that fails health, then the previous tag is redeployed.
4. Given `--dry-run`, then images and current state are resolved and nothing
   changes.

## Validation

Focused validation: live cutover on okami with runtime health evidence from all
three services, plus dry-run resolution and shell/YAML parse checks.

## Validation evidence

- Dry run resolved `ghcr.io/vnvalentin/project0-godot:main` (x2) and
  `project0-infra:main`; no changes made.
- Systemd units `project0-server`, `project0-login`, `project0-enrollment`
  stopped and disabled; UDP 9999/9998 and TCP 8095 confirmed free first.
- Deploy reached `all services healthy (attempt 2)`.
- **Runtime evidence, not just container state:** game server health file
  `status: healthy`, `server_tick: 11100`, `tick_rate: 30`,
  `uptime_seconds: 184.9`; login server `server_tick: 11130`. The fixed-tick
  loops are advancing, not merely bound.
- `GET http://192.168.1.254:8095/healthz` returned **HTTP 200**.
- `ss -lnup` confirmed `192.168.1.254:9999` and `192.168.1.254:9998` bound by
  the containers.
- Rollback target `/var/lib/project0/deployed-tag` contains `main`.

## Root-cause learning

- Symptom: the enrollment container crash-looped with
  `PermissionError: [Errno 13] Permission denied: '/data'`.
- Public seam: `deploy/compose.yml`, enrollment service startup.
- Hypothesis: the non-root container user lacked write access to its volume.
- Discriminating check: read `ENROLLMENT_DB_PATH` from
  `/etc/project0/enrollment.env`.
- Confirmed root cause: the host env file pins
  `ENROLLMENT_DB_PATH=/data/code/project0/infra/enrollment/.data/enrollment.sqlite3`
  — an **in-tree host path** that is meaningless inside the container. The
  service tried to create `/data` as uid 10001 and was denied. The value was
  correct for the systemd deploy and silently wrong for a container.
- Why existing tests missed it: the Python tests inject their own DB path, and
  the earlier container smoke test used image defaults, so the host env file's
  path had never been exercised in a container.
- Countermeasure: `environment:` in compose overrides `env_file:` and pins the
  DB to the mounted volume. Recorded in the file so the override is not
  mistaken for duplication.
- Remaining limitation: other host env files may carry further in-tree paths
  that only surface when that code path runs. The env files are host state
  outside the repository, so this is not statically checkable from here.

- Symptom: `deploy_containers.sh: line 127: /var/lib/project0/deployed-tag:
  Permission denied`, though the deploy still completed.
- Confirmed root cause: the script used a failed redirect as control flow
  (`> file 2>/dev/null || sudo tee`). Bash reports a redirection failure before
  the `2>/dev/null` on that same command applies, so the error printed even
  though the fallback worked.
- Countermeasure: write via `sudo -n tee` directly rather than relying on a
  failed redirect. Verified the rollback target is readable and correct.

- Symptom: after the cutover every JIT sector request logged
  `Ignored provisional sector <id>: Generation did not reach validation.`
- Public seam: `SectorBlueprintService.request_blueprint` via the containerized
  game server.
- Hypothesis: the container could not reach the Ollama service on the host.
- Discriminating check: `ss -lntp | grep 11434` on the host (listening on `*`)
  versus a request to `127.0.0.1:11434` from inside the container (no route).
- Confirmed root cause: **two** independent faults. First, `127.0.0.1` inside a
  container is the container's own loopback, so the host's Ollama was
  unreachable — a regression introduced by this cutover. Second, and
  pre-existing, `server/sector_blueprint_service.gd` built its `LocalLLMClient`
  from its own hardcoded `@export var ollama_host` and never called
  `configure_from_env()`, so `PROJECT0_OLLAMA_HOST` reached only the
  boot-town client. Fixing only the first would have left generation broken
  while appearing addressed.
- Why existing tests missed it: the container healthcheck proves the tick loop
  is alive, not that world generation succeeds, and no test exercises the
  sector path against a real Ollama endpoint.
- Countermeasure: `configure_from_env()` is now called on the sector path's
  client (it only overrides an untouched export, so explicit configuration
  still wins), and compose sets `PROJECT0_OLLAMA_HOST` to the host's LAN
  address. The LAN address is used rather than `host.docker.internal` because
  Godot's HTTP client performs its own name resolution and does not reliably
  honor a `/etc/hosts` alias, which an earlier attempt proved.
- Regression evidence: an in-container probe using `configure_from_env()`
  resolved `http://192.168.1.254:11434`, model `llama3:latest`, and returned
  `success=true outcome=success raw={"ok": true}` from a live generation.
- Remaining limitation: `scripts/probe_ollama.gd` constructs its client
  **without** `configure_from_env()`, so it always tests `127.0.0.1` and cannot
  validate an environment override. It produced a false negative during this
  investigation and should not be trusted for that purpose.

- Symptom: every WAN client login failed. `POST /login` returned HTTP 502 with
  `{"detail":"upstream_unavailable"}`, which the Windows launcher surfaced to
  the user as a malformed response.
- Public seam: `POST /login` on the public enrollment service.
- Hypothesis: the enrollment container could not reach the login authority.
- Discriminating check: the same request direct to the container bypassing
  nginx returned the identical 502 with `server: uvicorn`, proving the failure
  was the application's own upstream call and not the reverse proxy.
- Confirmed root cause: the enrollment service delegates `/login` to the login
  authority over `127.0.0.1:9997`, and
  `server/login_loopback_http_endpoint.gd` binds the **literal** `127.0.0.1` by
  deliberate design (ADR 0005 loopback delegation; the file states the bind is
  "never resolved from NetworkConfig"). Under systemd both processes shared one
  host, so that loopback was the same interface. This cutover placed them in
  separate network namespaces, so each container's `127.0.0.1` became its own
  and the delegation target vanished.
- Why existing tests missed it: the Python tests inject a fake login-authority
  client, and the container healthcheck only proves the enrollment process
  answers `/healthz` — which it did, correctly, throughout the outage. No test
  exercises the delegation across a real process boundary.
- Countermeasure: the enrollment service now runs with
  `network_mode: "service:login-server"`, sharing the login server's network
  namespace so `127.0.0.1` is the same interface for both processes. This
  reproduces the single-host topology the design assumes and keeps the endpoint
  unreachable from outside, rather than rebinding it to `0.0.0.0` and breaking
  the ADR 0005 boundary. Enrollment's published port moves to the login-server
  service, because a container sharing another's namespace cannot publish ports.
- Regression evidence: `POST /login` with deliberately invalid credentials
  returned **401 Unauthorized** both directly (`192.168.1.254:8095`) and through
  the public endpoint (`https://enroll.valentin.vip/login`), where it had
  returned 502 before — proving the request now reaches the login authority and
  receives a real verdict.
- Remaining limitation: this was the **third** defect of the same class in this
  cutover (Ollama host, enrollment DB path, login delegation). Each was
  configuration that silently assumed a single host. Remaining host-assumed
  values in `/etc/project0/*.env` are host state outside the repository and are
  not statically checkable from here.

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Tech debt: [DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase)
- Prior slice: [105](105-container-images-and-registry.md)
- Deferred design: [zone-server sharding](../../.scratch/zone-sharding/issues/01-zone-server-sharding-model.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 106
