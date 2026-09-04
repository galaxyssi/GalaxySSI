"""Feature gates for staged latency protocol upgrades."""
from __future__ import annotations

import os


def feature_enabled(name: str, *, default: bool = False) -> bool:
    env_name = "GALAXYSSI_FEATURE_" + "".join(
        character if character.isalnum() else "_"
        for character in str(name or "").upper()
    )
    raw = os.environ.get(env_name)
    if raw is None:
        return default
    return str(raw).strip().lower() in {"1", "true", "yes", "on", "enabled"}


def agent_output_delta_enabled() -> bool:
    return feature_enabled("agent.output_delta_v1", default=True)
