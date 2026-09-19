# Slice 149 - Phase 16 (F-037): updater transaction — atomic swap, recovery, and rollback

GitHub issue: #100 (Goal: client-auto-update); also #182 (unified-launcher), which hosts the updater

Status: **delivered**

Phase: 16 (Client delivery experience)

Feature: [F-037](../FEATURE-LIST.md#f-037-windows-client-delivery--version-identity-mandatory-gate-and-signed-patching)

Design source: [Windows client delivery contract](../../.scratch/client-auto-update/spec.md)
("Apply, restart, and rollback"),
[ADR 0008](../adr/0008-windows-client-delivery-trust-and-rollback.md) decisions
4–5. Consumes the verified staging from
[Slice 148](148-https-update-staging.md).

## Ownership deviation (auditable)

Implemented directly by Copilot under the **standing authorization** in
[AGENTS.md](../../AGENTS.md) (user, 2026-09-18). **Fallback trigger:** Claude CLI
is interactive-only on this machine. The full delivery gate was applied.

## User outcome

Installing an update can now be interrupted — killed process, power loss, a bad
patch that will not launch — and the tester still ends up with a client that
starts. A version that fails twice stops being retried rather than looping.

## Scope and non-goals

In scope: the transaction record, the atomic pack swap that retains exactly one
known-good backup, startup recovery from an interrupted swap, explicit rollback,
and the bounded retry budget.

Out of scope: the process orchestration around it — launching the updater
detached, quitting the client, relaunching it, and the post-patch readiness
check that decides whether to roll back. Also out of scope: embedding the
production public key, the launcher's LAN/WAN UI, and onboarding. Those need
packaged-Windows runtime evidence and land together in the next slice.

## Why this lives in the launcher, not the game

The updater must not depend on the artifact it is replacing. A Godot-hosted
updater would ship *inside* `Project0.pck` and could be broken by the very patch
it is applying — or by the half-written pack a previous crash left behind. The Go
launcher is a separate binary, so it still runs when the pack is missing or
corrupt. That is exactly the situation recovery exists for.

## Public seam

`native/windows_launcher/updater.go`:

- `Marker` — `pending_version`, `previous_version`, `staged_sha256`,
  `swap_started`, `attempt_count`; `LoadMarker` / `SaveMarker` / `ClearMarker`.
- `ApplyStagedPatch(dir, stagedPath, pendingVersion, previousVersion, expectedSHA256)`
- `RecoverInterrupted(dir) -> "clean" | "completed" | "rolled_back" | "repair_required"`
- `Rollback(dir)`
- `NeedsRepair(marker, version)`, `ErrRepairRequired`, `SHA256File(path)`

## Design notes

**Ordering is chosen so every interruption point is recoverable:**

```
copy staged -> Project0.pck.incoming   (same volume, so the rename is atomic)
verify the incoming copy's digest
marker.swap_started = true             (a crash after here is detectable)
rename Project0.pck          -> Project0.pck.bak
rename Project0.pck.incoming -> Project0.pck
marker.swap_started = false            (transaction closed)
```

The staged file is **copied, not renamed**, because staging lives under the user
profile and the install directory may be a different volume — where `os.Rename`
is not atomic and can fail outright. The copy is `Sync`ed before the rename so a
power loss cannot leave a renamed but empty pack.

**The digest is re-checked here even though Slice 148 already verified it.** This
process is the last thing standing between those bytes and becoming the running
client; it must not trust a handoff it cannot re-prove.

**Recovery prefers a completed swap over a blind undo.** If the new pack is
already in place and its digest matches, the update actually succeeded and the
crash merely beat the marker write — rolling back would discard a good install.
Only when the pack is absent or wrong does it restore the backup.

**A corrupt marker reads as absent.** It cannot be trusted to describe the
on-disk state, and refusing to start over it would strand the tester with no way
back.

**Two attempts, then stop.** Repeatedly re-applying a patch that bricks the
client is worse than sitting on the last known-good build and asking for help. A
*different* version gets a fresh budget, so one bad release does not poison the
next.

## BDD

1. Given a verified staged patch, then it is installed and exactly one backup
   remains.
2. Given a digest that does not match, then the patch is refused and the original
   pack and scratch files are untouched.
3. Given a crash after the backup rename, then startup restores the known-good
   pack.
4. Given a crash after the new pack landed, then startup keeps it.
5. Given no pack and no backup, then startup reports `repair_required`.
6. Given nothing in flight, then startup is a no-op.
7. Given a failed readiness check, then rollback restores the previous pack.
8. Given no backup, then rollback is refused.
9. Given a version that fails twice, then further attempts return
   `ErrRepairRequired` and the known-good pack stays in place.
10. Given a newer version, then it gets a fresh attempt budget.
11. Given a corrupt marker, then it reads as "nothing in flight".

## Validation

- `go vet ./...` in `native/windows_launcher` — clean.
- `go test ./...` — **ok** (module `project0/windows-launcher`), including the
  pre-existing enrollment tests.
- `go test -v` for the new tests — **11/11 PASS**:
  `TestApplyStagedPatchInstallsAndKeepsOneBackup`,
  `TestApplyRefusesAPatchWhoseDigestDoesNotMatch`,
  `TestRecoveryRestoresTheKnownGoodPackAfterAnInterruptedSwap`,
  `TestRecoveryKeepsASwapThatActuallyCompleted`,
  `TestRecoveryReportsRepairWhenNothingCanBeRestored`,
  `TestRecoveryIsANoOpWhenNothingWasInFlight`,
  `TestRollbackRestoresThePreviousPack`,
  `TestRollbackWithoutABackupIsRefused`,
  `TestARepeatedlyFailingVersionStopsRetrying`,
  `TestADifferentVersionGetsAFreshAttemptBudget`,
  `TestACorruptMarkerIsTreatedAsAbsent`.
- Full GUT suite on the Linux host — unchanged (this slice touches no GDScript).
- `bash scripts/check_record_sync.sh` → 0 errors, exit 0.

Interruptions are simulated by performing the same file operations
`ApplyStagedPatch` performs and then stopping, so recovery runs against real
on-disk states rather than mocks.

## Root-cause learning

No unexpected failure arose. One authoring error was caught by `go vet`/compile
before it could run: the corrupt-marker test was initially written without its
`*testing.T` parameter, so it would have been silently ignored as a non-test
function rather than failing — the Go equivalent of the "GUT silently skips a
script that fails to preload" trap already recorded in the shared agent notes.
Countermeasure applied here: the per-test `--- PASS` list was read and counted
rather than trusting the package-level `ok`.

### Post-merge correction (2026-09-18): the pack is not file-locked

A follow-up probe against the **real packaged Windows client** disproved a
justification this slice and ADR 0008 relied on.

- **Symptom / prior belief:** the records stated a running Godot process "cannot
  safely replace its active `.pck`" because the running exe/pck are file-locked.
  The Go tests could not detect this either way, because they ran against
  `t.TempDir()` with no process holding the files.
- **Falsifiable hypothesis:** Windows refuses `os.Rename` on `Project0.pck` while
  `Project0.exe` holds it open.
- **Discriminating check:** launch the packaged client, then attempt rename,
  open-for-write, and delete against the live process.
- **Confounder ruled out first:** the exe genuinely depends on the separate pack
  — removing it yields `Couldn't load project data at path "."` — so the probe
  measured the real artifact and not an embedded copy.
- **Result:** all three operations **succeeded** against a live client. The pack
  is not locked.
- **Why this matters:** the OS provides *no* protection here, so the updater's
  ordering and transaction marker are the only thing standing between a live
  client and a half-applied swap. The conclusion (quit, then swap) is unchanged,
  but it now rests on the hot-reload limitation and on lazy resource loads
  otherwise mixing new content with old code — not on a lock that does not exist.
- **Records corrected:** ADR 0008, `.scratch/client-auto-update/spec.md`, and the
  auto-update map now carry the measured correction.

Two process lessons from the probe itself, both of which produced a *confidently
wrong* first verdict:

1. The first probe leaked an `O_TRUNC` handle on the file under test, so later
   steps were blocked by the probe rather than by the client — and it reported
   the opposite of the truth. Restore state between checks and close every
   handle.
2. Its liveness check read `cmd.ProcessState` before `Wait()`, which is always
   `nil`, so "client still running" was meaningless. Track liveness with a
   goroutine on `Wait()`.

The tell was an internally contradictory result (an operation refused *after* the
process exited but permitted while it ran). A self-contradictory measurement is
evidence about the instrument, not the system.

## Follow-on

The process orchestration (launch detached, quit, relaunch, post-patch readiness
check driving `Rollback`) and embedding the production public key land next, with
packaged-Windows runtime evidence. Until that exists, **no claim is made that
end-to-end self-update works** — only that the transaction mechanics are correct.
