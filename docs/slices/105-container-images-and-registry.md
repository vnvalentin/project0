# Slice 105 - Container images for every service, published to GHCR

Status: **in progress**

Phase: 7 (Delivery workflow capabilities), advancing F-002 and P-014.

## User outcome

Every deployable Project0 service has a reproducible container image built by
CI and published to GHCR, addressable by an immutable tag. This is the
prerequisite for replacing the `git archive` deploy model, whose artifacts
exist only on the deployment host.

## Scope and non-goals

In scope: `deploy/infra/Dockerfile` (shared Python control-plane image),
`deploy/infra/Dockerfile.dockerignore`, and `.github/workflows/images.yml`
publishing `project0-godot`, `project0-infra`, and `project0-dashboard`.

Out of scope: deploying from those images, cutting production over from the
systemd units, retiring `scripts/deploy_all.sh`'s preserve-and-restart model,
and splitting the login authority into its own image
([DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase)).
All of that is Slice 106.

## Public seam

`ghcr.io/vnvalentin/project0-<service>:<tag>`, where tag is the git tag, the
branch name, or the full commit SHA. Nothing deploys from these images yet, so
the current runtime is unaffected.

## Design notes

- **One image per runtime family, not per service.** `project0-godot` serves the
  game and login servers, and will serve a future zone server, because they are
  one codebase differing only by entrypoint. `project0-infra` serves enrollment
  and operator, which pin an identical `requirements.txt`. Both couplings are
  deliberate and recorded as
  [DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase).
- The root `.dockerignore` was written for the game-server image and excludes
  `infra/`, `dashboard/`, and `tests/`. Docker allows one ignore file per
  context root, so the infra image uses BuildKit's
  `<dockerfile>.dockerignore` override rather than weakening the game-server
  build context.
- Pull requests build every image but never push. Publishing is gated on
  `github.event_name != 'pull_request'` so a fork PR cannot write to the
  registry.
- Images are public on GHCR, which is free for public packages, and Actions
  pulls authenticated with `GITHUB_TOKEN` are free on hosted and self-hosted
  runners alike.

## Safety invariants

- The workflow publishes only; it deploys nothing and touches no host.
- `permissions` is `contents: read` plus `packages: write`, nothing more.
- No secret is baked into any image. Both Python services fail closed at import
  when required configuration is absent, which this slice verified.
- Both Python services run as a non-root uid with no writable state in the
  image.

## Acceptance scenarios

1. Given a push to `main` or a `v*` tag, when the workflow runs, then all three
   images build and are pushed to GHCR with branch/semver/SHA tags.
2. Given a pull request, when the workflow runs, then images build but are not
   pushed.
3. Given the shared infra image, when started with the enrollment target, then
   `/healthz` returns 200; when started with the operator target, the same.
4. Given required configuration is absent, then the service exits non-zero at
   startup rather than serving in a degraded state.

## Validation

Focused validation: image build and container smoke test on the Linux host
okami, plus workflow YAML parse. Full GUT and record-sync remain required.

## Validation evidence

- `docker build -f deploy/infra/Dockerfile` succeeded; image size 250 MB.
- Enrollment target: `GET /healthz` returned **HTTP 200**.
- Operator target from the **same image**, entrypoint overridden to
  `uvicorn infra.operator.asgi:app`: `GET /healthz` returned **HTTP 200**.
- Fail-closed confirmed: startup aborted with `OPNSENSE_API_KEY and
  OPNSENSE_API_SECRET must be set`, then `ENROLLMENT_SERVER_PUBLIC_KEY must be
  set`, then `OPERATOR_TOKEN must be set` — each a non-zero exit, never a
  degraded start.
- `.github/workflows/images.yml` parsed by PyYAML; one job, three matrix images.

## Root-cause learning

- Symptom: `docker build` for the infra image failed with
  `"/infra": not found` on `COPY infra/ /app/infra/`.
- Public seam: `deploy/infra/Dockerfile` build context.
- Hypothesis: the path was wrong in the Dockerfile.
- Discriminating check: `cat .dockerignore` at the repository root.
- Confirmed root cause: the root `.dockerignore` excludes `infra`, `dashboard`,
  `tests`, and `docs` because it was authored for the single game-server image.
  Once more than one image shares the repository root as its build context, a
  single root ignore file silently removes another image's source.
- Why existing tests missed it: only one image had ever been built from this
  repository, so the ignore file had never been wrong before.
- Countermeasure: `deploy/infra/Dockerfile.dockerignore`, which BuildKit
  prefers over the root file, ignoring everything and re-including `infra/`.
  The game-server context is untouched.
- Remaining limitation: any future image added at the repository root needs its
  own `<dockerfile>.dockerignore`, or it will inherit the game-server
  exclusions. Noted in the file's own comment.

## Record links

- Feature: [F-002](../FEATURE-LIST.md#f-002-portable-windows-client-package),
  [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Tech debt: [DT-012](../TECHNICAL-DEBT-TRACKER.md#dt-012-login-authority-shares-the-game-servers-image-and-codebase)
- Deferred design: [zone-server sharding](../../.scratch/zone-sharding/issues/01-zone-server-sharding-model.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 105
