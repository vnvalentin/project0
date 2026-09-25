//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func runVerifiedAdmission(manifestURL, certificatePath, currentVersion string, args []string) (resultErr error) {
	manifest, raw, payloads, err := verifiedGateInputs(manifestURL, certificatePath, currentVersion)
	if err != nil {
		return err
	}
	var identity struct {
		BuildID string `json:"build_id"`
	}
	if err := json.Unmarshal(raw, &identity); err != nil {
		return err
	}
	if strings.TrimSpace(identity.BuildID) == "" || len(identity.BuildID) > 128 || len(payloads) != 2 {
		return errors.New("verified install requires build_id and both payloads")
	}
	if int64(len(payloads["Project0.pck"])) != manifest.SizeBytes {
		return errors.New("signed pack size does not match payload")
	}
	for _, payload := range manifest.Payloads {
		if payload.Name == "Project0.pck" && (!strings.EqualFold(payload.SHA256, manifest.PCKSHA256) || payload.URL != manifest.PCKURL) {
			return errors.New("signed pack metadata is inconsistent")
		}
	}
	root, err := appDataDirectory()
	if err != nil {
		return err
	}
	if !filepath.IsAbs(root) {
		return errors.New("verified install requires absolute LOCALAPPDATA")
	}
	if err := os.MkdirAll(filepath.Dir(root), 0700); err != nil {
		return err
	}
	if err := os.Mkdir(root, 0700); err != nil {
		return fmt.Errorf("verified fresh install requires absent Project0 root: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			if cleanupErr := os.RemoveAll(root); cleanupErr != nil {
				resultErr = errors.Join(resultErr, fmt.Errorf("verified install cleanup: %w", cleanupErr))
			}
		}
	}()
	staging := filepath.Join(root, "staging")
	if err := os.Mkdir(staging, 0700); err != nil {
		return err
	}
	for _, name := range []string{"Project0.exe", "Project0.pck"} {
		if err := writeSyncedFile(filepath.Join(staging, name), payloads[name]); err != nil {
			return err
		}
	}
	if err := writeSyncedFile(filepath.Join(staging, "version-manifest.json"), raw); err != nil {
		return err
	}
	active := filepath.Join(root, "active")
	if err := os.Rename(staging, active); err != nil {
		return err
	}
	pendingManifest := filepath.Join(root, ".version-manifest.pending")
	if err := writeSyncedFile(pendingManifest, raw); err != nil {
		return err
	}
	if err := os.Rename(pendingManifest, filepath.Join(root, "version-manifest.json")); err != nil {
		return err
	}
	if err := emitAdmissionEvent(map[string]any{"event": "manifest_persisted", "semver": manifest.RequiredClientVersion, "build_id": identity.BuildID, "content_hash": manifest.PCKSHA256}); err != nil {
		return err
	}
	request, err := buildLaunchRequest(defaultLauncherConfig(), args, os.Environ())
	if err != nil {
		return err
	}
	command := exec.Command(filepath.Join(active, "Project0.exe"), request.Args...)
	command.Dir = active
	command.Env = environmentList(request.Env)
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	if err := command.Start(); err != nil {
		return fmt.Errorf("verified engine start: %w", err)
	}
	committed = true
	eventErr := emitAdmissionEvent(map[string]any{"event": "engine_started", "pid": command.Process.Pid, "path": command.Path})
	return errors.Join(eventErr, command.Wait())
}

func emitAdmissionEvent(event map[string]any) error {
	raw, err := json.Marshal(event)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(os.Stdout, "PROJECT0_ADMISSION "+string(raw))
	return err
}

func writeSyncedFile(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	return file.Close()
}
