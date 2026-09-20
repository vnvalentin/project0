"""Versioned, bounded operator control request/result contracts."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class ControlAction(StrEnum):
    START = "start"
    STOP = "stop"
    RESTART = "restart"
    KICK_PEER = "kick_peer"
    DRAIN = "drain"
    RELOAD_TUNING = "reload_tuning"
    SET_DEGRADED = "set_degraded"


class ControlOutcome(StrEnum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"


@dataclass(frozen=True)
class ControlRequest:
    request_id: str
    action: ControlAction
    target: str
    operator_identity: str
    granted_scopes: tuple[str, ...] = ()
    payload: tuple[tuple[str, str], ...] = ()

    def validate(self) -> str | None:
        if not self.request_id or len(self.request_id) > 96:
            return "invalid request_id"
        if not self.target or len(self.target) > 96:
            return "invalid target"
        if not self.operator_identity or len(self.operator_identity) > 96:
            return "invalid operator_identity"
        if len(self.granted_scopes) > 16 or any(not scope or len(scope) > 64 for scope in self.granted_scopes):
            return "invalid granted_scopes"
        if len(self.payload) > 16 or any(len(key) > 64 or len(value) > 256 for key, value in self.payload):
            return "invalid payload"
        return None


@dataclass(frozen=True)
class ControlResult:
    request_id: str
    outcome: ControlOutcome
    reason: str
    idempotent: bool = True


@dataclass(frozen=True)
class AuditRecord:
    request_id: str
    operator_identity: str
    action: ControlAction
    target: str
    outcome: ControlOutcome
    timestamp: int
    reason: str
