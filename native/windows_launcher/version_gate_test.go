//go:build windows

package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCompareSemVer(t *testing.T) {
	if got, err := compareSemVer("0.13.0", "0.12.0"); err != nil || got <= 0 {
		t.Fatalf("comparison = %d, err=%v", got, err)
	}
	if got, err := compareSemVer("0.12.0", "0.12.0"); err != nil || got != 0 {
		t.Fatalf("comparison = %d, err=%v", got, err)
	}
	if _, err := compareSemVer("0.13.0-beta", "0.12.0"); err == nil {
		t.Fatal("expected prerelease suffix to be rejected")
	}
}

func TestManifestResponseAcceptsDetachedHeader(t *testing.T) {
	key, public := testKey(t)
	manifest, signature := signedManifest(t, key, []byte("payload"), "https://example/Project0.pck")
	header := http.Header{"X-Project0-Manifest-Signature": []string{base64.StdEncoding.EncodeToString(signature)}}
	raw, decoded, err := manifestResponse(manifest, header)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := verifyManifest(raw, decoded, public); err != nil {
		t.Fatal(err)
	}
}

func TestManifestEnvelopeCarriesSignedManifest(t *testing.T) {
	key, public := testKey(t)
	manifest, signature := signedManifest(t, key, []byte("payload"), "https://example/Project0.pck")
	body, err := json.Marshal(manifestEnvelope{Manifest: manifest, Signature: base64.StdEncoding.EncodeToString(signature)})
	if err != nil {
		t.Fatal(err)
	}
	raw, decoded, err := manifestResponse(body, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := verifyManifest(raw, decoded, public); err != nil {
		t.Fatal(err)
	}
}

func TestRunVersionGateRejectsOutdatedClientAfterSignatureVerification(t *testing.T) {
	key, public := testKey(t)
	manifest, signature := signedManifestAtVersion(t, key, []byte("payload"), "https://example/Project0.pck", "0.13.0")
	server := httptest.NewTLSServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("X-Project0-Manifest-Signature", base64.StdEncoding.EncodeToString(signature))
		_, _ = response.Write(manifest)
	}))
	defer server.Close()

	publicKeyFile := t.TempDir() + string(os.PathSeparator) + "test-public.pem"
	if err := os.WriteFile(publicKeyFile, []byte(public), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(testSigningPublicKeyFileEnv, publicKeyFile)
	certificateFile := t.TempDir() + string(os.PathSeparator) + "test-ca.pem"
	certificatePEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw})
	if err := os.WriteFile(certificateFile, certificatePEM, 0600); err != nil {
		t.Fatal(err)
	}

	err := runVersionGate(server.URL, certificateFile, "0.12.0")
	if err == nil || err.Error() != "CLIENT_OUTDATED: required 0.13.0, local 0.12.0" {
		t.Fatalf("runVersionGate error = %v", err)
	}
}

func TestRunVersionGateRejectsEachMismatchedPayload(t *testing.T) {
	tests := []struct {
		name   string
		target string
	}{
		{name: "exe", target: "Project0.exe"},
		{name: "pck", target: "Project0.pck"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			key, public := testKey(t)
			validPayload := []byte("valid " + test.target)
			corruptPayload := []byte("corrupt " + test.target)
			var manifest []byte
			var signature []byte
			server := httptest.NewTLSServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
				if request.URL.Path == "/manifest" {
					response.Header().Set("X-Project0-Manifest-Signature", base64.StdEncoding.EncodeToString(signature))
				}
				switch request.URL.Path {
				case "/manifest":
					_, _ = response.Write(manifest)
				case "/Project0.exe":
					_, _ = response.Write(payloadForTarget(test.target, validPayload, corruptPayload, "Project0.exe"))
				case "/Project0.pck":
					_, _ = response.Write(payloadForTarget(test.target, validPayload, corruptPayload, "Project0.pck"))
				default:
					http.NotFound(response, request)
				}
			}))
			defer server.Close()

			manifest, signature = signedPayloadManifest(t, key, server.URL, validPayload)
			certificateFile := filepath.Join(t.TempDir(), "test-ca.pem")
			certificatePEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw})
			if err := os.WriteFile(certificateFile, certificatePEM, 0600); err != nil {
				t.Fatal(err)
			}
			publicKeyFile := filepath.Join(t.TempDir(), "test-public.pem")
			if err := os.WriteFile(publicKeyFile, []byte(public), 0600); err != nil {
				t.Fatal(err)
			}
			t.Setenv(testSigningPublicKeyFileEnv, publicKeyFile)

			err := runVersionGate(server.URL+"/manifest", certificateFile, launcherClientVersion)
			if err == nil || err.Error() != "PAYLOAD_HASH_MISMATCH: "+test.target {
				t.Fatalf("runVersionGate error = %v", err)
			}
		})
	}
}

