"""Validated per-Agent model and reasoning configuration."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Mapping, Sequence


MODEL_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$")
CODEX_REASONING_EFFORTS = ("low", "medium", "high", "xhigh")


@dataclass(frozen=True)
class AgentInvocationProfile:
    agent_id: str
    default_model: str = ""
    models: tuple[str, ...] = ()
    reasoning_efforts: tuple[str, ...] = ()

    @property
    def configurable(self) -> bool:
        return bool(self.models or self.reasoning_efforts)

    def public(self) -> dict:
        return {
            "default_model": self.default_model,
            "models": [
                {"id": model, "display_name": model}
                for model in self.models
            ],
            "reasoning_efforts": list(self.reasoning_efforts),
        }


@dataclass(frozen=True)
class AgentInvocationSelection:
    model_id: str = ""
    reasoning_effort: str = ""


def invocation_profile_for(
    agent_id: str,
    command: Sequence[str] | None,
) -> AgentInvocationProfile:
    clean_agent_id = str(agent_id or "").strip().casefold()
    command_model = _command_model(command)
    configured_models = _configured_models(clean_agent_id)
    models = _unique_valid_models((command_model, *configured_models))
    if clean_agent_id != "codex":
        return AgentInvocationProfile(agent_id=clean_agent_id)
    default_model = command_model if command_model in models else (models[0] if models else "")
    return AgentInvocationProfile(
        agent_id=clean_agent_id,
        default_model=default_model,
        models=models,
        reasoning_efforts=CODEX_REASONING_EFFORTS,
    )


def requested_agent_invocation(
    agent_id: str,
    value: object,
    command: Sequence[str] | None,
) -> AgentInvocationSelection:
    if not isinstance(value, Mapping):
        return AgentInvocationSelection()
    profile = invocation_profile_for(agent_id, command)
    requested_model = str(value.get("model_id") or "").strip()
    requested_effort = str(value.get("reasoning_effort") or "").strip().casefold()
    if requested_effort == "auto":
        requested_effort = ""
    if requested_model:
        if not MODEL_ID_PATTERN.fullmatch(requested_model):
            raise ValueError("Agent model id is invalid")
        if requested_model not in profile.models:
            raise ValueError(f"Agent model is not advertised by {agent_id}: {requested_model}")
    if requested_effort and requested_effort not in profile.reasoning_efforts:
        raise ValueError(
            f"Agent reasoning effort is not supported by {agent_id}: {requested_effort}"
        )
    if (requested_model or requested_effort) and not profile.configurable:
        raise ValueError(f"Agent does not expose configurable invocation options: {agent_id}")
    return AgentInvocationSelection(
        model_id=requested_model or profile.default_model,
        reasoning_effort=requested_effort,
    )


def _configured_models(agent_id: str) -> tuple[str, ...]:
    if not agent_id:
        return ()
    raw = os.environ.get(f"SIGNALASI_{agent_id.upper().replace('-', '_')}_MODELS", "")
    return tuple(part.strip() for part in re.split(r"[,;]", raw) if part.strip())


def _command_model(command: Sequence[str] | None) -> str:
    values = [str(value or "").strip() for value in command or ()]
    for index, value in enumerate(values[:-1]):
        if value in {"--model", "-m"}:
            candidate = values[index + 1]
            return candidate if MODEL_ID_PATTERN.fullmatch(candidate) else ""
    return ""


def _unique_valid_models(values: Sequence[str]) -> tuple[str, ...]:
    result: list[str] = []
    for value in values:
        clean = str(value or "").strip()
        if clean and MODEL_ID_PATTERN.fullmatch(clean) and clean not in result:
            result.append(clean)
    return tuple(result)
