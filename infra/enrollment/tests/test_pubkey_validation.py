"""Unit tests for infra/enrollment/pubkey.py's strict public-key validation."""
from __future__ import annotations

import base64

import pytest

from infra.enrollment.pubkey import InvalidPublicKeyError, validate_public_key

VALID_KEY = base64.b64encode(bytes(range(32))).decode("ascii")


def test_accepts_well_formed_key():
    assert validate_public_key(VALID_KEY) == VALID_KEY


def test_rejects_wrong_length():
    with pytest.raises(InvalidPublicKeyError, match="44 characters"):
        validate_public_key("short==")


def test_rejects_non_equals_terminated():
    # 44 chars but does not end in '='.
    candidate = base64.b64encode(bytes(range(32))).decode("ascii")
    mangled = candidate[:-1] + "A"
    with pytest.raises(InvalidPublicKeyError, match="base64"):
        validate_public_key(mangled)


def test_rejects_invalid_base64_characters():
    candidate = ("!" * 43) + "="
    with pytest.raises(InvalidPublicKeyError):
        validate_public_key(candidate)


def test_rejects_wrong_decoded_length():
    # 31 raw bytes base64-encodes to exactly 44 '='-terminated characters,
    # same shape as a real key but one byte short.
    candidate = base64.b64encode(bytes(range(31))).decode("ascii")
    assert len(candidate) == 44
    assert candidate.endswith("=")
    with pytest.raises(InvalidPublicKeyError, match="got 31"):
        validate_public_key(candidate)


def test_rejects_non_string_input():
    with pytest.raises(InvalidPublicKeyError):
        validate_public_key(12345)  # type: ignore[arg-type]
