"""Validated per-Agent model and reasoning configuration."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Mapping, Sequence


MODEL_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/\[\]-]{0,127}$")
CODEX_REASONING_EFFORTS = ("low", "medium", "high", "xhigh")
CODEX_VISION_FALLBACK_MODEL = "gpt-5.6-sol"
CODEX_TEXT_ONLY_MODELS = frozenset({"gpt-5.3-codex-spark"})
CODEX_MODELS = (
    ("gpt-5.6-sol", "\u80fd\u529b\u6700\u5f3a\uff0c\u590d\u6742\u7f16\u7801\u4e0e\u957f\u671f\u4efb\u52a1"),
    ("gpt-5.6-terra", "\u80fd\u529b\u3001\u901f\u5ea6\u3001\u6210\u672c\u5747\u8861"),
    ("gpt-5.6-luna", "\u5feb\u901f\u3001\u4f4e\u6210\u672c"),
    ("gpt-5.5", "\u590d\u6742\u7f16\u7801\u3001\u7814\u7a76\u548c\u901a\u7528\u4efb\u52a1"),
    ("gpt-5.4", "\u65e5\u5e38\u7f16\u7801"),
    ("gpt-5.4-mini", "\u7b80\u5355\u4efb\u52a1\u3001\u5b50\u667a\u80fd\u4f53"),
    ("gpt-5.3-codex-spark", "\u8d85\u9ad8\u901f\u7f16\u7801"),
)
CLAUDE_MODELS = (
    ("best", "\u6709\u6743\u9650\u65f6\u4f7f\u7528 Fable 5\uff0c\u5426\u5219 Opus 5"),
    ("fableclaude-fable-5", "\u6700\u957f\u4efb\u52a1\u3001\u6700\u9ad8\u80fd\u529b"),
    ("opusclaude-opus-5", "\u590d\u6742\u63a8\u7406\u548c Agent \u7f16\u7801"),
    ("sonnetclaude-sonnet-5", "\u65e5\u5e38\u7f16\u7801\u9996\u9009"),
    ("haikuclaude-haiku-4-5-20251001", "\u6700\u5feb\u3001\u6700\u4fbf\u5b9c"),
    ("opusplan", "Opus \u89c4\u5212\uff0cSonnet \u6267\u884c"),
    ("opus[1m]", "Opus\uff0c100 \u4e07\u4e0a\u4e0b\u6587"),
    ("sonnet[1m]", "Sonnet\uff0c100 \u4e07\u4e0a\u4e0b\u6587"),
)


@dataclass(frozen=True)
class AgentInvocationProfile:
    agent_id: str
    default_model: str = ""
    models: tuple[str, ...] = ()
    reasoning_efforts: tuple[str, ...] = ()
    model_descriptions: tuple[tuple[str, str], ...] = ()

    @property
    def configurable(self) -> bool:
        return bool(self.models or self.reasoning_efforts)

    def public(self) -> dict:
        descriptions = dict(self.model_descriptions)
        return {
            "default_model": self.default_model,
            "models": [
                {
                    "id": model,
                    "display_name": model,
                    "description": descriptions.get(model, ""),
                }
                for model in self.models
            ],
            "reasoning_efforts": list(self.reasoning_efforts),
        }


@dataclass(frozen=True)
class AgentInvocationSelection:
    model_id: str = ""
    reasoning_effort: str = ""


def effective_agent_model(
    agent_id: str,
    model_id: str,
    *,
    has_image_input: bool,
) -> str:
    """Keep the saved selection, but use a native-vision model for image turns."""
    clean_agent_id = str(agent_id or "").strip().casefold()
    clean_model_id = str(model_id or "").strip()
    if (
        has_image_input
        and clean_agent_id == "codex"
        and clean_model_id in CODEX_TEXT_ONLY_MODELS
    ):
        return CODEX_VISION_FALLBACK_MODEL
    return clean_model_id


def invocation_profile_for(
    agent_id: str,
    command: Sequence[str] | None,
) -> AgentInvocationProfile:
    clean_agent_id = str(agent_id or "").strip().casefold()
    command_model = _command_model(command)
    catalog = {
        "codex": CODEX_MODELS,
        "claude": CLAUDE_MODELS,
    }.get(clean_agent_id, ())
    configured_models = _configured_models(clean_agent_id)
    models = _unique_valid_models((
        command_model,
        *(model_id for model_id, _ in catalog),
        *configured_models,
    ))
    if clean_agent_id not in {"codex", "claude"}:
        return AgentInvocationProfile(agent_id=clean_agent_id)
    default_model = (
        command_model
        if command_model in models
        else ("best" if clean_agent_id == "claude" and "best" in models else (models[0] if models else ""))
    )
    return AgentInvocationProfile(
        agent_id=clean_agent_id,
        default_model=default_model,
        models=models,
        reasoning_efforts=(CODEX_REASONING_EFFORTS if clean_agent_id == "codex" else ()),
        model_descriptions=tuple(catalog),
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
