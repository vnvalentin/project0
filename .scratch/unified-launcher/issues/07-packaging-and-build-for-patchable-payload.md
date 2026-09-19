# Packaging and build changes for a patchable payload

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 04-patch-delivery-integrity-and-rollback

## Question

Given the patch pipeline (ticket 04), decide how the build produces a patchable,
versioned payload plus its manifest, replacing today's build-time embedding.

Decide:

- **Payload artifact**: what the build emits instead of an embedded `payload/`
  (versioned payload file set + generated manifest with per-file hashes and a
  version id), and where it is published for the enrollment surface to serve.
- **Version stamping**: how the build assigns and records the version id that the
  local version-record and manifest agree on.
- **Build-script changes**: the impact on
  [scripts/export_windows_client.sh](../../scripts/export_windows_client.sh) and
  [scripts/build_windows_oneclick.ps1](../../scripts/build_windows_oneclick.ps1),
  and how the launcher binary is now built independent of the payload it fetches.
- **Backward/first-install**: how a freshly downloaded launcher with no local
  payload performs its initial full install through the same patch pipeline.
- **Signing**: if the manifest/payload is signed (ticket 04), where signing
  happens in the build and where the verifying key lives in the launcher.

## Required decision output

A build/packaging spec: artifacts emitted, version stamping, manifest
generation and (if chosen) signing, publication location, and the concrete
changes to the two build scripts. This is a decision ticket, not the build work
itself.

## Answer

_(unresolved)_
