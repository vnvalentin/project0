# Slice 157 - Phase 16 (F-037): visible WAN package and opt-in stable-directory updates

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher)

Status: **in progress; initial release-ready, post-release update hardening deferred**

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

## Reconciliation with Nakama delivery

The public WAN gameplay path is now validated separately by [Slice 181](181-nakama-live-gameplay-bridge.md)
under [F-039](../FEATURE-LIST.md#f-039-nakama-v1-entry-and-realtime-foundation):
two fresh Nakama-authenticated clients completed session validation, Character
and world entry, shared match binding, movement submission, and
Project0-authoritative state return. That evidence supersedes any earlier
assumption that Slice 157 must prove the WAN gameplay transport itself.

Slice 157 remains open only for the distinct Windows client-delivery contract.
Initial release requires visible package contents, stable installation,
explicit onboarding, clean packaged boot, and executable first-install evidence.
Live update and rollback are deliberately deferred until after initial release
and must be completed before automatic updates are enabled or advertised.
Nakama runtime validation does not by itself prove those launcher lifecycle
gates.

## Invariants

- Signed manifest and PCK verification remain unchanged.
- The existing atomic swap and rollback transaction remains disabled from the
	initial-release claim until its packaged runtime proof is complete.
- The enrollment container remains read-only over release artifacts.
- LAN users continue using the portable client ZIP.

## Validation

- `GOOS=windows GOARCH=amd64 go test ./...` passes in `native/windows_launcher`.
- `GOOS=windows GOARCH=amd64 go vet ./...` passes.
- `bash -n scripts/package_client_linux.sh scripts/publish_client_downloads.sh` passes.
- `git diff --check` passes.
- GitHub Actions run [35519933553](https://github.com/vnvalentin/project0/actions/runs/35519933553)
	completed successfully for version `0.12.0`. It produced the portable client
	ZIP (31,833,880 bytes), launcher EXE (8,282,112 bytes), launcher ZIP
	(36,522,362 bytes), and manifest. The manifest recorded
	`source_tree_dirty: false`, `godot_export_exit_code: 0`, and
	`godot_cpp_ref: d5cc777`; the portable ZIP contained exactly
	`Project0.exe` and `Project0.pck`. This proves release artifact production,
	not the deferred update transaction.
- Native Windows runtime evidence for the current package completed with a clean
	`Project0.exe --headless --quit-after 2` boot and a real launcher first install
	into an isolated `%LOCALAPPDATA%/Project0/payload` directory; exit code was 0
	and both payload files were present. Live update and rollback evidence remains
	post-release work by decision.
- A real Windows launcher rollback probe then invoked
	`Project0-Launcher-0.12.0-proof.exe --project0-update-helper` against an
	isolated payload with a deliberately invalid staged PCK. The relaunched client
	failed readiness and the original payload PCK was restored byte-for-byte.
	The GUI-subsystem launcher did not expose a reliable process exit code through
	the PowerShell harness; the on-disk restoration assertion passed. Signed
	download and valid-update runtime evidence remain open.
- The native launcher verifier was also exercised against the published HTTPS
	patch host using its embedded trusted public key. The live manifest and
	detached signature verified, the signed PCK downloaded, and the staged file
	matched the signed byte count. The private signing key was not present on the
	workstation and no new release artifact was generated. Valid-update relaunch
	evidence remains open.
- [Slice 181](181-nakama-live-gameplay-bridge.md) provides the current WAN
	gameplay evidence: both fresh clients exited 0 after Nakama session,
	Character, world-entry, shared-match, movement, and authoritative-state
	validation. This supports the public access boundary but does not substitute
	for the Windows launcher lifecycle checks above.

## Root-cause learning

- Symptom: the first Linux package attempt left the stamped client-version
	contract modified after export. The affected seam was
	`scripts/package_client_linux.sh`'s version-stamping cleanup.
	Hypothesis: the exit trap could not restore the source because the backup
	path was never populated. The discriminating check was inspection of the
	backup setup and a post-failure comparison with `HEAD`.
	Confirmed root cause: the script created a temporary backup filename but
	omitted the copy into it. Countermeasure: copy the contract before stamping;
	the focused syntax and cleanup checks now pass. The corrected package
	workflow produced the expected artifacts; runtime evidence remains pending.
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