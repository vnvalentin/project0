# Slice 056 — Game-server container image and run-beside-native

Status: **delivered**

Phase: 10 (Authoritative runtime and action input), advancing
[P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime).
Second delivery of the
[container-platform map](../../.scratch/container-platform/map.md), implementing
the [runtime-boundary decision](../../.scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md).

## User outcome

The authoritative Godot server can be built as a reproducible OCI image and run
beside the existing native systemd server on an isolated UDP port, without
changing the running server or any gameplay behavior. This proves the container
runtime boundary before any cutover.

## Scope and non-goals

In scope: a `deploy/game-server/` Dockerfile, entrypoint, and Compose descriptor
that package the pinned Godot 4.3 headless runtime plus the project source,
bake the import cache at build time, run `server/server_main.gd` headless as a
non-root user, expose the authoritative ENet/UDP port, and shut down gracefully
on `SIGTERM`. A repository `.dockerignore` keeps the build context lean. A
port-bound container `HEALTHCHECK` proves the authoritative socket is listening.

Out of scope (later slices): the persistence path split to `/var/lib/project0`
and backup/restore (Slice 057); wiring the Slice 055 `ServerHealth` snapshot to
a machine-readable health file/endpoint; the operator control plane; the
login-service split; and the production cutover/rollback from the native
service (migration decision). This slice runs the container beside the native
server and then stops it; it does not change `project0-server.service` or any
`.gd` file, so the GUT suite is unaffected.

## Public seam

`deploy/game-server/`:

- `Dockerfile` — pinned `godot` 4.3-stable headless base, project source, baked
  `--import` cache, non-root user, `EXPOSE 9999/udp`, entrypoint.
- `entrypoint.sh` — resolves bind address/port/data dir from environment,
  forwards `SIGTERM` to Godot for graceful shutdown, runs
  `godot --headless --path . -s server/server_main.gd`.
- `docker-compose.yml` — builds from the repo root context, publishes the
  authoritative UDP port on an isolated host port, mounts a writable data
  volume, sets a non-root user, resource limits, and a port-bound healthcheck.
- `.dockerignore` (repo root) — excludes `.git`, `build/`, the `godot-cpp`
  source tree, the Windows launcher, and other non-runtime paths.

## Safety invariant

The container is additive and isolated: it binds only the published isolated
UDP port, runs non-root, receives no OPNsense credentials or client keys, and
never touches the native `project0-server.service` or the live data. Stopping
or removing the container leaves the host exactly as before.

## ADR rationale

No new ADR. The OCI image, systemd supervision, `/apps/project0` application
root, `/var/lib/project0` data boundary, UDP 9999, and non-root policy are
already fixed by the accepted runtime-boundary decision.

## BDD / TDD

There is no GUT seam for an image; the delivery evidence is runtime, per
`AGENTS.md` ("container claims require evidence in the matching environment").
Acceptance scenarios, proven on the Linux host `192.168.1.254` beside the
native server:

1. **Build.** The image builds reproducibly from the repo root context.
2. **Boot.** `docker run` reaches `Server listening on 0.0.0.0:9999` and the
   accounts/Canon schema initializes inside the container.
3. **Bind.** The published isolated host UDP port is bound while the container
   runs.
4. **Health.** The container `HEALTHCHECK` reports healthy.
5. **Graceful shutdown.** `docker stop` (SIGTERM) exits cleanly within the
   stop timeout.
6. **Non-interference.** The native `project0-server.service` and its port are
   untouched throughout.

## Validation

- Full GUT gate on the Linux host: `scripts/run_gut_validation.sh` (expected
  unchanged 326/326 across 45/45 scripts, exit 0 — this slice adds no `.gd`).
- `scripts/check_record_sync.sh` (exit 0).
- Runtime container evidence (build, boot log, port bind, healthcheck, graceful
  stop) captured on `192.168.1.254` beside the native server. Recorded on
  completion.

### Runtime evidence (Linux host `192.168.1.254`, 2026-09-14)

Built and run beside the live native server in an isolated `git worktree`, on
isolated host port `127.0.0.1:19999` (native server untouched on UDP 9999):

1. **Build.** `docker compose ... build` exit 0; pinned Godot 4.3-stable
   downloaded, `godot --version` succeeded, import cache baked, image
   `project0-game-server:candidate` created.
2. **Boot.** Container log reached `Server listening on 0.0.0.0:9999`;
   `Opened database successfully (.../accounts.db)`, `Starting town Canon
   ready: ok.`, `Accounts database ready ... (schema ensured)`. The
   server-critical `godot-sqlite` extension loaded at runtime (no `Native class
   "SQLite" not found` at run time).
3. **Bind.** `ss -uln` showed `127.0.0.1:19999` bound while running.
4. **Health.** `docker inspect` reported `healthy` (port-bound HEALTHCHECK).
5. **Graceful shutdown.** `docker compose stop` completed in ~0.39s, exit 143
   (clean SIGTERM via tini), well under the 20s stop-grace/SIGKILL timeout.
6. **Non-interference.** Native UDP 9999 stayed bound and
   `systemctl is-active project0-server` reported `active` throughout; the
   candidate container, volume, network, and image were removed afterward,
   leaving the host as before.

## Root-cause learning

Observed: the container log emits a non-fatal `GDExtension dynamic library not
found: /app/native/wgnetstack/gdext/build/libwgnetstack_gdext.linux.template_debug.x86_64.so`
and `Failed loading ... wgnetstack.gdextension` at startup.

Hypothesis and check: the wgnetstack `.so` is a compiled, git-ignored build
artifact (client WireGuard tunnel), so a fresh git checkout used as the build
context does not contain it. Discriminating check: the server nonetheless
reached `Server listening` and `healthy`, and the server-only `godot-sqlite`
extension loaded, confirming wgnetstack is not on the server's runtime path.

Root cause: the server image ships the client tunnel extension descriptor but
not its (client-only, uncommitted) binary. The `NetworkClient` autoload
tolerates the class being unavailable at runtime, so this is a benign warning,
not a failure. Removing the descriptor from the server image was deliberately
not done in this slice to avoid a parse-time `WgNetstack` identifier break in
the shared `client/network_client.gd` autoload; a dedicated follow-up should
either exclude client-only tunnel code from the server image behind a verified
seam or make the tunnel reference fully optional. Tracked as a benign
limitation of the container image, not a P-014 blocker.
