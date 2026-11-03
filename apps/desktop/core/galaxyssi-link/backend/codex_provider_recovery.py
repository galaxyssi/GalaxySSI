"""Bound retries of a failed provider connection, not the lifetime of useful work."""
from dataclasses import dataclass


@dataclass
class ProviderRecovery:
    started: float | None = None
    error: str = ""
    terminal: bool = False
    budget_seconds: float = 120.0

    def observe(self, params: dict, now: float):
        error = params.get("error")
        if not isinstance(error, dict) or not isinstance(params.get("willRetry"), bool):
            return
        if self.started is None:
            self.started = now
        self.error = str(error.get("message") or "Codex provider connection failed")[:1600]
        self.terminal = self.terminal or not params["willRetry"]

    def recovered(self):
        if not self.terminal:
            self.started, self.error = None, ""

    def expired(self, now: float) -> bool:
        return self.terminal or self.started is not None and now - self.started >= self.budget_seconds
