package main

import (
	"bytes"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestFixtureSigning(t *testing.T) {
	for _, scenario := range []struct {
		name     string
		manifest []byte
		valid    bool
	}{
		{"valid", []byte(`{"required_client_version":"0.13.0"}`), true},
		{"bom", append([]byte{0xef, 0xbb, 0xbf}, []byte(`{"required_client_version":"0.13.0"}`)...), true},
		{"malformed", []byte(`{"required_client_version":`), false},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			directory := t.TempDir()
			manifestPath := filepath.Join(directory, "manifest.json")
			signaturePath := filepath.Join(directory, "manifest.sig")
			publicKeyPath := filepath.Join(directory, "public.pem")
			if err := os.WriteFile(manifestPath, scenario.manifest, 0600); err != nil {
				t.Fatal(err)
			}
			output, err := exec.Command("go", "run", "generate_1100_fixture.go", manifestPath, signaturePath, publicKeyPath).CombinedOutput()
			if !scenario.valid {
				if err == nil {
					t.Fatal("malformed input succeeded")
				}
				entries, readErr := os.ReadDir(directory)
				if readErr != nil || len(entries) != 1 {
					t.Fatalf("malformed input published signing outputs: %v, %v", entries, readErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("signing failed: %v: %s", err, output)
			}
			manifest, err := os.ReadFile(manifestPath)
			if err != nil || !bytes.Equal(manifest, bytes.TrimPrefix(scenario.manifest, []byte{0xef, 0xbb, 0xbf})) {
				t.Fatalf("unexpected manifest bytes: %v", err)
			}
			publicPEM, err := os.ReadFile(publicKeyPath)
			if err != nil {
				t.Fatal(err)
			}
			block, rest := pem.Decode(publicPEM)
			if block == nil || block.Type != "PUBLIC KEY" || len(rest) != 0 {
				t.Fatal("invalid public key PEM")
			}
			publicKey, err := x509.ParsePKIXPublicKey(block.Bytes)
			if err != nil {
				t.Fatal(err)
			}
			rsaKey, ok := publicKey.(*rsa.PublicKey)
			if !ok {
				t.Fatal("public key is not RSA")
			}
			signature, err := os.ReadFile(signaturePath)
			if err != nil {
				t.Fatal(err)
			}
			digest := sha256.Sum256(manifest)
			if err := rsa.VerifyPKCS1v15(rsaKey, crypto.SHA256, digest[:], signature); err != nil {
				t.Fatal(err)
			}
			entries, err := os.ReadDir(directory)
			if err != nil || len(entries) != 3 {
				t.Fatalf("expected only manifest, signature, and public key: %v, %v", entries, err)
			}
		})
	}
}
