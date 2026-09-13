// Package bridge implements the wgnetstack userspace WireGuard loopback bridge.
package bridge

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config is the untrusted external configuration for one bridge instance.
// It is parsed and validated before any network or key material is touched.
type Config struct {
	ClientPrivateKeyPath        string `json:"client_private_key_path"`
	ClientAddress               string `json:"client_address"`
	MTU                         int    `json:"mtu"`
	ServerPublicKey             string `json:"server_public_key"`
	ServerEndpoint              string `json:"server_endpoint"`
	PersistentKeepaliveInterval int    `json:"persistent_keepalive_interval"`
	GameHost                    string `json:"game_host"`
}

// ParseConfig decodes and bounds-checks a JSON config payload. It never reads
// the private key itself; only the path is validated for presence here.
func ParseConfig(raw []byte) (Config, error) {
	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return Config{}, fmt.Errorf("invalid config json: %w", err)
	}
	if cfg.ClientPrivateKeyPath == "" {
		return Config{}, fmt.Errorf("client_private_key_path is required")
	}
	if cfg.ClientAddress == "" {
		return Config{}, fmt.Errorf("client_address is required")
	}
	if cfg.MTU <= 0 {
		cfg.MTU = 1420
	}
	if cfg.ServerPublicKey == "" {
		return Config{}, fmt.Errorf("server_public_key is required")
	}
	if cfg.ServerEndpoint == "" {
		return Config{}, fmt.Errorf("server_endpoint is required")
	}
	if cfg.GameHost == "" {
		return Config{}, fmt.Errorf("game_host is required")
	}
	if cfg.PersistentKeepaliveInterval <= 0 {
		cfg.PersistentKeepaliveInterval = 25
	}
	return cfg, nil
}

// readPrivateKeyBase64 reads the base64 WireGuard private key from disk at
// the configured path. The key value itself is never logged.
func readPrivateKeyBase64(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("reading private key file: %w", err)
	}
	key := trimKey(string(raw))
	if key == "" {
		return "", fmt.Errorf("private key file is empty")
	}
	return key, nil
}

func trimKey(s string) string {
	start, end := 0, len(s)
	for start < end && (s[start] == ' ' || s[start] == '\n' || s[start] == '\r' || s[start] == '\t') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\n' || s[end-1] == '\r' || s[end-1] == '\t') {
		end--
	}
	return s[start:end]
}
