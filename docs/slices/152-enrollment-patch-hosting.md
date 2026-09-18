# Slice 152 - Phase 16 (F-037): enrollment HTTPS `/patches` hosting

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Unified launcher" and "Manifest, patch, and trust"),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the standing authorization in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). Claude CLI remains interactive-only
on this machine; the full delivery gate was applied.

## User outcome

The release artifacts can now live beside the existing public HTTPS enrollment
service at `https://enroll.valentin.vip/patches`, with the service exposing only
that release directory and the container receiving it read-only. An outdated
client can reach `manifest.json`, `manifest.sig`, and its versioned `Project0.pck`
without authenticating first; the RSA signature, not the URL, remains the trust
anchor.

## Scope and non-goals

In scope: FastAPI static hosting under `/patches`, an `ENROLLMENT_PATCHES_DIR`
configuration seam, and a read-only `/var/lib/project0/patches` compose mount.
The route is disabled when no directory is configured, preserving existing test
and development app construction.

Out of scope: generating or uploading release artifacts, TLS/reverse-proxy
configuration outside the existing enrollment surface, manifest signing,
updater orchestration, launcher UI, or public directory listing policy.

## Public seam

- `infra/enrollment/app.py`: `create_app(..., patches_dir=...)` mounts
  `StaticFiles(directory=patches_dir, html=False)` at `/patches` when configured.
- `infra/enrollment/asgi.py`: resolves `ENROLLMENT_PATCHES_DIR` and passes it to
  production app construction.
- `deploy/compose.yml`: sets `ENROLLMENT_PATCHES_DIR=/var/lib/project0/patches`
  and mounts `${ENROLLMENT_PATCHES_DIR:-/var/lib/project0/patches}` read-only.

Expected release layout:

```text
/var/lib/project0/patches/
  manifest.json
  manifest.sig
  0.7.0/Project0.pck
```

The signed manifest's `pck_url` points at the versioned path. The host directory
is intentionally not writable from the container.

## Security boundary

The route is public and unauthenticated by design: the version gate happens
before authentication, so an outdated client must be able to retrieve its
patch. Public availability does not imply trust. The client verifies the RSA
signature and pack digest before staging; a malicious or compromised host can
only serve bytes the client refuses unless it also has the offline private key.

`html=False` avoids turning the route into a directory-index surface. Missing
files return bounded 404 responses from Starlette. The compose mount is read-only
so a compromised enrollment process cannot rewrite the served release artifacts
in place.

## BDD

1. Given a configured patches directory with `manifest.json`, then
   `GET /patches/manifest.json` returns it publicly.
2. Given `manifest.sig` and a versioned pack, then both are publicly reachable
   under `/patches`.
3. Given a missing artifact, then the route returns 404.
4. Given no configured patches directory, then `/patches/*` is not mounted and
   existing app construction remains unchanged.
5. Given the compose service, then the patches directory is mounted read-only
   and the container points at `/var/lib/project0/patches`.

## Validation

- Enrollment pytest suite: `pytest -q infra/enrollment/tests` passes with the
  new static-files test.
- Compose config inspection confirms the read-only patches mount and env path.
- `bash scripts/check_record_sync.sh` exits 0.

## Root-cause learning

No unexpected runtime failure. The hosting path deliberately reuses the existing
FastAPI/TLS enrollment surface rather than introducing another public service or
certificate boundary. The release directory remains an operator-published
artifact; this slice does not pretend to prove a production upload or proxy
reload.

## Follow-on

The release operator still needs to publish a signed release into the host
patches directory and run the packaged-client update flow. The next product slice
is the updater process orchestration and packaged-Windows runtime evidence.
