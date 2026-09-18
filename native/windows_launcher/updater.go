package main

// Slice 149 (Phase 16, F-037): the update transaction — the part that actually
// replaces the client's pack, and the part that has to survive being killed
// halfway through.
//
// This lives in the launcher, not in the game, for one reason: the updater must
// not depend on the artifact it is replacing. A Godot-hosted updater would ship
// inside Project0.pck and could be broken by the very patch it is applying (or
// by the half-written pack left behind by a previous crash). The launcher is a
// separate binary, so it still runs when the pack is missing or corrupt.
//
// Ordering is chosen so that every interruption point is recoverable:
//
//	copy staged -> <dir>/Project0.pck.incoming   (same volume, so the later
//	                                              rename is atomic)
//	verify the incoming copy's digest
//	marker.swap_started = true                   (crash after here is detectable)
//	rename Project0.pck      -> Project0.pck.bak
//	rename Project0.pck.incoming -> Project0.pck
//	marker cleared                               (transaction complete)
//
// The staged file is copied rather than renamed because staging lives under the
// user profile and the install directory may be a different volume, where
// os.Rename is not atomic (and can fail outright).
//
// See .scratch/client-auto-update/spec.md and
// docs/adr/0008-windows-client-delivery-trust-and-rollback.md.

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const (
	packName     = "Project0.pck"
	backupName   = "Project0.pck.bak"
	incomingName = "Project0.pck.incoming"
	markerName   = "update-transaction.json"

	// One automatic attempt plus one retry. A version that fails twice stops
	// trying: repeatedly re-applying a patch that bricks the client is worse
	// than sitting on the last known-good build and asking for help.
	maxAttempts = 2
)

// ErrRepairRequired means this version has exhausted its attempts and must not
// be applied again automatically.
var ErrRepairRequired = errors.New("update attempts exhausted; repair required")

// Marker is the on-disk transaction record. It is the only thing that tells a
// freshly started launcher whether a previous run died mid-swap.
type Marker struct {
	PendingVersion  string `json:"pending_version"`
	PreviousVersion string `json:"previous_version"`
	StagedSHA256    string `json:"staged_sha256"`
	SwapStarted     bool   `json:"swap_started"`
	AttemptCount    int    `json:"attempt_count"`
}

func packPath(dir string) string     { return filepath.Join(dir, packName) }
func backupPath(dir string) string   { return filepath.Join(dir, backupName) }
func incomingPath(dir string) string { return filepath.Join(dir, incomingName) }
func markerPath(dir string) string   { return filepath.Join(dir, markerName) }

// LoadMarker returns the stored transaction, or a zero Marker when none exists.
// A corrupt marker is treated as absent: it cannot be trusted to describe the
// on-disk state, and refusing to start the launcher over it would strand the
// tester with no way back.
func LoadMarker(dir string) Marker {
	raw, err := os.ReadFile(markerPath(dir))
	if err != nil {
		return Marker{}
	}
	var m Marker
	if err := json.Unmarshal(raw, &m); err != nil {
		return Marker{}
	}
	return m
}

func SaveMarker(dir string, m Marker) error {
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return writeFileSynced(markerPath(dir), raw)
}

