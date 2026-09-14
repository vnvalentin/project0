//go:build windows

package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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

func TestMissingInviteFailsClosed(t *testing.T) {
	t.Setenv("PROJECT0_INVITE_CODE", "")
	if got := inviteCode(); got != "" {
		t.Fatalf("expected no invite, got %q", got)
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
