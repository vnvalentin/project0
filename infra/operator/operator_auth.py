"""Independent verification of Project0 operator assertions."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class OperatorIdentity:
    identity: str
    scopes: frozenset[str]


def verify_operator_token(token: str, secret_hex: str, expected_issuer: str = "project0-console", expected_audience: str = "project0-console", now: int | None = None) -> OperatorIdentity | None:
    try:
        payload_b64, signature_b64 = token.split(".", 1)
        payload = base64.b64decode(payload_b64, validate=True)
        provided = base64.b64decode(signature_b64, validate=True)
        expected = hmac.new(bytes.fromhex(secret_hex), payload_b64.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(provided, expected):
            return None
        claims = json.loads(payload.decode("utf-8"))
        current = int(time.time()) if now is None else now
        if claims.get("v") != 1 or claims.get("iss") != expected_issuer or claims.get("aud") != expected_audience:
            return None
        if not isinstance(claims.get("aid"), str) or not claims["aid"]:
            return None
        if current < int(claims.get("iat", -1)) or current >= int(claims.get("exp", 0)):
            return None
        scopes = claims.get("scp", ["*"])
        if not isinstance(scopes, list) or any(not isinstance(scope, str) for scope in scopes):
            return None
        return OperatorIdentity(claims["aid"], frozenset(scopes))
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None
