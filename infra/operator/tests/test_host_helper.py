import base64
import hashlib
import hmac
import json
import subprocess

from infra.operator.host_helper import execute


def make_token(secret: str, scopes: list[str]) -> str:
    claims = {"v": 1, "aid": "operator", "iss": "project0-console", "aud": "project0-console", "iat": 1_700_000_000, "exp": 4_102_444_800, "scp": scopes}
    payload = base64.b64encode(json.dumps(claims, separators=(",", ":")).encode()).decode()
    sig = base64.b64encode(hmac.new(bytes.fromhex(secret), payload.encode(), hashlib.sha256).digest()).decode()
    return f"{payload}.{sig}"


def test_helper_executes_only_allowlisted_lifecycle_command() -> None:
    calls = []

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        return subprocess.CompletedProcess(argv, 0, "", "")

    result = execute({"operator_token": make_token("00" * 32, ["lifecycle"]), "target": "game-server", "action": "restart"}, "00" * 32, runner)
    assert result["outcome"] == "accepted"
    assert calls[0][0] == ["systemctl", "restart", "project0-server"]
    assert calls[0][1]["shell"] is False


def test_helper_rejects_scope_and_command_injection() -> None:
    result = execute({"operator_token": make_token("00" * 32, ["read"]), "target": "game-server", "action": "restart"}, "00" * 32, lambda *_args, **_kwargs: None)
    assert result == {"outcome": "rejected", "reason": "operator_scope_denied"}

    result = execute({"operator_token": make_token("00" * 32, ["lifecycle"]), "target": "game-server; rm -rf /", "action": "restart"}, "00" * 32, lambda *_args, **_kwargs: None)
    assert result == {"outcome": "rejected", "reason": "unsupported_action"}
