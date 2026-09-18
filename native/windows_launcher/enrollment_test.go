//go:build windows

package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"golang.org/x/crypto/curve25519"
)

func TestDPAPIProtectRoundTrip(t *testing.T) {
	input := []byte("test-only-private-key-material")
	protected, err := protect(input)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(input, protected) {
		t.Fatal("protected data must not equal plaintext")
	}
	unprotected, err := unprotect(protected)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(input, unprotected) {
		t.Fatalf("round trip mismatch: got %q", unprotected)
	}
}

func TestKeyDerivationProducesWireGuardPublicKey(t *testing.T) {
	privateKey := make([]byte, 32)
	for index := range privateKey {
		privateKey[index] = byte(index + 1)
	}
	privateKey[0] &= 248
	privateKey[31] &= 127
	privateKey[31] |= 64
	publicKey, err := curve25519.X25519(privateKey, curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	encoded := base64.StdEncoding.EncodeToString(publicKey)
	if len(encoded) != 44 || encoded[43] != '=' {
		t.Fatalf("invalid WireGuard public-key shape: %q", encoded)
	}
}

func TestProvisioningFailsClosedWithoutInviteOrCredentials(t *testing.T) {
	t.Setenv("PROJECT0_INVITE_CODE", "")
	originalArgs := os.Args
	os.Args = []string{"launcher.exe"}
	defer func() { os.Args = originalArgs }()
	// Stub the interactive credential prompt so the test never blocks on the
	// real Windows credential dialog; empty credentials must fail closed.
	original := credentialPrompter
	credentialPrompter = func() (string, string) { return "", "" }
	defer func() { credentialPrompter = original }()
	if _, err := provisionPeer(strings.Repeat("A", 43) + "="); err == nil {
		t.Fatal("expected provisioning to fail closed without invite or credentials")
	}
}

func TestLoginSendsCredentialsAndReturnsAssertion(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/login" {
			t.Errorf("login posted to unexpected path: %q", request.URL.Path)
		}
		var body loginRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Errorf("decode login request: %v", err)
			return
		}
		if body.Username != "vic" || body.Password != "s3cret" {
			t.Errorf("unexpected login request: %+v", body)
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(loginResponse{Assertion: "account.assertion.jwt"})
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	assertion, err := login("vic", "s3cret")
	if err != nil {
		t.Fatal(err)
	}
	if assertion != "account.assertion.jwt" {
		t.Fatalf("unexpected assertion: %q", assertion)
	}
}

func TestLoginRejectionFailsClosed(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusUnauthorized)
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	if _, err := login("vic", "wrong"); err == nil {
		t.Fatal("expected a rejected login to return an error")
	}
}

func TestRedeemWithAssertionSendsAssertionNotInvite(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		var body redeemRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Errorf("decode redeem request: %v", err)
			return
		}
		if body.Assertion != "account.assertion.jwt" || body.InviteCode != "" || body.PublicKey != strings.Repeat("A", 43)+"=" {
			t.Errorf("unexpected assertion redeem request: %+v", body)
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(peerConfig{
			ServerPublicKey: strings.Repeat("B", 43) + "=",
			Endpoint:        "game.example:51900",
			AssignedAddress: "10.77.0.2/32",
			AllowedIPs:      "192.168.1.254/32",
			Keepalive:       25,
		})
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	config, err := redeemWithAssertion("account.assertion.jwt", strings.Repeat("A", 43)+"=")
	if err != nil {
		t.Fatal(err)
	}
	if config.AssignedAddress != "10.77.0.2/32" {
		t.Fatalf("unexpected assigned address: %q", config.AssignedAddress)
	}
}

func TestProvisionPeerUsesLoginByDefault(t *testing.T) {
	t.Setenv("PROJECT0_INVITE_CODE", "")
	originalArgs := os.Args
	os.Args = []string{"launcher.exe"}
	defer func() { os.Args = originalArgs }()
	original := credentialPrompter
	credentialPrompter = func() (string, string) { return "vic", "s3cret" }
	defer func() { credentialPrompter = original }()

	var sawLogin, sawAssertionRedeem bool
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/login":
			sawLogin = true
			writer.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(writer).Encode(loginResponse{Assertion: "account.assertion.jwt"})
		case "/redeem":
			var body redeemRequest
			_ = json.NewDecoder(request.Body).Decode(&body)
			if body.Assertion == "account.assertion.jwt" && body.InviteCode == "" {
				sawAssertionRedeem = true
			}
			writer.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(writer).Encode(peerConfig{
				ServerPublicKey: strings.Repeat("B", 43) + "=",
				Endpoint:        "game.example:51900",
				AssignedAddress: "10.77.0.2/32",
				AllowedIPs:      "192.168.1.254/32",
				Keepalive:       25,
			})
		default:
			t.Errorf("unexpected path: %q", request.URL.Path)
		}
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	if _, err := provisionPeer(strings.Repeat("A", 43) + "="); err != nil {
		t.Fatal(err)
	}
	if !sawLogin || !sawAssertionRedeem {
		t.Fatalf("default path must log in then redeem with the assertion (login=%v, assertionRedeem=%v)", sawLogin, sawAssertionRedeem)
	}
}

