# Slice 108 - Retire the git-archive deploy path
GitHub issue: #95

Status: **delivered**

Phase: 7 (Delivery workflow capabilities), advancing P-014.

## User outcome

There is exactly one way to deploy Project0: published container images pulled
by tag. The superseded path is gone rather than left lying around, so it cannot
be run by mistake or mistaken for the supported route.

## Scope and non-goals

In scope: deleting `scripts/deploy_all.sh`, `scripts/deploy_server.ps1`, and
`deploy/services.json`; repointing `.github/workflows/deploy-rehearsal.yml` at
`scripts/deploy_containers.sh`; removing the dead `-DeployServer` stage from
`scripts/build_current_deployment.ps1`; and exercising the deploy failure and
rollback paths that had never been run.

Out of scope: deleting the systemd unit files (`scripts/project0-*.service`,
`infra/*/project0-*.service`). They are inert, are not referenced by any
pipeline, and document the pre-container topology; removing them is a separate
decision.

## Public seam

`scripts/deploy_containers.sh --tag <image-tag>` is now the only deploy entry
point. `scripts/build_current_deployment.ps1` builds a local Windows client
package only and no longer touches any server.

## Design notes

- `scripts/deploy_server.ps1` was not merely unused, it was **actively
  harmful**: it restarted `project0-server` and `project0-login`, which Slice
  106 stopped and disabled, and replaced `/data/code/project0`. Running it after
  the container cutover would have broken the stack rather than deployed it.
- `deploy/services.json` described systemd units and their health contracts.
  `deploy/compose.yml` now holds that role, so the registry was orphaned rather
  than merely redundant. Adding a service is still one entry, now in compose.
- `deploy-rehearsal.yml` was still rehearsing the retired path, so the weekly
  runner health check was exercising code no release used.
- The `preserve_runtime_state` machinery, the host venv rebuild, and the
  pre-restart `--check-only` parse validation all disappeared with
  `deploy_all.sh`. Each existed to compensate for the deploy root lacking build
  artifacts; the image carries them, so none has a replacement.

## Safety invariants

- Deleting a deploy script cannot affect a running container; the stack is
  driven by `deploy/compose.yml` and the recorded tag.
- The rehearsal workflow remains dry-run only.
- No secret, volume, or persistent path changed.

## Acceptance scenarios

1. Given a tag that does not exist, when a deploy runs, then it fails before
   stopping anything and the running stack is untouched.
2. Given a service that cannot become healthy, when a deploy runs, then the
   previously healthy tag is redeployed and the failure is reported.
3. Given the rehearsal workflow, when it runs, then it resolves images from
   `deploy/compose.yml` and changes nothing.
4. Given the Windows client pipeline, when it runs, then it produces client
   artifacts and contacts no server.

## Validation

Focused validation: deliberate failure injection against the live stack on
okami for both the missing-tag and failed-health paths, plus a rehearsal dry
run and a PowerShell parse check.

## Validation evidence

- **Missing-tag path (previously untested):** deploying
  `v9.9.9-does-not-exist` failed with `image pull failed for tag ...; nothing
  was changed`, and all three containers remained `Up (healthy)` on `v0.1.1`.
- **Rollback path (previously untested):** injecting a service that cannot
  become healthy produced
  `still not healthy: operator(restarting)` →
  `ROLLBACK: redeploying previous tag v0.1.1` →
  `ERROR: deploy of 'v0.1.1' failed health; rolled back to 'v0.1.1'`.
  The injected container was then removed and the stack redeployed clean; all
  three services `Up (healthy)`, recorded tag `v0.1.1`.
- Rehearsal dry run on the host resolved
  `project0-infra:v0.1.1` and `project0-godot:v0.1.1` (x2) and changed nothing.
- `.github/workflows/deploy-rehearsal.yml` parsed by PyYAML.
- `build_current_deployment.ps1` passed a PowerShell parser check after the
  `-DeployServer` stage was removed.
- No dangling reference to `deploy_all.sh`, `deploy_server.ps1`,
  `services.json`, or `-DeployServer` remains in any `.yml`, `.sh`, or `.ps1`.

## Root-cause learning

- Symptom: none observed in production — this was found by inspection while
  retiring the old path.
- Confirmed issue: `scripts/deploy_server.ps1` survived the container cutover
  and still targeted systemd units that Slice 106 had disabled. A Windows
  operator running the documented command would have overwritten the deploy
  root and restarted dead units, taking the stack down.
- Why existing tests missed it: nothing tests that a *retired* path has been
  retired. Slice 106 changed the runtime but left the previous entry point
  executable, and the two were only connected by intent.
- Countermeasure: delete superseded deploy entry points in the same slice that
  supersedes them, rather than leaving them for later cleanup.

## Known limitation

Rollback reverts the **image tag only**. It re-runs `docker compose up` with
the previously healthy tag and the *current* compose file, so a bad change to
`deploy/compose.yml` itself is not covered — the rollback would reapply the
same broken configuration. Test B demonstrated this directly: the injected
failure came from a compose profile, so the rollback redeployed the identical
profile and the run still ended in a reported failure. Covering compose changes
would require versioning the compose file alongside the image tag.

## Record links

- Feature: [P-014](../FEATURE-LIST.md#p-014-containerized-fixed-tick-authoritative-server-runtime)
- Supersedes: [Slice 104](104-registry-driven-deploy.md),
  [Slice 101](101-server-deployment-pipeline.md)
- Prior slice: [106](106-container-runtime-cutover.md)
- Phase tracker: [PROJECT-TRACKER.md](../PROJECT-TRACKER.md#phase-7--delivery-workflow-capabilities)
- Registry: [SLICE-REGISTRY.md](SLICE-REGISTRY.md), reservation 108
