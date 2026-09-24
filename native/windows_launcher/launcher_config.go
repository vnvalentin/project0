//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type launcherMode string

const (
	launcherModeWAN launcherMode = "WAN"
	launcherModeLAN launcherMode = "LAN"
)

const (
	launcherConfigFileName = "launcher-config.json"
	launcherConfigBackup   = "launcher-config.json.bak"
	lanModeArg             = "--project0-lan"
	wanModeArg             = "--project0-wan"
	lanHostArgPrefix       = "--project0-lan-host="
)

type launcherConfig struct {
	Mode    launcherMode `json:"mode"`
	LANHost string       `json:"lan_host,omitempty"`
}

type launchRequest struct {
	Mode launcherMode
	Args []string
	Env  map[string]string
}

func defaultLauncherConfig() launcherConfig {
	return launcherConfig{Mode: launcherModeWAN}
}

func loadLauncherConfig(path string) (launcherConfig, error) {
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		backupPath := path + ".bak"
		raw, err = os.ReadFile(backupPath)
		if errors.Is(err, os.ErrNotExist) {
			return defaultLauncherConfig(), nil
		}
	}
	if err != nil {
		return launcherConfig{}, fmt.Errorf("read launcher config: %w", err)
	}
	var config launcherConfig
	if err := json.Unmarshal(raw, &config); err != nil {
		return launcherConfig{}, fmt.Errorf("parse launcher config: %w", err)
	}
	if err := validateLauncherConfig(config); err != nil {
		return launcherConfig{}, err
	}
	return config, nil
}

func saveLauncherConfig(path string, config launcherConfig) error {
	if err := validateLauncherConfig(config); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create launcher config directory: %w", err)
	}
	raw, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return fmt.Errorf("encode launcher config: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".launcher-config-*")
	if err != nil {
		return fmt.Errorf("create launcher config temporary file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("protect launcher config temporary file: %w", err)
	}
	if _, err := temporary.Write(raw); err != nil {
		temporary.Close()
		return fmt.Errorf("write launcher config: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync launcher config: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close launcher config: %w", err)
	}

	backupPath := path + ".bak"
	_ = os.Remove(backupPath)
	if _, err := os.Stat(path); err == nil {
		if err := os.Rename(path, backupPath); err != nil {
			return fmt.Errorf("stage previous launcher config: %w", err)
		}
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		_ = os.Rename(backupPath, path)
		return fmt.Errorf("publish launcher config: %w", err)
	}
	_ = os.Remove(backupPath)
	return nil
}

func launcherConfigPath() (string, error) {
	root, err := appDataDirectory()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, launcherConfigFileName), nil
}

func applyLauncherModeArgs(config launcherConfig, args []string) (launcherConfig, bool, error) {
	updated := config
	changed := false
	for _, arg := range args {
		switch {
		case arg == lanModeArg:
			updated.Mode = launcherModeLAN
			changed = true
		case arg == wanModeArg:
			updated.Mode = launcherModeWAN
			changed = true
		case strings.HasPrefix(arg, lanHostArgPrefix):
			updated.LANHost = strings.TrimSpace(strings.TrimPrefix(arg, lanHostArgPrefix))
			changed = true
		}
	}
	if err := validateLauncherConfig(updated); err != nil {
		return launcherConfig{}, false, err
	}
	return updated, changed, nil
}

func buildLaunchRequest(config launcherConfig, args []string, environment []string) (launchRequest, error) {
	if err := validateLauncherConfig(config); err != nil {
		return launchRequest{}, err
	}
	request := launchRequest{Mode: config.Mode, Args: append([]string(nil), args...), Env: environmentMap(environment)}
	request.Env["PROJECT0_TUNNEL"] = "1"
	request.Env["PROJECT0_CLIENT_HTTPS_LOGIN"] = "1"
	if config.Mode == launcherModeLAN {
		request.Env["PROJECT0_TUNNEL"] = "0"
		request.Env["PROJECT0_CLIENT_HTTPS_LOGIN"] = "0"
		if !hasServerHostArg(request.Args) {
			request.Args = append(request.Args, "--server-host="+config.LANHost)
		}
	}
	return request, nil
}

func validateLauncherConfig(config launcherConfig) error {
	if config.Mode != launcherModeLAN && config.Mode != launcherModeWAN {
		return fmt.Errorf("unsupported launcher mode %q", config.Mode)
	}
	if config.Mode == launcherModeLAN && strings.TrimSpace(config.LANHost) == "" {
		return errors.New("LAN mode requires a server host")
	}
	return nil
}

func environmentMap(environment []string) map[string]string {
	values := make(map[string]string, len(environment))
	for _, entry := range environment {
		parts := strings.SplitN(entry, "=", 2)
		if len(parts) == 2 {
			values[parts[0]] = parts[1]
		}
	}
	return values
}

func environmentList(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := make([]string, 0, len(keys))
	for _, key := range keys {
		result = append(result, key+"="+values[key])
	}
	return result
}

func hasServerHostArg(args []string) bool {
	for _, arg := range args {
		if strings.HasPrefix(arg, "--server-host=") {
			return true
		}
	}
	return false
}
