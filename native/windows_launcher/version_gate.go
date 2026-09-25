//go:build windows

package main

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const testManifestURL = "https://192.168.1.254:8443/api/v1/client/manifest"

const (
	testManifestURLEnv          = "PROJECT0_TEST_MANIFEST_URL"
	testSigningPublicKeyFileEnv = "PROJECT0_TEST_SIGNING_PUBLIC_KEY_FILE"
)

type payloadHashMismatchError struct {
	Name string
}

func (e *payloadHashMismatchError) Error() string {
	return fmt.Sprintf("PAYLOAD_HASH_MISMATCH: %s", e.Name)
}

func testManifestEndpoint() string {
	if value := strings.TrimSpace(os.Getenv(testManifestURLEnv)); value != "" {
		return value
	}
	return testManifestURL
}

type manifestEnvelope struct {
	Manifest  json.RawMessage `json:"manifest"`
	Signature string          `json:"signature"`
}

func testCACertArg(args []string) (string, bool) {
	for _, arg := range args {
		if strings.HasPrefix(arg, "--test-ca-cert=") {
			return strings.TrimSpace(strings.TrimPrefix(arg, "--test-ca-cert=")), true
		}
	}
	return "", false
}

func runVersionGate(manifestURL, certificatePath, currentVersion string) error {
	client, err := clientWithCA(certificatePath)
	if err != nil {
		return fmt.Errorf("TLS verification failed: %w", err)
	}
	response, err := client.Get(manifestURL)
	if err != nil {
		return fmt.Errorf("TLS verification failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("manifest HTTP status %d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("read manifest: %w", err)
	}
	manifestRaw, signature, err := manifestResponse(body, response.Header)
	if err != nil {
		return err
	}
	publicKeyPEM, err := testSigningPublicKey()
	if err != nil {
		return fmt.Errorf("test signing key: %w", err)
	}
	manifest, err := verifyManifest(manifestRaw, signature, publicKeyPEM)
	if err != nil {
		return fmt.Errorf("manifest signature invalid: %w", err)
	}
	if err := verifyManifestPayloads(client, manifest); err != nil {
		return err
	}
	comparison, err := compareSemVer(manifest.RequiredClientVersion, currentVersion)
	if err != nil {
		return err
	}
	if comparison > 0 {
		return fmt.Errorf("CLIENT_OUTDATED: required %s, local %s", manifest.RequiredClientVersion, currentVersion)
	}
	return nil
}

func verifyManifestPayloads(client *http.Client, manifest updateManifest) error {
	for _, payload := range manifest.Payloads {
		if payload.Name == "" || payload.URL == "" || payload.SHA256 == "" {
			return errors.New("manifest payload metadata is malformed")
		}
		if !strings.HasPrefix(payload.URL, "https://") {
			return errors.New("manifest payload URL must be HTTPS")
		}
		response, err := client.Get(payload.URL)
		if err != nil {
			return fmt.Errorf("download %s: %w", filepath.Base(payload.Name), err)
		}
		body, readErr := io.ReadAll(io.LimitReader(response.Body, 1<<30))
		response.Body.Close()
		if readErr != nil {
			return fmt.Errorf("read %s: %w", filepath.Base(payload.Name), readErr)
		}
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			return fmt.Errorf("payload HTTP status %d for %s", response.StatusCode, filepath.Base(payload.Name))
		}
		digest := sha256.Sum256(body)
		if hex.EncodeToString(digest[:]) != strings.ToLower(payload.SHA256) {
			return &payloadHashMismatchError{Name: filepath.Base(payload.Name)}
		}
	}
	return nil
}

func testSigningPublicKey() (string, error) {
	path := strings.TrimSpace(os.Getenv(testSigningPublicKeyFileEnv))
	if path == "" {
		return launcherTrustedPublicKeyPEM, nil
	}
	key, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(key), nil
}

func clientWithCA(certificatePath string) (*http.Client, error) {
	certificate, err := os.ReadFile(certificatePath)
	if err != nil {
		return nil, err
	}
	pool, err := x509.SystemCertPool()
	if err != nil {
		pool = x509.NewCertPool()
	}
	if !pool.AppendCertsFromPEM(certificate) {
		return nil, errors.New("test CA certificate is not PEM")
	}
	return &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}}, nil
}

func manifestResponse(body []byte, headers http.Header) ([]byte, []byte, error) {
	if encoded := headers.Get("X-Project0-Manifest-Signature"); encoded != "" {
		signature, err := decodeSignature(encoded)
		if err != nil {
			return nil, nil, err
		}
		return body, signature, nil
	}
	var envelope manifestEnvelope
	if err := json.Unmarshal(body, &envelope); err != nil || len(envelope.Manifest) == 0 || envelope.Signature == "" {
		return nil, nil, errors.New("manifest response lacks a detached signature")
	}
	signature, err := decodeSignature(envelope.Signature)
	if err != nil {
		return nil, nil, err
	}
	return envelope.Manifest, signature, nil
}

func decodeSignature(value string) ([]byte, error) {
	value = strings.TrimSpace(value)
	if decoded, err := base64.StdEncoding.DecodeString(value); err == nil {
		return decoded, nil
	}
	decoded, err := hex.DecodeString(value)
	if err != nil {
		return nil, errors.New("manifest signature is not base64 or hex")
	}
	return decoded, nil
}

type semVer struct{ major, minor, patch int }

func compareSemVer(left, right string) (int, error) {
	parsedLeft, err := parseSemVer(left)
	if err != nil {
		return 0, err
	}
	parsedRight, err := parseSemVer(right)
	if err != nil {
		return 0, err
	}
	if parsedLeft.major != parsedRight.major {
		return sign(parsedLeft.major - parsedRight.major), nil
	}
	if parsedLeft.minor != parsedRight.minor {
		return sign(parsedLeft.minor - parsedRight.minor), nil
	}
	return sign(parsedLeft.patch - parsedRight.patch), nil
}

func parseSemVer(value string) (semVer, error) {
	parts := strings.Split(value, ".")
	if len(parts) != 3 {
		return semVer{}, fmt.Errorf("malformed SemVer %q", value)
	}
	values := [3]int{}
	for index, part := range parts {
		parsed, err := strconv.Atoi(part)
		if err != nil || parsed < 0 {
			return semVer{}, fmt.Errorf("malformed SemVer %q", value)
		}
		values[index] = parsed
	}
	return semVer{major: values[0], minor: values[1], patch: values[2]}, nil
}

func sign(value int) int {
	if value < 0 {
		return -1
	}
	if value > 0 {
		return 1
	}
	return 0
}
