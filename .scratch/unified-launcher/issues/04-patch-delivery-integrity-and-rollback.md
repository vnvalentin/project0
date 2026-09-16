# Patch delivery, integrity verification, atomic apply, and rollback

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 03-version-check-and-patch-manifest

## Question

Given the manifest from ticket 03, decide how an out-of-date payload is brought
current safely, and how the launcher stops embedding the payload at build time.

Decide:

- **Delivery model**: full-file replacement versus delta/binary-diff downloads;
  which files are fetched (only changed, per manifest hashes).
- **Integrity and authenticity**: per-file hash verification against the
  manifest, and whether the manifest itself is signed (and by which existing key
  mechanism) so a tampered manifest cannot direct a malicious payload.
- **Atomic apply**: download to a staging location, verify, then swap the live
  payload directory atomically so an interrupted patch never leaves a
  half-updated client.
- **Rollback**: retain the prior payload so a failed verify/apply or a failed
  first launch of the new version can revert; when the prior copy is discarded.
- **Storage move**: relocate the payload from the launcher's embedded `payload/`
  to an on-disk, launcher-managed install directory (AppData vs install path),
  and what the launcher does on very first install (no prior payload present).
- **Failure UX**: bounded, user-legible outcomes for download failure, integrity
  failure, and apply failure, consistent with the launcher's existing
  `MessageBoxW` failure surface.

## Required decision output

A patch pipeline spec: fetch -> verify -> stage -> atomic swap -> rollback, with
the integrity/signature model, the on-disk layout, and the enumerated failure
outcomes. Feeds packaging/build (ticket 07) and the integration ticket.

## Answer

_(unresolved)_
