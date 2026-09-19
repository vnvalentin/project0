# Runtime boundary and container adapter

Status: resolved
Assignee: Copilot
Type: grilling
Blocked by: none

## Question

What is the authoritative game server's container/runtime contract? Decide the
container image/runtime format, host supervisor relationship, fixed-tick and
health contract, UDP/network exposure, resource limits, filesystem/data volume,
non-root policy, graceful shutdown, and local validation boundary. The answer
must support the current Linux host and preserve a native systemd rollback path.

## Required decision output

A handoff-ready runtime contract and a bounded P-014 implementation route.

## Resolution

The authoritative game server will be packaged as an OCI-compatible container
using a repository Dockerfile and Compose-compatible deployment descriptor.
Docker is the initial host target because the existing host already runs the
Project0 flow dashboard with Docker Compose; the image format remains portable
to Podman if the host standard changes.

The Linux host keeps systemd as the top-level lifecycle supervisor. The native
`project0-server.service` remains available as the rollback implementation until
container equivalence and cutover evidence are complete. The future operator
control plane talks to an allowlisted systemd/container adapter, never arbitrary
shell commands.

The deployment application root is:

```text
/apps/project0/
```

This directory owns the Project0 container application descriptors, image
build/deployment metadata, and release manifests. The stable application and
container identity is `project0`. Persistent runtime data MUST live outside the
application tree in an explicit host-managed location, initially:

```text
/var/lib/project0/
```

The game container contract is:

- expose authoritative ENet/UDP port `9999`;
- run as a non-root user;
- receive only the explicit `/var/lib/project0` data mount;
- keep the repository checkout and client private keys outside the container;
- receive no OPNsense API credentials;
- provide a bounded fixed-tick runtime contract;
- provide a machine-readable health signal;
- handle graceful termination and bounded shutdown;
- apply resource limits and a read-only image/filesystem wherever writable
  paths are not required;
- emit bounded structured telemetry suitable for the operator interface.

The first P-014 implementation route is: build image, run locally with a
temporary data volume, prove boot/health/tick/UDP/shutdown/persistence, run
beside the native server on an isolated port or host, perform equivalence and
rollback checks, then cut over the host service to the container.

## Acceptance evidence

The implementation slice must prove the container starts from `/apps/project0`,
binds UDP `9999` when deployed, remains healthy across a bounded runtime
window, shuts down cleanly, persists data through container replacement, runs
without root, and leaves the native systemd service available for rollback.

## Decision status

Resolved by user confirmation on 2026-09-14. No production files were changed
by this planning decision.
