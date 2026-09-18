# Slice 156 - Phase 16 (F-037): release pipeline publishes Windows client downloads

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **in progress**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

## User outcome

A tagged release publishes the self-updating Windows launcher and portable ZIP
on the existing public enrollment HTTPS site. A player can open one stable URL
and choose the launcher download without needing GitHub Actions access.

## Scope and non-goals

In scope: downloading the CI artifact in the tagged release deployment job,
publishing versioned client files under `/patches/downloads/`, and generating a
small explicit HTML download page.

Out of scope: changing signed patch verification, making the artifact directory
writable from the enrollment container, or enabling directory listings.

## Public seam and invariant

- `https://enroll.valentin.vip/patches/downloads/` serves the generated page.
- The launcher and ZIP are copied into `/patches/downloads/<version>/`.
- The enrollment container remains read-only over the published directory.
- Only strict `MAJOR.MINOR.PATCH` versions are published.

## Rollback

The publisher writes only the versioned download directory and index page. A
previous page or version can be restored from the host's deployment backup, and
the signed `/patches/manifest.json`, signature, and pack remain untouched.

## Validation

- `bash -n scripts/publish_client_downloads.sh` passes.
- Invalid versions fail closed with exit 2.
- Enrollment pytest suite: 122 passed.
- Tagged release workflow must publish the artifact and verify the public page
  and both client download links after deployment.