func TestProvisionPeerPrefersExplicitInvite(t *testing.T) {
	t.Setenv("PROJECT0_INVITE_CODE", "invite-123")
	originalArgs := os.Args
	os.Args = []string{"launcher.exe"}
	defer func() { os.Args = originalArgs }()
	// If the invite path is taken, the credential prompt must never run.
	original := credentialPrompter
	credentialPrompter = func() (string, string) {
		t.Fatal("credential prompt must not run when an invite is supplied")
		return "", ""
	}
	defer func() { credentialPrompter = original }()

	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/redeem" {
			t.Errorf("invite path posted to unexpected path: %q", request.URL.Path)
		}
		var body redeemRequest
		_ = json.NewDecoder(request.Body).Decode(&body)
		if body.InviteCode != "invite-123" || body.Assertion != "" {
			t.Errorf("unexpected invite redeem request: %+v", body)
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(peerConfig{
			ServerPublicKey: strings.Repeat("B", 43) + "=",
			Endpoint:        "game.example:51900",
			AssignedAddress: "10.77.0.2/32",
			AllowedIPs:      "192.168.1.254/32",
			Keepalive:       25,
		})
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	if _, err := provisionPeer(strings.Repeat("A", 43) + "="); err != nil {
		t.Fatal(err)
	}
}

func TestEnrollmentBaseURLToleratesRedeemSuffix(t *testing.T) {
	t.Setenv("PROJECT0_ENROLLMENT_URL", "https://enroll.example.com/redeem/")
	if got := enrollmentBaseURL(); got != "https://enroll.example.com" {
		t.Fatalf("unexpected base URL: %q", got)
	}
	t.Setenv("PROJECT0_ENROLLMENT_URL", "")
	if got := enrollmentBaseURL(); got != "https://project0.valentin.vip" {
		t.Fatalf("unexpected default base URL: %q", got)
	}
}

func TestRedeemSendsOnlyInviteAndPublicKey(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		var body redeemRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Errorf("decode request: %v", err)
			return
		}
		if body.InviteCode != "invite-123" || body.PublicKey != strings.Repeat("A", 43)+"=" {
			t.Errorf("unexpected redeem request: %+v", body)
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(peerConfig{
			ServerPublicKey: strings.Repeat("B", 43) + "=",
			Endpoint:        "game.example:51900",
			AssignedAddress: "10.77.0.2/32",
			AllowedIPs:      "192.168.1.254/32",
			Keepalive:       25,
		})
	}))
	defer server.Close()
	t.Setenv("PROJECT0_ENROLLMENT_URL", server.URL)

	config, err := redeem("invite-123", strings.Repeat("A", 43)+"=")
	if err != nil {
		t.Fatal(err)
	}
	if config.AssignedAddress != "10.77.0.2/32" {
		t.Fatalf("unexpected assigned address: %q", config.AssignedAddress)
	}
}

func TestCachedPeerMustMatchProtectedPrivateKey(t *testing.T) {
	privateKey := make([]byte, 32)
	for index := range privateKey {
		privateKey[index] = byte(index + 1)
	}
	privateKey[0] &= 248
	privateKey[31] &= 127
	privateKey[31] |= 64
	publicKey, err := curve25519.X25519(privateKey, curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	config := peerConfig{ClientPublicKey: base64.StdEncoding.EncodeToString(publicKey)}
	if !config.matchesPrivateKey(privateKey) {
		t.Fatal("matching private key was rejected")
	}
	// Flip a non-clamped byte: X25519 re-clamps bit 0 of byte[0], so mutating it
	// would derive the same public key and not actually be a mismatch.
	privateKey[16] ^= 1
	if config.matchesPrivateKey(privateKey) {
		t.Fatal("mismatched private key was accepted")
	}
}

func TestInviteMaterialIsNotForwardedToGame(t *testing.T) {
	args := forwardedArgs([]string{"--invite-code=one-time", "--fullscreen"})
	if strings.Join(args, " ") != "--fullscreen" {
		t.Fatalf("invite argument was forwarded: %v", args)
	}
	t.Setenv("PROJECT0_INVITE_CODE", "one-time")
	for _, entry := range filteredEnvironment() {
		if strings.HasPrefix(entry, "PROJECT0_INVITE_CODE=") {
			t.Fatal("invite environment variable was forwarded")
		}
	}
}
