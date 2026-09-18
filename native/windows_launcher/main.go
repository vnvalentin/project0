//go:build windows

package main

import (
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

//go:embed payload/**
var payload embed.FS

func main() {
	if hasArg(os.Args[1:], "--project0-update-helper") {
		if err := runUpdaterHelper(os.Args[1:]); err != nil {
			fail(err)
		}
		return
	}

	config, privateKey, err := ensurePeerConfig()
	if err != nil {
		fail(err)
	}
	payloadDirectory, err := payloadDirectory()
	if err != nil {
		fail(err)
	}
	if outcome, recoveryErr := RecoverInterrupted(payloadDirectory); recoveryErr != nil {
		fail(fmt.Errorf("recover interrupted update: %w", recoveryErr))
	} else if outcome == "repair_required" {
		fail(ErrRepairRequired)
	}
	if err := extractPayloadIfMissing(payloadDirectory); err != nil {
		fail(err)
	}

	keyPath, err := privateKeyFile(privateKey)
	if err != nil {
		fail(err)
	}
	defer os.Remove(keyPath)
	command := exec.Command(filepath.Join(payloadDirectory, "Project0.exe"), forwardedArgs(os.Args[1:])...)
	command.Dir = payloadDirectory
	command.Env = append(filteredEnvironment(),
		"PROJECT0_TUNNEL=1",
		"PROJECT0_TUNNEL_SERVER_PUBKEY="+config.ServerPublicKey,
		"PROJECT0_TUNNEL_ENDPOINT="+config.Endpoint,
		"PROJECT0_TUNNEL_GAME_HOST="+strings.TrimSuffix(config.AllowedIPs, "/32")+":9999",
		"PROJECT0_TUNNEL_CLIENT_ADDRESS="+config.AssignedAddress,
		"PROJECT0_TUNNEL_KEY_PATH="+keyPath,
		"PROJECT0_TUNNEL_KEEPALIVE="+fmt.Sprint(config.Keepalive),
	)
	command.Stdout = nil
	command.Stderr = nil
	command.Stdin = nil

	if err := command.Run(); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			os.Exit(exitError.ExitCode())
		}
		fail(err)
	}
}

func hasArg(args []string, wanted string) bool {
	for _, arg := range args {
		if arg == wanted {
			return true
		}
	}
	return false
}

func payloadDirectory() (string, error) {
	root, err := appDataDirectory()
	if err != nil {
		return "", err
	}
	directory := filepath.Join(root, "payload")
	if err := os.MkdirAll(directory, 0700); err != nil {
		return "", fmt.Errorf("create payload directory: %w", err)
	}
	return directory, nil
}

func runUpdaterHelper(args []string) error {
	values := parseUpdaterArgs(args)
	for _, required := range []string{"staged-pack", "pending-version", "previous-version", "expected-sha256", "payload-dir"} {
		if values[required] == "" {
			return fmt.Errorf("updater helper requires --project0-%s", required)
		}
	}
	if err := ApplyStagedPatch(
		values["payload-dir"],
		values["staged-pack"],
		values["pending-version"],
		values["previous-version"],
		values["expected-sha256"],
	); err != nil {
		return err
	}

	client := exec.Command(filepath.Join(values["payload-dir"], "Project0.exe"), "--project0-run-client")
	client.Dir = values["payload-dir"]
	if err := client.Run(); err != nil {
		if rollbackErr := Rollback(values["payload-dir"]); rollbackErr != nil {
			return fmt.Errorf("client readiness failed: %v; rollback failed: %w", err, rollbackErr)
		}
		return fmt.Errorf("client readiness failed; update rolled back: %w", err)
	}
	return nil
}

func parseUpdaterArgs(args []string) map[string]string {
	values := map[string]string{}
	for _, arg := range args {
		if !strings.HasPrefix(arg, "--project0-") {
			continue
		}
		parts := strings.SplitN(strings.TrimPrefix(arg, "--project0-"), "=", 2)
		if len(parts) == 2 {
			values[parts[0]] = parts[1]
		}
	}
	return values
}

func forwardedArgs(args []string) []string {
	forwarded := make([]string, 0, len(args))
	for _, arg := range args {
		if strings.HasPrefix(arg, "--invite-code=") {
			continue
		}
		forwarded = append(forwarded, arg)
	}
	return forwarded
}

func filteredEnvironment() []string {
	filtered := make([]string, 0, len(os.Environ()))
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "PROJECT0_INVITE_CODE=") {
			continue
		}
		filtered = append(filtered, entry)
	}
	return filtered
}

func extractPayload(destination string) error {
	return fs.WalkDir(payload, "payload", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == "payload" {
			return nil
		}
		relativePath := strings.TrimPrefix(path, "payload/")
		target := filepath.Join(destination, filepath.FromSlash(relativePath))
		if entry.IsDir() {
			return os.MkdirAll(target, 0o700)
		}
		contents, err := fs.ReadFile(payload, path)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
			return err
		}
		return os.WriteFile(target, contents, 0o600)
	})
}

func extractPayloadIfMissing(destination string) error {
	return fs.WalkDir(payload, "payload", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == "payload" {
			return nil
		}
		relativePath := strings.TrimPrefix(path, "payload/")
		target := filepath.Join(destination, filepath.FromSlash(relativePath))
		if entry.IsDir() {
			return os.MkdirAll(target, 0700)
		}
		if _, err := os.Stat(target); err == nil {
			return nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		contents, err := fs.ReadFile(payload, path)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			return err
		}
		return os.WriteFile(target, contents, 0600)
	})
}

func fail(err error) {
	message := syscall.StringToUTF16Ptr("Project0 could not start:\n\n" + err.Error())
	title := syscall.StringToUTF16Ptr("Project0")
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBox := user32.NewProc("MessageBoxW")
	messageBox.Call(0, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x10)
	os.Exit(1)
}
