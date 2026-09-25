//go:build windows

package main

// Slice 154 (Phase 16, F-037): the native launcher download boundary. The
// launcher must keep working while Project0.pck is corrupt or being replaced,
// so it cannot call the GDScript verifier inside that pack. This is the same
// contract in Go: verify raw manifest bytes, then parse; verify the signed pack
// size and SHA-256; leave no unverified artifact staged.

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const launcherTrustedPublicKeyPEM = `-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAqy81nl1CCXaKDK4jiMcY
tWww3/qzCOx1L5tfm+Ro+Pw9AhopUHyxOdxbBZCaFI9jolHWC9O8uEEjqdEzk9wS
EiL6JV+R08tO4/vhuE3YTvEk5LOCHeZ9ywCje1JESbzO9ApJqLE8JwnNiKZqg8dm
Rze2CqUr9VMaHR//GOzY6inkpVWclUKMHnOcmp712LK+vQ67pNvnHPVFg60b1sNQ
vCEXN9MxxpoQzFbzyi5a9u0uHN4G7JU6Ru3j6/meC+3irnOFp+VGuiwDSUxpPlNR
8XBxWvRquud71xKJItqSWKYvyPs9DHLmG+koMUIU1QmiOJ5qVYQh0NvJ7V2ZokWG
izShuKDIkoOzvP3AxsdT1ETrrxGF4syHs6mJj/7IYQKYvo2QnDibpWYLmLqpN2/o
eIbff8DT7HE45Juefg1oVYnmluDCIbHkNzb1Gcr4NtETGL566fZIK+roV13MF4Iv
yPYhJcljSJ1uUa7BXH0MBQS4wKjue/2vDL8Nw+K8qqHnAgMBAAE=
-----END PUBLIC KEY-----`

const (
	manifestFileName  = "manifest.json"
	signatureFileName = "manifest.sig"
	stagedPackName    = "Project0.pck.staged"

	UpdateOutcomeOK             = "ok"
	UpdateOutcomeUpToDate       = "up_to_date"
	UpdateOutcomeInsecureURL    = "insecure_url"
	UpdateOutcomeTransportError = "transport_error"
	UpdateOutcomeHTTPError      = "http_error"
	UpdateOutcomeUnverified     = "unverified"
	UpdateOutcomeMalformed      = "malformed"
	UpdateOutcomeHashMismatch   = "hash_mismatch"
	UpdateOutcomeSizeMismatch   = "size_mismatch"
)

type updateManifest struct {
	SchemaVersion         int               `json:"schema_version"`
	RequiredClientVersion string            `json:"required_client_version"`
	PCKSHA256             string            `json:"pck_sha256"`
	PCKURL                string            `json:"pck_url"`
	SizeBytes             int64             `json:"size_bytes"`
	Payloads              []manifestPayload `json:"payloads,omitempty"`
}

type manifestPayload struct {
	Name   string `json:"name"`
	URL    string `json:"url"`
	SHA256 string `json:"sha256"`
}

type UpdateDownloadResult struct {
	Outcome    string
	Detail     string
	Manifest   updateManifest
	StagedPath string
}

func DownloadAndStageUpdate(client *http.Client, baseURL, currentVersion, payloadDir string) UpdateDownloadResult {
	return downloadAndStageWithKey(client, baseURL, currentVersion, payloadDir, launcherTrustedPublicKeyPEM)
}

