# Client version check and patch manifest contract

Status: open
Assignee: (unassigned)
Type: grilling
Blocked by: 01-prior-art-eqemu-and-launcher-patterns, 02-lan-wan-mode-selection-checkbox

## Question

Define how the launcher learns whether the installed client payload is current,
and the **manifest** that describes the authoritative current payload.

Decide:

- **Version source of truth**: where the installed payload's version is stored
  and read locally, and what identifies a version (semantic version, build id,
  content hash).
- **Manifest schema**: the server-owned document listing the current version and
  the payload file set with per-file size and hash (and the overall version id),
  bounded and validated like every other Project0 contract.
- **Serving surface**: confirm the manifest is served from the existing HTTPS
  enrollment surface ([infra/enrollment/](../../infra/enrollment/)) and the
  route/shape, keeping the public surface minimal (DT-009 rate-limiting
  relation).
- **When the check runs**: launcher stage ordering (before onboarding? before
  launch?) and whether a check is required every run or throttled.
- **LAN-mode interaction**: whether version checking/patching applies in LAN
  mode at all (no WAN patch server assumed on a LAN), or is WAN-only. This
  depends on the mode contract from ticket 02.

## Required decision output

A validated manifest schema, the local version-record format, the serving
route, the stage at which the check runs, and the LAN-vs-WAN applicability rule.
Feeds the patch-delivery ticket.

## Answer

_(unresolved)_
