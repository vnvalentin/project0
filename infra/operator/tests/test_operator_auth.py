import base64
import hashlib
import hmac
import json

from infra.operator.operator_auth import verify_operator_token


def token(secret: str, claims: dict) -> str:
    payload = base64.b64encode(json.dumps(claims, separators=(",", ":")).encode()).decode()
    signature = base64.b64encode(hmac.new(bytes.fromhex(secret), payload.encode(), hashlib.sha256).digest()).decode()
    return f"{payload}.{signature}"


def test_verify_operator_assertion() -> None:
    claims = {"v": 1, "aid": "operator", "iss": "project0-console", "aud": "project0-console", "iat": 100, "exp": 200, "scp": ["lifecycle"]}
    identity = verify_operator_token(token("00" * 32, claims), "00" * 32, now=150)
    assert identity is not None
    assert identity.identity == "operator"
    assert identity.scopes == {"lifecycle"}


def test_verify_operator_assertion_rejects_tamper_and_expiry() -> None:
    claims = {"v": 1, "aid": "operator", "iss": "project0-console", "aud": "project0-console", "iat": 100, "exp": 200}
    signed = token("00" * 32, claims)
    assert verify_operator_token(signed + "x", "00" * 32, now=150) is None
    assert verify_operator_token(signed, "00" * 32, now=200) is None