func downloadAndStageWithKey(client *http.Client, baseURL, currentVersion, payloadDir, publicKeyPEM string) UpdateDownloadResult {
	base := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if !strings.HasPrefix(base, "https://") {
		return updateFailure(UpdateOutcomeInsecureURL, "update base URL must be HTTPS")
	}
	if client == nil {
		client = http.DefaultClient
	}

	manifestRaw, outcome := downloadBytes(client, base+"/"+manifestFileName)
	if outcome.Outcome != UpdateOutcomeOK {
		return outcome
	}
	signature, outcome := downloadBytes(client, base+"/"+signatureFileName)
	if outcome.Outcome != UpdateOutcomeOK {
		return outcome
	}
	manifest, err := verifyManifest(manifestRaw, signature, publicKeyPEM)
	if err != nil {
		return updateFailure(UpdateOutcomeUnverified, err.Error())
	}
	if manifest.RequiredClientVersion == currentVersion {
		return UpdateDownloadResult{Outcome: UpdateOutcomeUpToDate, Manifest: manifest}
	}
	if manifest.PCKURL == "" || !strings.HasPrefix(manifest.PCKURL, "https://") {
		return updateFailure(UpdateOutcomeMalformed, "signed pck_url must be HTTPS")
	}
	if manifest.SizeBytes <= 0 || len(manifest.PCKSHA256) != 64 {
		return updateFailure(UpdateOutcomeMalformed, "signed pack metadata is invalid")
	}

	if err := os.MkdirAll(payloadDir, 0o700); err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("create payload directory: %v", err))
	}
	temporary, err := os.CreateTemp(payloadDir, ".project0-update-*")
	if err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("create staged temp file: %v", err))
	}
	temporaryPath := temporary.Name()
	cleanup := func() { _ = os.Remove(temporaryPath) }
	defer cleanup()

	response, err := client.Get(manifest.PCKURL)
	if err != nil {
		return updateFailure(UpdateOutcomeTransportError, err.Error())
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return updateFailure(UpdateOutcomeHTTPError, fmt.Sprintf("patch HTTP status %d", response.StatusCode))
	}
	written, err := io.Copy(temporary, response.Body)
	if err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("download patch: %v", err))
	}
	if err := temporary.Close(); err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("close patch: %v", err))
	}
	if written != manifest.SizeBytes {
		return updateFailure(UpdateOutcomeSizeMismatch, fmt.Sprintf("patch has %d bytes, signed manifest says %d", written, manifest.SizeBytes))
	}
	actual, err := sha256File(temporaryPath)
	if err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("hash patch: %v", err))
	}
	if actual != strings.ToLower(manifest.PCKSHA256) {
		return updateFailure(UpdateOutcomeHashMismatch, "patch digest does not match signed manifest")
	}

	stagedPath := filepath.Join(payloadDir, stagedPackName)
	_ = os.Remove(stagedPath)
	if err := os.Rename(temporaryPath, stagedPath); err != nil {
		return updateFailure(UpdateOutcomeTransportError, fmt.Sprintf("publish staged patch: %v", err))
	}
	return UpdateDownloadResult{Outcome: UpdateOutcomeOK, Manifest: manifest, StagedPath: stagedPath}
}

func verifyManifest(raw, signature []byte, publicKeyPEM string) (updateManifest, error) {
	block, _ := pem.Decode([]byte(publicKeyPEM))
	if block == nil {
		return updateManifest{}, errors.New("trusted public key is unusable")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return updateManifest{}, err
	}
	key, ok := parsed.(*rsa.PublicKey)
	if !ok {
		return updateManifest{}, errors.New("trusted key is not RSA")
	}
	digest := sha256.Sum256(raw)
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], signature); err != nil {
		return updateManifest{}, errors.New("manifest signature is invalid")
	}
	var manifest updateManifest
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return updateManifest{}, fmt.Errorf("manifest JSON is malformed: %w", err)
	}
	if manifest.SchemaVersion != 1 || manifest.RequiredClientVersion == "" || manifest.PCKURL == "" || manifest.SizeBytes <= 0 {
		return updateManifest{}, errors.New("manifest fields are malformed")
	}
	return manifest, nil
}

func downloadBytes(client *http.Client, url string) ([]byte, UpdateDownloadResult) {
	response, err := client.Get(url)
	if err != nil {
		return nil, updateFailure(UpdateOutcomeTransportError, err.Error())
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, updateFailure(UpdateOutcomeHTTPError, fmt.Sprintf("HTTP status %d", response.StatusCode))
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, updateFailure(UpdateOutcomeTransportError, err.Error())
	}
	return body, UpdateDownloadResult{Outcome: UpdateOutcomeOK}
}

func sha256File(path string) (string, error) {
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

func updateFailure(outcome, detail string) UpdateDownloadResult {
	return UpdateDownloadResult{Outcome: outcome, Detail: detail}
}
