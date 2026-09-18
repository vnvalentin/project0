# Slice 144 - Phase 16 (F-037): client build version identity and export-time stamp

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher), since the launcher consumes the same version identity

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Version identity"), [ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md)
decision 1. This is the first implementation slice of the accepted Phase 16
handoff and the root dependency of every later slice in it.

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** recorded in
[AGENTS.md](../../AGENTS.md) and
[.github/copilot-instructions.md](../../.github/copilot-instructions.md)
(user, 2026-09-18). **Fallback trigger:** Claude CLI is interactive-only on this
machine — both `claude "…"` and `claude -p "…"` open a full-screen TUI and return
no session or evidence, and the repository's `Claude:` VS Code tasks fail with
`Variable ${relativeFile} can not be resolved`. The delivery gate was applied in
full regardless: records-first, issue traceability, public-seam tests, executed
validation, record sync, and branch/PR/merge.

## User outcome

A packaged Windows client now knows its own build version at runtime. Previously
the version existed only in the ZIP file name, so a running client could not tell
the server what build it was, and the server had no way to compare. This is the
identity every later Phase 16 capability compares against.

## Scope and non-goals

In scope: the in-pack `ClientBuildVersion` contract (the authoritative runtime
build version plus fail-closed semver validation) and the export-time stamping
that writes the released version into that contract before the Godot export, so
it travels *inside* `Project0.pck`.

Out of scope (later slices of the same accepted contract): the pre-auth version
handshake and its rejection enum, the server-owned
`PROJECT0_REQUIRED_CLIENT_VERSION` gate, the signed update manifest and its
verification, HTTPS patch staging, the detached updater/atomic swap/rollback,
launcher LAN/WAN and onboarding changes, and the controller placeholder. Nothing
in this slice contacts the network, compares versions, or changes packaging
layout.

## Public seam

- `shared/client_build_version.gd` (`ClientBuildVersion`):
  - `CLIENT_BUILD_VERSION` — the stamped constant, checked in at the current
    default so source runs and tests are stable.
  - `current() -> String` — the running client's build version.
  - `is_valid(version: Variant) -> bool` — fail-closed `MAJOR.MINOR.PATCH`
    validation (numeric parts only, no leading zeros, no prefix/suffix).
- `scripts/stamp_client_build_version.sh <version>` — deterministic, idempotent
  generator for the file above; refuses a malformed version with a non-zero exit
  and writes nothing.
- `scripts/export_windows_client.sh` — stamps before exporting and restores the
  working tree afterward.

## Design notes

The version lives **inside the pack** rather than in executable metadata because
the pack is the unit the later integrity model signs and hashes: a version the
attacker can edit without invalidating the signed pack hash would be worthless to
the gate. Executable/product metadata stays informational only.

The generator is a separate script rather than inline export logic so the stamp
can be exercised and reviewed without a full Godot export (which needs Windows
export templates), and so the Linux packaging script can adopt the same seam
later. Stamping restores the original file on exit, so running an export never
leaves the working tree dirty or silently re-versions the source checkout.

## BDD

1. Given a source checkout, when a client reads `ClientBuildVersion.current()`,
   then it returns the checked-in stamped version.
2. Given the shipped constant, when it is validated, then it is a well-formed
   semver string.
3. Given a well-formed `MAJOR.MINOR.PATCH` string, when validated, then accepted.
4. Given a malformed version (empty, `1.2`, `1.2.3.4`, `v1.2.3`, `1.2.x`,
   negative, leading-zero, whitespace, or a non-String), when validated, then
   rejected.
5. Given the stamp script and a valid version, when it runs, then the contract
   file contains exactly that version and re-running is idempotent.
6. Given the stamp script and a malformed version, when it runs, then it exits
   non-zero and leaves the contract file unchanged.

## Validation

Executed on the Linux host (working-tree overlay onto the deploy tree, since
this depends on merged-but-undeployed Phase 15 files):

- `bash scripts/run_gut_validation.sh` → **734/734 tests passing across 101/101
  scripts, 2351 asserts, exit 0** (from 729/100 on `main`: +1 script, +5 tests,
  exactly the new test file). 4 pre-existing headless warnings, unrelated.
- `bash scripts/stamp_client_build_version.sh` behavior, asserted directly:
  - baseline `0.6.0` → stamp `1.4.9` → file reads `1.4.9`;
  - re-stamping `1.4.9` produced a byte-identical file
    (`md5 e848dd27d052300a2b555fe657a59e84` before and after) — idempotent;
  - six malformed inputs (``, `1.2`, `v1.2.3`, `1.2.3.4`, `01.2.3`, `1.2.x`)
    each exited `1` and left the contract file unchanged — fail-closed;
  - restamping `0.6.0` restored the original value.
- `bash scripts/check_record_sync.sh`.

New test: `tests/unit/test_client_build_version.gd` (5 tests) covering
`current()`, the shipped constant's well-formedness, accepted versions, thirteen
malformed strings, and six non-String inputs.

## Root-cause learning

**Product defect caught by validation (before merge).** The stamp script's guard
and substitution anchored on `"$`. Symptom: on the first real run the script
refused a file that visibly contained the expected line
(`stamp: … does not contain the expected CLIENT_BUILD_VERSION assignment`, while
`grep "^const CLIENT_BUILD_VERSION"` matched). Falsifiable hypothesis: the anchor,
not the content, was wrong. Discriminating check: the prefix-only grep matched
while the `"$`-anchored one did not — proving a trailing character after the
closing quote. Root cause: the Windows working copy has CRLF endings, so `"$`
never matches (a `\r` sits between the quote and the line end). Existing tests
missed it because the GDScript contract is line-ending agnostic and nothing
exercised the shell generator. Countermeasure: guard on the prefix only and bound
the substitution with `"[^"]*"`, which rewrites the value while preserving
whatever line ending the file uses; regression evidence is the passing
positive/idempotent/fail-closed run above. Remaining limitation: the stamp is
verified by direct invocation rather than by a committed automated test, because
the suite is GUT/GDScript and does not execute shell scripts.

**Environment failure.** The Claude CLI handoff could not run non-interactively
(symptom: every invocation returned "the command opened the alternate buffer"
with no output), and a launched session wedged the persistent shell so later
commands returned the same message. The discriminating check was running a
trivial `echo`/`git` command in a **new** terminal, which succeeded — proving the
shell integration was wedged by the TUI rather than the repository being broken.
Countermeasure: the standing-authorization rule now recorded in `AGENTS.md`, the
Copilot instructions, and `.agents/repo-memory.md`, plus the recovery note (start
a new terminal; do not retry the wedged one).

## Follow-on

The next slice in the accepted contract is the pre-auth version handshake
(`shared/version_handshake.gd` plus the server gate), which consumes
`ClientBuildVersion.current()` delivered here.
