//go:build windows

package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func testKey(t *testing.T) (*rsa.PrivateKey, string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return key, string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))
}

func signedManifest(t *testing.T, key *rsa.PrivateKey, pack []byte, url string) ([]byte, []byte) {
	t.Helper()
	digest := sha256.Sum256(pack)
	raw, err := json.Marshal(map[string]any{
		"schema_version":          1,
		"required_client_version": "0.7.0",
		"pck_sha256":              hex.EncodeToString(digest[:]),
		"pck_url":                 url,
		"size_bytes":              len(pack),
	})
	if err != nil {
		t.Fatal(err)
	}
	manifestDigest := sha256.Sum256(raw)
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, manifestDigest[:])
	if err != nil {
		t.Fatal(err)
	}
	return raw, signature
}

func TestDownloadAndStageUpdateVerifiesAndStagesThePack(t *testing.T) {
	key, public := testKey(t)
	pack := []byte("signed pack")
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/manifest.json":
			raw, _ := signedManifest(t, key, pack, "https://placeholder/Project0.pck")
			_, _ = w.Write(raw)
		case "/manifest.sig":
			raw, signature := signedManifest(t, key, pack, "https://placeholder/Project0.pck")
			_ = raw
			_, _ = w.Write(signature)
		case "/Project0.pck":
			_, _ = w.Write(pack)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	// The manifest's signed URL must point at the test server.
	manifest, signature := signedManifest(t, key, pack, server.URL+"/Project0.pck")
	transport := server.Client().Transport
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/manifest.json":
			_, _ = w.Write(manifest)
		case "/manifest.sig":
			_, _ = w.Write(signature)
		case "/Project0.pck":
			_, _ = w.Write(pack)
		default:
			http.NotFound(w, r)
		}
	})
	client := &http.Client{Transport: transport}
	payloadDir := t.TempDir()
	result := downloadAndStageWithKey(client, server.URL, "0.6.0", payloadDir, public)
	if result.Outcome != UpdateOutcomeOK {
		t.Fatalf("outcome=%s detail=%s", result.Outcome, result.Detail)
	}
	if got := readFile(t, result.StagedPath); got != string(pack) {
		t.Fatalf("staged pack=%q", got)
	}
}

func TestDownloadAndStageUpdateRefusesTamperedManifestAndLeavesNoStage(t *testing.T) {
	key, public := testKey(t)
	pack := []byte("signed pack")
	raw, signature := signedManifest(t, key, pack, "https://example/Project0.pck")
	raw[len(raw)-2] ^= 1
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/manifest.json" {
			_, _ = w.Write(raw)
			return
		}
		if r.URL.Path == "/manifest.sig" {
			_, _ = w.Write(signature)
			return
		}
		http.NotFound(w, r)
	}))
	defer server.Close()
	payloadDir := t.TempDir()
	result := downloadAndStageWithKey(server.Client(), server.URL, "0.6.0", payloadDir, public)
	if result.Outcome != UpdateOutcomeUnverified {
		t.Fatalf("outcome=%s detail=%s", result.Outcome, result.Detail)
	}
	if _, err := os.Stat(filepath.Join(payloadDir, stagedPackName)); !os.IsNotExist(err) {
		t.Fatal("tampered manifest left a staged pack")
	}
}

func TestDownloadAndStageUpdateRefusesPlaintextAndUpToDateManifest(t *testing.T) {
	payloadDir := t.TempDir()
	if result := DownloadAndStageUpdate(http.DefaultClient, "http://example/patches", "0.6.0", payloadDir); result.Outcome != UpdateOutcomeInsecureURL {
		t.Fatalf("plaintext outcome=%s", result.Outcome)
	}
	key, public := testKey(t)
	pack := []byte("pack")
	manifest, signature := signedManifest(t, key, pack, "https://unused/Project0.pck")
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/manifest.json" {
			_, _ = w.Write(manifest)
			return
		}
		if r.URL.Path == "/manifest.sig" {
			_, _ = w.Write(signature)
			return
		}
		http.NotFound(w, r)
	}))
	defer server.Close()
	if result := downloadAndStageWithKey(server.Client(), server.URL, "0.7.0", payloadDir, public); result.Outcome != UpdateOutcomeUpToDate {
		t.Fatalf("up-to-date outcome=%s", result.Outcome)
	}
}
