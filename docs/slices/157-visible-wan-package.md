# Slice 157 - Phase 16 (F-037): visible WAN package and opt-in stable-directory updates

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **in progress**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

## User outcome

The WAN download is a visible package containing the launcher, Godot client,
PCK, and native DLL. The launcher installs those files into the stable
`%LOCALAPPDATA%/Project0` directory and asks for confirmation before downloading
or applying a signed update.

## Scope and non-goals

In scope: external package files instead of Go-embedded payloads, stable local
installation, explicit update confirmation, and release packaging of the
visible WAN folder.

Out of scope: Authenticode certificate acquisition and Microsoft Defender
submission, which require operator-owned identity and portal actions.

## Invariants

- Signed manifest and PCK verification remain unchanged.
- Updates still use the existing atomic swap and rollback transaction.
- The enrollment container remains read-only over release artifacts.
- LAN users continue using the portable client ZIP.

## Validation

- `GOOS=windows GOARCH=amd64 go test ./...` passes in `native/windows_launcher`.
- `GOOS=windows GOARCH=amd64 go vet ./...` passes.
- `bash -n scripts/package_client_linux.sh scripts/publish_client_downloads.sh` passes.
- `git diff --check` passes.
- The packaging workflow is being rerun on the delivery branch after fixing
	cleanup, package-directory creation, manifest defaulting, and branch-safe
	artifact naming. Slice completion remains blocked until that run produces
	the ZIP, launcher, and manifest artifacts.

## Root-cause learning

- Symptom: the first Linux package attempt left the stamped client-version
	contract modified after export. The affected seam was
	`scripts/package_client_linux.sh`'s version-stamping cleanup.
	Hypothesis: the exit trap could not restore the source because the backup
	path was never populated. The discriminating check was inspection of the
	backup setup and a post-failure comparison with `HEAD`.
	Confirmed root cause: the script created a temporary backup filename but
	omitted the copy into it. Countermeasure: copy the contract before stamping;
	the focused syntax and cleanup checks now pass. Remaining limitation: the
	complete package workflow still needs to produce its artifacts.
- Symptom: the package script exported the client but failed while assembling
	the launcher archive. The affected seam was the versioned launcher package
	directory. Hypothesis: the destination directory was absent. The
	discriminating check was the first failing copy command in the package
	step. Confirmed root cause: the script removed the directory and copied into
	it without recreating it. Countermeasure: create the directory before the
	copies; the focused script and launcher tests pass.
- Symptom: CI failed at manifest generation with an unbound `GODOT_CPP_REF`.
	The affected seam was the release workflow's package manifest. Hypothesis:
	the script assumed a locally exported variable that CI did not provide. The
	discriminating check was the failed line under `set -u`. Confirmed root
	cause: no default existed despite the documented pinned revision.
	Countermeasure: default to `d5cc777` while preserving an explicit override.
- Symptom: branch validation failed while uploading an otherwise completed
	package because the artifact name contained `/`. The affected seam was the
	release workflow artifact handoff. Hypothesis: `github.ref_name` was used
	directly for a slash-bearing branch. The discriminating check was the
	Actions error naming the invalid artifact. Confirmed root cause: branch names
	are not valid artifact-name components. Countermeasure: use the unique
	numeric workflow run ID for upload and download names.
- Symptom: the successful CI manifest reported `source_tree_dirty: true` on a
	clean checkout. The affected seam was manifest provenance. Hypothesis: the
	temporary export stamp was still present when the manifest inspected Git.
	The discriminating check was the manifest value plus the script's restore
	order. Confirmed root cause: restoration was deferred to the process exit
	trap, after manifest generation. Countermeasure: restore immediately after
	export and disable the now-completed trap; the source is clean before the
	remaining package steps.