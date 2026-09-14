"""Strict validation for client-supplied WireGuard public keys.

A WireGuard key is 32 raw bytes, base64-encoded with padding, which always
produces a 44-character string ending in `=`. This module validates that
shape only; it never sees or accepts a private key.

Delivered for Slice 048 (docs/slices/048-wireguard-enrollment-service.md).
"""
from __future__ import annotations

import base64

PUBLIC_KEY_LENGTH_CHARS = 44
PUBLIC_KEY_DECODED_BYTES = 32


class InvalidPublicKeyError(ValueError):
    """Raised when a supplied string is not a well-formed WireGuard public key."""


def validate_public_key(candidate: str) -> str:
    """Return the validated public key string, or raise InvalidPublicKeyError.

    Rejects anything that is not exactly 44 characters, does not end in '=',
    is not valid base64, or does not decode to exactly 32 bytes.
    """
    if not isinstance(candidate, str):
        raise InvalidPublicKeyError("public key must be a string")
    if len(candidate) != PUBLIC_KEY_LENGTH_CHARS:
        raise InvalidPublicKeyError(
            f"public key must be {PUBLIC_KEY_LENGTH_CHARS} characters, got {len(candidate)}"
        )
    if not candidate.endswith("="):
        raise InvalidPublicKeyError("public key must be '='-padded base64")
    try:
        decoded = base64.b64decode(candidate, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise InvalidPublicKeyError(f"public key is not valid base64: {exc}") from exc
    if len(decoded) != PUBLIC_KEY_DECODED_BYTES:
        raise InvalidPublicKeyError(
            f"public key must decode to {PUBLIC_KEY_DECODED_BYTES} bytes, got {len(decoded)}"
        )
    return candidate
