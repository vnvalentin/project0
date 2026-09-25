//go:build windows

package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"testing"
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

func TestPackagedLauncherRejectsOutdatedClientBeforeSideEffects(t *testing.T) {
	key, public := testKey(t)
	manifest, signature := signedManifestAtVersion(t, key, []byte("payload"), "https://example/Project0.pck", "0.13.0")
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
	launcherPath := root + string(os.PathSeparator) + "Project0-Launcher.exe"
	build := exec.Command("go", "build", "-o", launcherPath, ".")
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
	if strings.TrimSpace(string(output)) != "CLIENT_OUTDATED: required 0.13.0, local 0.12.0" {
		t.Fatalf("launcher output = %q", output)
	}
	if _, err := os.Stat(localAppData); !os.IsNotExist(err) {
		t.Fatalf("launcher created side effects under LOCALAPPDATA: %v", err)
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
