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
	"os/exec"
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
	ClientPublicKey string `json:"client_public_key,omitempty"`
}

// redeemRequest carries EITHER a one-time invite_code (operator/fallback path)
// OR a signed account assertion (self-service login path). The enrollment
// service requires exactly one, so both fields are omitempty: the unused one is
// omitted from the JSON body rather than sent as an empty string.
type redeemRequest struct {
	InviteCode string `json:"invite_code,omitempty"`
	Assertion  string `json:"assertion,omitempty"`
	PublicKey  string `json:"public_key"`
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginResponse struct {
	Assertion string `json:"assertion"`
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
		if json.Unmarshal(configBytes, &config) == nil && config.validate() == nil {
			if protected, keyErr := os.ReadFile(protectedPath); keyErr == nil {
				privateKey, unprotectErr := unprotect(protected)
				if unprotectErr == nil && len(privateKey) == 32 && config.matchesPrivateKey(privateKey) {
					return config, privateKey, nil
				}
			}
		}
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
	publicKeyB64 := base64.StdEncoding.EncodeToString(publicKey)
	config, err := provisionPeer(publicKeyB64)
	if err != nil {
		return peerConfig{}, nil, err
	}
	config.ClientPublicKey = publicKeyB64
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

func (config peerConfig) matchesPrivateKey(privateKey []byte) bool {
	if len(privateKey) != 32 || config.ClientPublicKey == "" {
		return false
	}
	publicKey, err := curve25519.X25519(privateKey, curve25519.Basepoint)
	return err == nil && config.ClientPublicKey == base64.StdEncoding.EncodeToString(publicKey)
}

// provisionPeer obtains a fresh WireGuard peer for this device. It prefers the
// self-service login path (username/password -> signed account assertion ->
// redeem), and falls back to an explicit one-time invite code when one is
// supplied via --invite-code=<code> or PROJECT0_INVITE_CODE. This removes the
// prior hard requirement to obtain an invite from a third device (ADR 0004).
func provisionPeer(publicKey string) (peerConfig, error) {
	if invite := explicitInvite(); invite != "" {
		return redeem(invite, publicKey)
	}
	username, password := credentialPrompter()
	username = strings.TrimSpace(username)
	if username == "" || password == "" {
		return peerConfig{}, errors.New("first run requires a Project0 login (username and password), or --invite-code=<code>")
	}
	assertion, err := login(username, password)
	if err != nil {
		return peerConfig{}, err
	}
	return redeemWithAssertion(assertion, publicKey)
}

// explicitInvite returns a one-time invite code only when the operator supplied
// one explicitly (argument or environment). Unlike the removed inviteCode(), it
// never falls through to an interactive prompt: absence of an invite means the
// self-service login path is used instead.
func explicitInvite() string {
	for _, arg := range os.Args[1:] {
		if strings.HasPrefix(arg, "--invite-code=") {
			return strings.TrimSpace(strings.TrimPrefix(arg, "--invite-code="))
		}
	}
	return strings.TrimSpace(os.Getenv("PROJECT0_INVITE_CODE"))
}

// credentialPrompter is the interactive username/password prompt, a package
// variable so tests substitute a non-interactive stub instead of blocking on
// the real Windows credential dialog.
var credentialPrompter = promptForCredentials

func promptForCredentials() (string, string) {
	command := "$ErrorActionPreference='Stop'; " +
		"$c = Get-Credential -Message 'Sign in to Project0'; " +
		"if ($c) { $c.UserName; $c.GetNetworkCredential().Password }"
	output, err := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-Command",
		command,
	).Output()
	if err != nil {
		return "", ""
	}
	normalized := strings.TrimRight(strings.ReplaceAll(string(output), "\r\n", "\n"), "\n")
	lines := strings.SplitN(normalized, "\n", 2)
	if len(lines) < 2 {
		return "", ""
	}
	return strings.TrimSpace(lines[0]), lines[1]
}

// login exchanges a username/password for a short-lived signed account
// assertion at the public enrollment service's POST /login.
func login(username, password string) (string, error) {
	responseBody, err := postEnrollment("/login", loginRequest{Username: username, Password: password})
	if err != nil {
		return "", err
	}
	var parsed loginResponse
	if err := json.Unmarshal(responseBody, &parsed); err != nil {
		return "", fmt.Errorf("invalid login response: %w", err)
	}
	if parsed.Assertion == "" {
		return "", errors.New("login response did not include an assertion")
	}
	return parsed.Assertion, nil
}

func redeem(invite, publicKey string) (peerConfig, error) {
	return decodePeerConfig(postEnrollment("/redeem", redeemRequest{InviteCode: invite, PublicKey: publicKey}))
}

func redeemWithAssertion(assertion, publicKey string) (peerConfig, error) {
	return decodePeerConfig(postEnrollment("/redeem", redeemRequest{Assertion: assertion, PublicKey: publicKey}))
}

func decodePeerConfig(responseBody []byte, err error) (peerConfig, error) {
	if err != nil {
		return peerConfig{}, err
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

// enrollmentBaseURL resolves the public enrollment service base URL from
// PROJECT0_ENROLLMENT_URL (default https://project0.valentin.vip), tolerating a
// value that already includes a trailing "/redeem" or slash so both /login and
// /redeem resolve correctly.
func enrollmentBaseURL() string {
	raw := strings.TrimRight(strings.TrimSpace(os.Getenv("PROJECT0_ENROLLMENT_URL")), "/")
	if raw == "" {
		return "https://project0.valentin.vip"
	}
	raw = strings.TrimSuffix(raw, "/redeem")
	return strings.TrimRight(raw, "/")
}

func postEnrollment(path string, payload any) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequest(http.MethodPost, enrollmentBaseURL()+path, strings.NewReader(string(body)))
	if err != nil {
		return nil, fmt.Errorf("create enrollment request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("enrollment request failed: %w", err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("enrollment rejected (HTTP %d)", response.StatusCode)
	}
	return responseBody, nil
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