func TestPackagedLauncherRejectsOutdatedClientBeforeSideEffects(t *testing.T) {
	key, public := testKey(t)
	manifest, signature := signedManifestAtVersion(t, key, []byte("payload"), "https://example/Project0.pck", "0.14.0")
	server := httptest.NewTLSServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("X-Project0-Manifest-Signature", base64.StdEncoding.EncodeToString(signature))
		_, _ = response.Write(manifest)
	}))
	defer server.Close()

	root := t.TempDir()
	publicKeyFile := root + string(os.PathSeparator) + "test-public.pem"
	if err := os.WriteFile(publicKeyFile, []byte(public), 0600); err != nil {
		t.Fatal(err)
	}
	certificateFile := root + string(os.PathSeparator) + "test-ca.pem"
	certificatePEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw})
	if err := os.WriteFile(certificateFile, certificatePEM, 0600); err != nil {
		t.Fatal(err)
	}
	for _, currentVersion := range []string{"0.12.0", "0.13.0"} {
		t.Run(currentVersion, func(t *testing.T) {
			launcherPath := filepath.Join(t.TempDir(), "Project0-Launcher.exe")
			arguments := []string{"build", "-o", launcherPath}
			if currentVersion != "0.12.0" {
				arguments = append(arguments, "-ldflags", "-H=windowsgui -X main.launcherClientVersion="+currentVersion)
			}
			build := exec.Command("go", append(arguments, ".")...)
			if output, err := build.CombinedOutput(); err != nil {
				t.Fatalf("build launcher: %v\n%s", err, output)
			}

			localAppData := root + string(os.PathSeparator) + "localappdata"
			command := exec.Command(launcherPath, "--test-ca-cert="+certificateFile)
			command.Env = testEnvironment(os.Environ(), map[string]string{
				"LOCALAPPDATA":              localAppData,
				testManifestURLEnv:          server.URL,
				testSigningPublicKeyFileEnv: publicKeyFile,
			})
			output, err := command.CombinedOutput()
			if err == nil {
				t.Fatal("expected launcher to reject the outdated client")
			}
			exitError, ok := err.(*exec.ExitError)
			if !ok || exitError.ExitCode() != updateRequiredExitCode {
				t.Fatalf("launcher error = %v, output = %s", err, output)
			}
			if strings.TrimSpace(string(output)) != "CLIENT_OUTDATED: required 0.14.0, local "+currentVersion {
				t.Fatalf("launcher output = %q", output)
			}
			if _, err := os.Stat(localAppData); !os.IsNotExist(err) {
				t.Fatalf("launcher created side effects under LOCALAPPDATA: %v", err)
			}
		})
	}
}

func TestPackagedLauncherRejectsEachMismatchedPayloadBeforeSideEffects(t *testing.T) {
	for _, target := range []string{"Project0.exe", "Project0.pck"} {
		t.Run(target, func(t *testing.T) {
			key, public := testKey(t)
			validPayload := []byte("valid " + target)
			corruptPayload := []byte("corrupt " + target)
			var manifest []byte
			var signature []byte
			server := httptest.NewTLSServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
				if request.URL.Path == "/manifest" {
					response.Header().Set("X-Project0-Manifest-Signature", base64.StdEncoding.EncodeToString(signature))
				}
				switch request.URL.Path {
				case "/manifest":
					_, _ = response.Write(manifest)
				case "/Project0.exe":
					_, _ = response.Write(payloadForTarget(target, validPayload, corruptPayload, "Project0.exe"))
				case "/Project0.pck":
					_, _ = response.Write(payloadForTarget(target, validPayload, corruptPayload, "Project0.pck"))
				default:
					http.NotFound(response, request)
				}
			}))
			defer server.Close()

			manifest, signature = signedPayloadManifest(t, key, server.URL, validPayload)
			root := t.TempDir()
			publicKeyFile := filepath.Join(root, "test-public.pem")
			if err := os.WriteFile(publicKeyFile, []byte(public), 0600); err != nil {
				t.Fatal(err)
			}
			certificateFile := filepath.Join(root, "test-ca.pem")
			certificatePEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw})
			if err := os.WriteFile(certificateFile, certificatePEM, 0600); err != nil {
				t.Fatal(err)
			}
			launcherPath := filepath.Join(root, "Project0-Launcher.exe")
			build := exec.Command("go", "build", "-o", launcherPath, ".")
			if output, err := build.CombinedOutput(); err != nil {
				t.Fatalf("build launcher: %v\n%s", err, output)
			}

			localAppData := filepath.Join(root, "localappdata")
			activeDirectory := filepath.Join(localAppData, "Project0", "active")
			activeManifest := filepath.Join(localAppData, "Project0", "version-manifest.json")
			command := exec.Command(launcherPath, "--test-ca-cert="+certificateFile)
			command.Env = testEnvironment(os.Environ(), map[string]string{
				"LOCALAPPDATA":              localAppData,
				testManifestURLEnv:          server.URL + "/manifest",
				testSigningPublicKeyFileEnv: publicKeyFile,
			})
			output, err := command.CombinedOutput()
			if err == nil {
				t.Fatal("expected launcher to reject the mismatched payload")
			}
			exitError, ok := err.(*exec.ExitError)
			if !ok || exitError.ExitCode() != 3 {
				t.Fatalf("launcher error = %v, output = %s", err, output)
			}
			if strings.TrimSpace(string(output)) != "PAYLOAD_HASH_MISMATCH: "+target {
				t.Fatalf("launcher output = %q", output)
			}
			for _, path := range []string{localAppData, activeDirectory, activeManifest} {
				if _, err := os.Stat(path); !os.IsNotExist(err) {
					t.Fatalf("launcher changed pre-launch path %s: %v", path, err)
				}
			}
			writePayloadMismatchEvidence(t, target, validPayload, corruptPayload, activeDirectory, activeManifest)
		})
	}
}

