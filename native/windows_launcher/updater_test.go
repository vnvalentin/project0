package main

// Slice 149 (Phase 16, F-037): updater transaction tests. The interesting cases
// are the interruptions — a swap killed halfway must always leave a launchable
// pack behind. Crashes are simulated by performing the same file operations
// ApplyStagedPatch performs and then stopping, rather than by mocking, so the
// recovery path is exercised against real on-disk states.

import (
	"os"
	"path/filepath"
	"testing"
)

const (
	oldPackContents = "OLD PACK v0.6.0"
	newPackContents = "NEW PACK v0.7.0"
)

func writeFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatalf("writing %s: %v", path, err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	return string(raw)
}

func digestOf(t *testing.T, path string) string {
	t.Helper()
	sum, err := SHA256File(path)
	if err != nil {
		t.Fatalf("hashing %s: %v", path, err)
	}
	return sum
}

// installWithStagedPatch builds an install directory holding the old pack plus a
// separate staging directory holding the new one.
func installWithStagedPatch(t *testing.T) (dir string, staged string, stagedSHA string) {
	t.Helper()
	dir = t.TempDir()
	stagingDir := t.TempDir()
	writeFile(t, packPath(dir), oldPackContents)
	staged = filepath.Join(stagingDir, packName)
	writeFile(t, staged, newPackContents)
	return dir, staged, digestOf(t, staged)
}

func TestApplyStagedPatchInstallsAndKeepsOneBackup(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)

	if err := ApplyStagedPatch(dir, staged, "0.7.0", "0.6.0", sha); err != nil {
		t.Fatalf("apply failed: %v", err)
	}
	if got := readFile(t, packPath(dir)); got != newPackContents {
		t.Errorf("pack = %q, want the new pack", got)
	}
	if got := readFile(t, backupPath(dir)); got != oldPackContents {
		t.Errorf("backup = %q, want the previous pack", got)
	}
	if _, err := os.Stat(incomingPath(dir)); !os.IsNotExist(err) {
		t.Error("the incoming scratch file should not survive a completed swap")
	}
	if marker := LoadMarker(dir); marker.SwapStarted {
		t.Error("a completed swap must not leave swap_started set")
	}
}

func TestApplyRefusesAPatchWhoseDigestDoesNotMatch(t *testing.T) {
	dir, staged, _ := installWithStagedPatch(t)

	err := ApplyStagedPatch(dir, staged, "0.7.0", "0.6.0", "not-the-real-digest")
	if err == nil {
		t.Fatal("expected a digest mismatch to be refused")
	}
	if got := readFile(t, packPath(dir)); got != oldPackContents {
		t.Errorf("pack = %q, want the original to be untouched", got)
	}
	if _, err := os.Stat(incomingPath(dir)); !os.IsNotExist(err) {
		t.Error("a refused patch must not leave scratch files behind")
	}
}

func TestRecoveryRestoresTheKnownGoodPackAfterAnInterruptedSwap(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)

	// Simulate a crash after the backup rename but before the new pack landed.
	if err := SaveMarker(dir, Marker{
		PendingVersion: "0.7.0", PreviousVersion: "0.6.0",
		StagedSHA256: sha, SwapStarted: true, AttemptCount: 1,
	}); err != nil {
		t.Fatalf("marker: %v", err)
	}
	if err := os.Rename(packPath(dir), backupPath(dir)); err != nil {
		t.Fatalf("simulating interruption: %v", err)
	}
	_ = staged

	outcome, err := RecoverInterrupted(dir)
	if err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if outcome != "rolled_back" {
		t.Errorf("outcome = %q, want rolled_back", outcome)
	}
	if got := readFile(t, packPath(dir)); got != oldPackContents {
		t.Errorf("pack = %q, want the known-good pack restored", got)
	}
	if marker := LoadMarker(dir); marker.SwapStarted {
		t.Error("recovery must close out the transaction")
	}
}

func TestRecoveryKeepsASwapThatActuallyCompleted(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)

	// Crash after the new pack landed but before the marker was cleared: the
	// update succeeded, so undoing it would throw away a good install.
	writeFile(t, backupPath(dir), oldPackContents)
	writeFile(t, packPath(dir), newPackContents)
	if err := SaveMarker(dir, Marker{
		PendingVersion: "0.7.0", PreviousVersion: "0.6.0",
		StagedSHA256: sha, SwapStarted: true, AttemptCount: 1,
	}); err != nil {
		t.Fatalf("marker: %v", err)
	}
	_ = staged

	outcome, err := RecoverInterrupted(dir)
	if err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if outcome != "completed" {
		t.Errorf("outcome = %q, want completed", outcome)
	}
	if got := readFile(t, packPath(dir)); got != newPackContents {
		t.Errorf("pack = %q, want the successfully installed pack kept", got)
	}
}

