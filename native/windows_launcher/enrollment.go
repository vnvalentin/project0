//go:build windows

package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/crypto/curve25519"
)

type peerConfig struct {
	ServerPublicKey string `json:"server_public_key"`
	Endpoint        string `json:"endpoint"`
	AssignedAddress string `json:"assigned_address"`
	AllowedIPs      string `json:"allowed_ips"`
	Keepalive       int    `json:"persistent_keepalive_seconds"`
}

type redeemRequest struct {
	InviteCode string `json:"invite_code"`
	PublicKey  string `json:"public_key"`
}

func ensurePeerConfig() (peerConfig, []byte, error) {
	root, err := appDataDirectory()
	if err != nil {
		return peerConfig{}, nil, err
	}
	configPath := filepath.Join(root, "peer.json")
	protectedPath := filepath.Join(root, "private-key.dpapi")
	if configBytes, readErr := os.ReadFile(configPath); readErr == nil {
		var config peerConfig
		if json.Unmarshal(configBytes, &config) == nil {
			if protected, keyErr := os.ReadFile(protectedPath); keyErr == nil {
				privateKey, unprotectErr := unprotect(protected)
				if unprotectErr == nil && len(privateKey) == 32 {
					return config, privateKey, nil
				}
			}
		}
	}

	invite := inviteCode()
	if invite == "" {
		return peerConfig{}, nil, errors.New("first run requires PROJECT0_INVITE_CODE or --invite-code=<code>")
	}
	privateKey := make([]byte, 32)
	if _, err := rand.Read(privateKey); err != nil {
		return peerConfig{}, nil, fmt.Errorf("generate client key: %w", err)
	}
	privateKey[0] &= 248
	privateKey[31] &= 127
	privateKey[31] |= 64
	publicKey, err := curve25519.X25519(privateKey, curve25519.Basepoint)
	if err != nil {
		return peerConfig{}, nil, fmt.Errorf("derive client public key: %w", err)
	}
	config, err := redeem(invite, base64.StdEncoding.EncodeToString(publicKey))
	if err != nil {
		return peerConfig{}, nil, err
	}
	if err := config.validate(); err != nil {
		return peerConfig{}, nil, err
	}
	protected, err := protect(privateKey)
	if err != nil {
		return peerConfig{}, nil, fmt.Errorf("protect client key: %w", err)
	}
	configBytes, err := json.Marshal(config)
	if err != nil {
		return peerConfig{}, nil, err
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		return peerConfig{}, nil, err
	}
	if err := writePrivateFile(protectedPath, protected); err != nil {
		return peerConfig{}, nil, err
	}
	if err := writePrivateFile(configPath, configBytes); err != nil {
		_ = os.Remove(protectedPath)
		return peerConfig{}, nil, err
	}
	return config, privateKey, nil
}

func (config peerConfig) validate() error {
	if config.ServerPublicKey == "" || config.Endpoint == "" || config.AssignedAddress == "" || config.AllowedIPs == "" || config.Keepalive < 0 {
		return errors.New("enrollment response is missing required peer configuration")
	}
	return nil
}

func inviteCode() string {
	for _, arg := range os.Args[1:] {
		if strings.HasPrefix(arg, "--invite-code=") {
			return strings.TrimSpace(strings.TrimPrefix(arg, "--invite-code="))
		}
	}
	return strings.TrimSpace(os.Getenv("PROJECT0_INVITE_CODE"))
}

func redeem(invite, publicKey string) (peerConfig, error) {
	url := strings.TrimRight(os.Getenv("PROJECT0_ENROLLMENT_URL"), "/")
	if url == "" {
		url = "https://enroll.valentin.vip/redeem"
	}
	body, err := json.Marshal(redeemRequest{InviteCode: invite, PublicKey: publicKey})
	if err != nil {
		return peerConfig{}, err
	}
	request, err := http.NewRequest(http.MethodPost, url, strings.NewReader(string(body)))
	if err != nil {
		return peerConfig{}, fmt.Errorf("create enrollment request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return peerConfig{}, fmt.Errorf("enrollment request failed: %w", err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return peerConfig{}, fmt.Errorf("enrollment rejected (HTTP %d)", response.StatusCode)
	}
	var config peerConfig
	if err := json.Unmarshal(responseBody, &config); err != nil {
		return peerConfig{}, fmt.Errorf("invalid enrollment response: %w", err)
	}
	if err := config.validate(); err != nil {
		return peerConfig{}, err
	}
	return config, nil
}

func appDataDirectory() (string, error) {
	root := os.Getenv("LOCALAPPDATA")
	if root == "" {
		return "", errors.New("LOCALAPPDATA is not set")
	}
	return filepath.Join(root, "Project0"), nil
}

func writePrivateFile(path string, contents []byte) error {
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, contents, 0600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

type dataBlob struct {
	cbData uint32
	pbData *byte
}

var (
	cryptProtectData   = syscall.NewLazyDLL("crypt32.dll").NewProc("CryptProtectData")
	cryptUnprotectData = syscall.NewLazyDLL("crypt32.dll").NewProc("CryptUnprotectData")
	localFree          = syscall.NewLazyDLL("kernel32.dll").NewProc("LocalFree")
)

func protect(input []byte) ([]byte, error) {
	return crypt(input, cryptProtectData)
}

func unprotect(input []byte) ([]byte, error) {
	return crypt(input, cryptUnprotectData)
}

func crypt(input []byte, procedure *syscall.LazyProc) ([]byte, error) {
	if len(input) == 0 {
		return nil, errors.New("empty credential")
	}
	inputBlob := dataBlob{cbData: uint32(len(input)), pbData: &input[0]}
	var outputBlob dataBlob
	result, _, callErr := procedure.Call(uintptr(unsafe.Pointer(&inputBlob)), 0, 0, 0, 0, 0, uintptr(unsafe.Pointer(&outputBlob)))
	if result == 0 {
		return nil, callErr
	}
	defer localFree.Call(uintptr(unsafe.Pointer(outputBlob.pbData)))
	output := unsafe.Slice(outputBlob.pbData, outputBlob.cbData)
	return append([]byte(nil), output...), nil
}

func privateKeyFile(privateKey []byte) (string, error) {
	name := filepath.Join(os.TempDir(), fmt.Sprintf("project0-key-%x", sha256.Sum256(privateKey)))
	if err := os.WriteFile(name, []byte(base64.StdEncoding.EncodeToString(privateKey)), 0600); err != nil {
		return "", err
	}
	return name, nil
}