func ClearMarker(dir string) error {
	err := os.Remove(markerPath(dir))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

// SHA256File returns the lowercase hex digest of a file, streamed so a large
// pack is never held in memory.
func SHA256File(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

// NeedsRepair reports whether this version has already burned its attempts.
func NeedsRepair(m Marker, version string) bool {
	return m.PendingVersion == version && m.AttemptCount >= maxAttempts
}

// ApplyStagedPatch installs a verified staged pack, leaving exactly one
// known-good backup behind. The digest is re-checked here even though the client
// already verified it: this process is the last thing standing between those
// bytes and becoming the running client, and it must not trust a handoff it
// cannot re-prove.
func ApplyStagedPatch(dir, stagedPath, pendingVersion, previousVersion, expectedSHA256 string) error {
	marker := LoadMarker(dir)
	if NeedsRepair(marker, pendingVersion) {
		return ErrRepairRequired
	}

	if err := copyFile(stagedPath, incomingPath(dir)); err != nil {
		_ = os.Remove(incomingPath(dir))
		return fmt.Errorf("staging copy failed: %w", err)
	}
	actual, err := SHA256File(incomingPath(dir))
	if err != nil {
		_ = os.Remove(incomingPath(dir))
		return fmt.Errorf("incoming digest unreadable: %w", err)
	}
	if actual != expectedSHA256 {
		_ = os.Remove(incomingPath(dir))
		return fmt.Errorf("incoming pack digest %s does not match expected %s", actual, expectedSHA256)
	}

	attempt := marker.AttemptCount
	if marker.PendingVersion == pendingVersion {
		attempt++
	} else {
		attempt = 1
	}
	inFlight := Marker{
		PendingVersion:  pendingVersion,
		PreviousVersion: previousVersion,
		StagedSHA256:    expectedSHA256,
		SwapStarted:     true,
		AttemptCount:    attempt,
	}
	if err := SaveMarker(dir, inFlight); err != nil {
		_ = os.Remove(incomingPath(dir))
		return fmt.Errorf("could not record the transaction: %w", err)
	}

	// From here on a crash is recoverable via RecoverInterrupted.
	if err := os.Remove(backupPath(dir)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("could not clear the previous backup: %w", err)
	}
	if err := os.Rename(packPath(dir), backupPath(dir)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("could not back up the current pack: %w", err)
	}
	if err := os.Rename(incomingPath(dir), packPath(dir)); err != nil {
		return fmt.Errorf("could not install the new pack: %w", err)
	}

	inFlight.SwapStarted = false
	return SaveMarker(dir, inFlight)
}

// RecoverInterrupted inspects the marker on startup and puts the install back
// into a known state. Returns a short machine-readable outcome:
//
//	"clean"      nothing was in flight
//	"completed"  the swap had finished; the transaction is simply closed out
//	"rolled_back" the known-good pack was restored
//	"repair_required" no usable pack and no backup to restore
func RecoverInterrupted(dir string) (string, error) {
	marker := LoadMarker(dir)
	if !marker.SwapStarted {
		return "clean", nil
	}

	// The swap may in fact have completed just before the crash. Prefer keeping a
	// good new pack over blindly undoing a successful update.
	if actual, err := SHA256File(packPath(dir)); err == nil && actual == marker.StagedSHA256 {
		marker.SwapStarted = false
		if err := SaveMarker(dir, marker); err != nil {
			return "", err
		}
		return "completed", nil
	}

	if _, err := os.Stat(backupPath(dir)); err == nil {
		_ = os.Remove(packPath(dir))
		if err := os.Rename(backupPath(dir), packPath(dir)); err != nil {
			return "", fmt.Errorf("rollback failed: %w", err)
		}
		_ = os.Remove(incomingPath(dir))
		marker.SwapStarted = false
		if err := SaveMarker(dir, marker); err != nil {
			return "", err
		}
		return "rolled_back", nil
	}

	return "repair_required", nil
}

// Rollback restores the retained known-good pack, used when the relaunched
// client fails its post-patch readiness check.
func Rollback(dir string) error {
	if _, err := os.Stat(backupPath(dir)); err != nil {
		return fmt.Errorf("no known-good pack to restore: %w", err)
	}
	_ = os.Remove(packPath(dir))
	if err := os.Rename(backupPath(dir), packPath(dir)); err != nil {
		return fmt.Errorf("rollback failed: %w", err)
	}
	marker := LoadMarker(dir)
	marker.SwapStarted = false
	return SaveMarker(dir, marker)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	// Flush to disk before the rename, so a power loss cannot leave a renamed
	// but empty pack in place.
	if err := out.Sync(); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func writeFileSynced(path string, data []byte) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}
