# Align development admission with the verified standalone client

Governing GitHub issue: #1421. Parent goal: #158.
User approved the version-setting change and game-only restart on 2026-10-02.
This is a cross-cutting incident correction, not a new milestone commitment.

## Outcome And Scope

Accept the published native-verified 0.14.21 client at the existing game
admission boundary. Preserve exact-version rejection for every other build.
Install the one-line non-secret server-admission.env as the previously absent
/apps/project0/deploy/.env. Recreate only game-server with --no-deps --pull never.
Do not pull an image, restart login/enrollment, change authentication, alter
data mounts or modify any account, Character or Canon data.

## Hypothesis And Discriminating Checks

The server rejects 0.14.21 because its required version is still 0.14.20.
Live log: client=0.14.21 required=0.14.20 outcome=CLIENT_OUTDATED.
The current Compose rendering differs from the live environment only at that
setting, and its local main image tag resolves to the running immutable image.
Prediction: after pinning 0.14.21, that native client's version handshake is
ACCEPTED; old/mismatched versions remain rejected. No equality rule changes.

SDD: change operator configuration only, keeping the existing admission and
authentication contracts. BDD: matching build accepted; mismatched build
rejected; selected Character enters the existing authoritative world.
TDD: run the existing pure version-handshake fixture against the same runtime
image in a network-isolated temporary container before restarting the service.
The image excludes unit-test files, so copy only the unchanged, hash-bound
merged-main fixture from the existing Linux checkout; no Windows branch is
checked out or executed on Linux. This is supporting component evidence only.

## Safety And Rollback

Capture the old image, game/login IDs, normalized mount/port fingerprints and
the old required-version value. Verify the installed env file's exact bytes.
Render Compose privately and fail if any environment value except the version
differs, or if image/mount/port identity changes. Never expose secret values.
Before restarting, require the same local image ID; use --pull never.
Retain durable evidence and clean the owned fixture/container in a finally
path. If restart or post-restart checks fail, remove only the newly installed
.env and recreate only game-server with the old 0.14.20 override and same image.
Existing services and persistent volumes are not rollback targets.

## Evidence And Completion

Record preflight, focused test verdict/counts, fixture/image hashes, restart
command, resulting container/config fingerprints and cleanup on #1421.
Confirm the service is healthy and login's container ID is unchanged.
Then require real Windows 0.14.21 admission and Character-to-world evidence.
Health, configured version and unit tests alone cannot close the issue.
Missing user login or runtime evidence leaves an explicit awaiting-evidence
status and next owner/action, never a gameplay success claim.