func TestRecoveryReportsRepairWhenNothingCanBeRestored(t *testing.T) {
	dir := t.TempDir()
	if err := SaveMarker(dir, Marker{
		PendingVersion: "0.7.0", StagedSHA256: "deadbeef", SwapStarted: true, AttemptCount: 1,
	}); err != nil {
		t.Fatalf("marker: %v", err)
	}

	outcome, err := RecoverInterrupted(dir)
	if err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if outcome != "repair_required" {
		t.Errorf("outcome = %q, want repair_required", outcome)
	}
}

func TestRecoveryIsANoOpWhenNothingWasInFlight(t *testing.T) {
	dir, _, _ := installWithStagedPatch(t)

	outcome, err := RecoverInterrupted(dir)
	if err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if outcome != "clean" {
		t.Errorf("outcome = %q, want clean", outcome)
	}
	if got := readFile(t, packPath(dir)); got != oldPackContents {
		t.Errorf("pack = %q, want it untouched", got)
	}
}

func TestRollbackRestoresThePreviousPack(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)
	if err := ApplyStagedPatch(dir, staged, "0.7.0", "0.6.0", sha); err != nil {
		t.Fatalf("apply failed: %v", err)
	}

	// The relaunched client failed its readiness check.
	if err := Rollback(dir); err != nil {
		t.Fatalf("rollback failed: %v", err)
	}
	if got := readFile(t, packPath(dir)); got != oldPackContents {
		t.Errorf("pack = %q, want the previous pack back", got)
	}
}

func TestRollbackWithoutABackupIsRefused(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, packPath(dir), newPackContents)

	if err := Rollback(dir); err == nil {
		t.Fatal("expected rollback to refuse when there is no known-good pack")
	}
}

func TestARepeatedlyFailingVersionStopsRetrying(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if err := ApplyStagedPatch(dir, staged, "0.7.0", "0.6.0", sha); err != nil {
			t.Fatalf("attempt %d failed: %v", attempt, err)
		}
		if err := Rollback(dir); err != nil {
			t.Fatalf("rollback %d failed: %v", attempt, err)
		}
	}

	err := ApplyStagedPatch(dir, staged, "0.7.0", "0.6.0", sha)
	if err != ErrRepairRequired {
		t.Fatalf("err = %v, want ErrRepairRequired after %d attempts", err, maxAttempts)
	}
	if got := readFile(t, packPath(dir)); got != oldPackContents {
		t.Errorf("pack = %q, want the known-good pack left in place", got)
	}
}

func TestADifferentVersionGetsAFreshAttemptBudget(t *testing.T) {
	dir, staged, sha := installWithStagedPatch(t)
	if err := SaveMarker(dir, Marker{
		PendingVersion: "0.7.0", AttemptCount: maxAttempts,
	}); err != nil {
		t.Fatalf("marker: %v", err)
	}

	// A newer release must not inherit the previous version's exhausted budget.
	if err := ApplyStagedPatch(dir, staged, "0.8.0", "0.6.0", sha); err != nil {
		t.Fatalf("apply failed for a new version: %v", err)
	}
	if marker := LoadMarker(dir); marker.AttemptCount != 1 {
		t.Errorf("attempt_count = %d, want 1 for a fresh version", marker.AttemptCount)
	}
}

func TestACorruptMarkerIsTreatedAsAbsent(t *testing.T) {
	dir, _, _ := installWithStagedPatch(t)
	writeFile(t, markerPath(dir), "{ this is not json")

	// A marker that cannot be parsed cannot be trusted to describe the on-disk
	// state, and refusing to start over it would strand the tester with no way
	// back — so it reads as "nothing in flight".
	if marker := LoadMarker(dir); marker.SwapStarted || marker.PendingVersion != "" {
		t.Errorf("corrupt marker = %+v, want a zero marker", marker)
	}
	outcome, err := RecoverInterrupted(dir)
	if err != nil {
		t.Fatalf("recovery failed: %v", err)
	}
	if outcome != "clean" {
		t.Errorf("outcome = %q, want clean", outcome)
	}
}
