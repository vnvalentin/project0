"""Bounded process-local abuse controls for public authentication routes."""
from __future__ import annotations

import time
from collections import defaultdict
from collections.abc import Callable


class PublicAuthRateLimiter:
    """Track bounded request/failure windows without storing credentials or tokens."""

    def __init__(self, max_attempts: int = 5, window_seconds: float = 60.0,
                 lockout_seconds: float = 300.0,
                 clock: Callable[[], float] = time.monotonic) -> None:
        if max_attempts < 1 or window_seconds <= 0 or lockout_seconds <= 0:
            raise ValueError("public auth limiter bounds must be positive")
        self.max_attempts = max_attempts
        self.window_seconds = window_seconds
        self.lockout_seconds = lockout_seconds
        self._clock = clock
        self._events: dict[str, list[float]] = defaultdict(list)
        self._locked_until: dict[str, float] = {}

    def _now(self, now: float | None) -> float:
        return self._clock() if now is None else now

    def _prune(self, key: str, now: float) -> list[float]:
        events = [event for event in self._events.get(key, []) if event > now - self.window_seconds]
        if events:
            self._events[key] = events
        else:
            self._events.pop(key, None)
        return events

    def allowed(self, key: str, now: float | None = None) -> bool:
        current = self._now(now)
        locked_until = self._locked_until.get(key, 0.0)
        if locked_until > current:
            return False
        if locked_until:
            self._locked_until.pop(key, None)
            self._events.pop(key, None)
        return len(self._prune(key, current)) < self.max_attempts

    def record_failure(self, key: str, now: float | None = None) -> None:
        current = self._now(now)
        events = self._prune(key, current)
        events.append(current)
        self._events[key] = events
        if len(events) >= self.max_attempts:
            self._locked_until[key] = current + self.lockout_seconds

    def record_success(self, key: str) -> None:
        self._events.pop(key, None)
        self._locked_until.pop(key, None)

    def consume(self, key: str, now: float | None = None) -> bool:
        current = self._now(now)
        if not self.allowed(key, current):
            return False
        events = self._prune(key, current)
        events.append(current)
        self._events[key] = events
        if len(events) >= self.max_attempts:
            self._locked_until[key] = current + self.lockout_seconds
        return True
