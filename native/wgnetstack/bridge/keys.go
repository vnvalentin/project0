package bridge

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
)

// base64KeyToHex converts a WireGuard base64 key (32 raw bytes) to the lower
// case hex string IpcSet expects.
func base64KeyToHex(b64 string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return "", fmt.Errorf("decoding base64 key: %w", err)
	}
	if len(raw) != 32 {
		return "", fmt.Errorf("wireguard key must decode to 32 bytes, got %d", len(raw))
	}
	return hex.EncodeToString(raw), nil
}
