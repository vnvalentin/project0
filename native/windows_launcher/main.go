//go:build windows

package main

import (
	"embed"
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
	config, privateKey, err := ensurePeerConfig()
	if err != nil {
		fail(err)
	}
	runDirectory, err := os.MkdirTemp("", "project0-")
	if err != nil {
		fail(err)
	}
	defer os.RemoveAll(runDirectory)

	if err := extractPayload(runDirectory); err != nil {
		fail(err)
	}

	keyPath, err := privateKeyFile(privateKey)
	if err != nil {
		fail(err)
	}
	defer os.Remove(keyPath)
	command := exec.Command(filepath.Join(runDirectory, "Project0.exe"), os.Args[1:]...)
	command.Dir = runDirectory
	command.Env = append(os.Environ(),
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

func fail(err error) {
	message := syscall.StringToUTF16Ptr("Project0 could not start:\n\n" + err.Error())
	title := syscall.StringToUTF16Ptr("Project0")
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBox := user32.NewProc("MessageBoxW")
	messageBox.Call(0, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x10)
	os.Exit(1)
}