func writePayloadMismatchEvidence(t *testing.T, target string, validPayload, corruptPayload []byte, activeDirectory, activeManifest string) {
	t.Helper()
	evidenceDirectory := os.Getenv("PROJECT0_EXPERIMENT_EVIDENCE_DIR")
	if evidenceDirectory == "" {
		return
	}
	declared := sha256.Sum256(validPayload)
	computed := sha256.Sum256(corruptPayload)
	timestamp := time.Now().UTC()
	evidence := map[string]any{
		"experiment_id":      "exp_1099_hash_mismatch",
		"timestamp_ms":       timestamp.UnixMilli(),
		"launcher_exit_code": 3,
		"failure_reason":     "PAYLOAD_HASH_MISMATCH",
		"tls_verification":   map[string]any{"status": "VERIFIED", "custom_ca_used": true},
		"manifest_signature": map[string]any{"status": "VALID", "public_key_matched": true},
		"rejected_payload_identity": map[string]any{
			"target_binary":   target,
			"declared_sha256": hex.EncodeToString(declared[:]),
			"computed_sha256": hex.EncodeToString(computed[:]),
		},
		"disk_integrity_audit": map[string]any{
			"staging_bytes_written":    0,
			"staging_path":             filepath.Join(filepath.Dir(activeDirectory), "staging"),
			"active_dir_modified":      false,
			"active_manifest_modified": false,
			"active_dir": map[string]any{
				"path":          activeDirectory,
				"before_exists": false,
				"after_exists":  false,
				"unchanged":     true,
			},
			"active_manifest": map[string]any{
				"path":          activeManifest,
				"before_exists": false,
				"after_exists":  false,
				"unchanged":     true,
			},
		},
		"process_audit": map[string]any{"project0_exe_spawn_count": 0},
	}
	if err := os.MkdirAll(evidenceDirectory, 0755); err != nil {
		t.Fatal(err)
	}
	content, err := json.MarshalIndent(evidence, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	filename := filepath.Join(evidenceDirectory, "exp_1099_hash_mismatch_"+timestamp.Format("20060102T150405.000Z")+"_"+strings.TrimSuffix(target, ".exe")+".json")
	if err := os.WriteFile(filename, append(content, '\n'), 0600); err != nil {
		t.Fatal(err)
	}
}

func testEnvironment(base []string, overrides map[string]string) []string {
	result := make([]string, 0, len(base)+len(overrides))
	for _, entry := range base {
		name := entry
		if separator := strings.IndexByte(entry, '='); separator >= 0 {
			name = entry[:separator]
		}
		if _, overridden := overrides[name]; !overridden {
			result = append(result, entry)
		}
	}
	for name, value := range overrides {
		result = append(result, name+"="+value)
	}
	return result
}

func payloadForTarget(target string, valid, corrupt []byte, current string) []byte {
	if target == current {
		return corrupt
	}
	return valid
}

func signedManifestAtVersion(t *testing.T, key *rsa.PrivateKey, pack []byte, url, version string) ([]byte, []byte) {
	t.Helper()
	raw, _ := signedManifest(t, key, pack, url)
	var value map[string]any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatal(err)
	}
	value["required_client_version"] = version
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(raw)
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return raw, signature
}

func signedPayloadManifest(t *testing.T, key *rsa.PrivateKey, baseURL string, valid []byte) ([]byte, []byte) {
	t.Helper()
	digest := sha256.Sum256(valid)
	value := map[string]any{
		"schema_version":          1,
		"required_client_version": launcherClientVersion,
		"pck_sha256":              hex.EncodeToString(digest[:]),
		"pck_url":                 baseURL + "/Project0.pck",
		"size_bytes":              len(valid),
		"payloads": []map[string]string{
			{"name": "Project0.exe", "url": baseURL + "/Project0.exe", "sha256": hex.EncodeToString(digest[:])},
			{"name": "Project0.pck", "url": baseURL + "/Project0.pck", "sha256": hex.EncodeToString(digest[:])},
		},
	}
	raw, err := json.Marshal(value)
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
