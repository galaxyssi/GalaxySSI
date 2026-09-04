"""Persistent GalaxySSI Agent connector configuration."""
from __future__ import annotations

import json
import os
import re
from copy import deepcopy
from pathlib import Path
from typing import Any


def _config_path() -> Path:
    configured = os.environ.get("GALAXYSSI_CONFIG_PATH", "").strip()
    if configured:
        return Path(configured)
    state_directory = os.environ.get("GALAXYSSI_STATE_DIR", "").strip()
    root = Path(state_directory) if state_directory else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"
    return root / "agents.json"
MASK = "********"

DEFAULT_CONFIG: dict[str, Any] = {
    "commands": {
        "hermes": "hermes chat -q",
        "codex": "codex exec --skip-git-repo-check --ephemeral --model gpt-5.6-sol -c model_reasoning_effort=\"low\" -",
        "claude": "claude -p",
        "gemini": "gemini -p",
        "openclaw": "openclaw agent --agent main --message {prompt} --json",
        "custom-agent": "",
    },
    "local_model": {
        "name": "Local LLM",
        "provider": "auto",
        "url": "",
        "model": "qwen2.5:7b",
        "api_key": "",
        "context_window_tokens": 64_000,
        "max_output_tokens": 4_096,
        "context_model_summary": True,
        "input_micros_per_million_tokens": "",
        "output_micros_per_million_tokens": "",
        "pricing_currency": "USD",
    },
    "cloud_model": {
        "name": "Cloud Model",
        "provider": "openai",
        "url": "",
        "model": "",
        "api_key": "",
        "context_window_tokens": 64_000,
        "max_output_tokens": 4_096,
        "context_model_summary": True,
        "input_micros_per_million_tokens": "",
        "output_micros_per_million_tokens": "",
        "pricing_currency": "USD",
    },
    "web_search": {
        "brave_api_key": "",
        "github_token": "",
    },
    "language_policy": {
        "response_language": "auto",
        "asr_language": "auto",
        "tts_language": "auto",
    },
    "custom_agent": {
        "name": "Custom Agent",
    },
    "custom_agents": [],
    "cli_runtime": {
        "enabled": True,
        "max_processes": 4,
        "max_processes_per_agent": 2,
        "idle_timeout_seconds": 300,
        "max_requests_per_process": 100,
        "transports": {
            "codex": {"mode": "managed-app-server", "prewarm": True},
            "hermes": {"mode": "native-session", "prewarm": False},
            "claude": {"mode": "native-session", "prewarm": False},
            "openclaw": {"mode": "native-session", "prewarm": False},
        },
    },
    "acp_runtime": {
        "enabled": True,
        "max_processes": 5,
        "idle_timeout_seconds": 600,
        "agents": {
            "hermes": {
                "enabled": True,
                "command": "hermes acp",
                "prewarm": True,
            },
            "codex": {
                "enabled": True,
                "command": "codex-acp",
                "prewarm": False,
            },
            "claude": {
                "enabled": True,
                "command": "claude-agent-acp",
                "prewarm": True,
            },
            "gemini": {
                "enabled": True,
                "command": "gemini --acp",
                "prewarm": True,
            },
            "openclaw": {
                "enabled": True,
                "command": "openclaw acp",
                "prewarm": True,
            },
        },
    },
}


def load_config(mask_secrets: bool = False) -> dict[str, Any]:
    config = deepcopy(DEFAULT_CONFIG)
    config_path = _config_path()
    if config_path.exists():
        try:
            with config_path.open("r", encoding="utf-8-sig") as handle:
                saved = json.load(handle)
            _merge(config, saved)
        except Exception:
            pass
    if mask_secrets:
        for section in ("local_model", "cloud_model"):
            if config.get(section, {}).get("api_key", ""):
                config[section]["api_key"] = MASK
        for key in ("brave_api_key", "github_token"):
            if config.get("web_search", {}).get(key, ""):
                config["web_search"][key] = MASK
    return config


def save_config(incoming: dict[str, Any]) -> dict[str, Any]:
    current = load_config(mask_secrets=False)
    updated = deepcopy(DEFAULT_CONFIG)
    _merge(updated, current)
    sanitized = _sanitize(incoming)

    for section in ("local_model", "cloud_model"):
        if sanitized.get(section, {}).get("api_key") == MASK:
            sanitized[section]["api_key"] = current.get(section, {}).get("api_key", "")
    for key in ("brave_api_key", "github_token"):
        if sanitized.get("web_search", {}).get(key) == MASK:
            sanitized["web_search"][key] = current.get("web_search", {}).get(key, "")

    from language_policy import normalize_language

    language_policy = sanitized.get("language_policy")
    if isinstance(language_policy, dict):
        for key in ("response_language", "asr_language", "tts_language"):
            language_policy[key] = normalize_language(language_policy.get(key))

    _merge(updated, sanitized)
    _write_config(_config_path(), updated)
    return load_config(mask_secrets=True)


def _write_config(config_path: Path, config: dict[str, Any]) -> None:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = config_path.with_suffix(f"{config_path.suffix}.tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, ensure_ascii=False, indent=2)
    temporary.replace(config_path)


def command_for(agent_id: str) -> str:
    config = load_config()
    command = str(config.get("commands", {}).get(agent_id, "")).strip()
    if command:
        return command
    for agent in custom_agent_configs(config):
        if agent["id"] == agent_id:
            return agent["command"]
    return ""


def local_model_config() -> dict[str, Any]:
    data = load_config().get("local_model", {})
    name = str(data.get("name", "")).strip() or "Local LLM"
    return {
        "name": name[:48],
        "provider": str(data.get("provider", "auto")).strip() or "auto",
        "url": str(data.get("url", "")).strip(),
        "model": str(data.get("model", "")).strip(),
        "api_key": str(data.get("api_key", "")).strip(),
        "context_window_tokens": _bounded_int(data.get("context_window_tokens"), 64_000, 4_096, 1_000_000),
        "max_output_tokens": _bounded_int(data.get("max_output_tokens"), 4_096, 512, 128_000),
        "context_model_summary": _as_bool(data.get("context_model_summary"), True),
        "input_micros_per_million_tokens": _optional_bounded_int(
            data.get("input_micros_per_million_tokens"),
            0,
            1_000_000_000_000,
        ),
        "output_micros_per_million_tokens": _optional_bounded_int(
            data.get("output_micros_per_million_tokens"),
            0,
            1_000_000_000_000,
        ),
        "pricing_currency": _currency(data.get("pricing_currency")),
    }


def cloud_model_config() -> dict[str, Any]:
    data = load_config().get("cloud_model", {})
    name = str(data.get("name", "")).strip() or "Cloud Model"
    return {
        "name": name[:48],
        "provider": str(data.get("provider", "openai")).strip().lower() or "openai",
        "url": str(data.get("url", "")).strip(),
        "model": str(data.get("model", "")).strip(),
        "api_key": str(data.get("api_key", "")).strip(),
        "context_window_tokens": _bounded_int(data.get("context_window_tokens"), 64_000, 4_096, 1_000_000),
        "max_output_tokens": _bounded_int(data.get("max_output_tokens"), 4_096, 512, 128_000),
        "context_model_summary": _as_bool(data.get("context_model_summary"), True),
        "input_micros_per_million_tokens": _optional_bounded_int(
            data.get("input_micros_per_million_tokens"),
            0,
            1_000_000_000_000,
        ),
        "output_micros_per_million_tokens": _optional_bounded_int(
            data.get("output_micros_per_million_tokens"),
            0,
            1_000_000_000_000,
        ),
        "pricing_currency": _currency(data.get("pricing_currency")),
    }


def language_policy_config() -> dict[str, str]:
    from language_policy import normalize_language

    data = load_config().get("language_policy", {})
    return {
        "response_language": normalize_language(data.get("response_language")),
        "asr_language": normalize_language(data.get("asr_language")),
        "tts_language": normalize_language(data.get("tts_language")),
    }


def web_search_config() -> dict[str, str]:
    data = load_config().get("web_search", {})
    return {
        "brave_api_key": str(data.get("brave_api_key", "")).strip(),
        "github_token": str(data.get("github_token", "")).strip(),
    }


def custom_agent_config() -> dict[str, str]:
    data = load_config().get("custom_agent", {})
    name = str(data.get("name", "")).strip() or "Custom Agent"
    return {"name": name[:48]}


def custom_agent_configs(config: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    data = (config or load_config()).get("custom_agents", [])
    if not isinstance(data, list):
        return []
    agents: list[dict[str, Any]] = []
    seen: set[str] = set()
    reserved = {
        "hermes",
        "codex",
        "claude",
        "gemini",
        "openclaw",
        "local-llm",
        "cloud-model",
        "custom-agent",
    }
    for item in data[:12]:
        if not isinstance(item, dict):
            continue
        agent_id = _normalize_agent_id(str(item.get("id", "")))
        if not agent_id or agent_id in reserved or agent_id in seen:
            continue
        command = str(item.get("command", "")).strip()
        if not command:
            continue
        name = str(item.get("name", "")).strip() or agent_id.replace("-", " ").title()
        kind = str(item.get("kind", "custom-cli")).strip() or "custom-cli"
        agents.append({
            "id": agent_id[:48],
            "name": name[:48],
            "kind": kind[:32],
            "command": command,
            "transport": _normalize_cli_transport(item.get("transport")),
            "pool_size": _bounded_int(item.get("pool_size"), 1, 1, 8),
            "prewarm": _as_bool(item.get("prewarm"), False),
        })
        seen.add(agent_id)
    return agents


def cli_runtime_config(config: dict[str, Any] | None = None) -> dict[str, Any]:
    data = (config or load_config()).get("cli_runtime", {})
    if not isinstance(data, dict):
        data = {}
    raw_transports = data.get("transports", {})
    transports: dict[str, dict[str, Any]] = {}
    if isinstance(raw_transports, dict):
        for raw_agent_id, value in raw_transports.items():
            agent_id = _normalize_agent_id(str(raw_agent_id or ""))
            if not agent_id:
                continue
            item = value if isinstance(value, dict) else {"mode": value}
            transports[agent_id] = {
                "mode": _normalize_cli_transport(item.get("mode")),
                "pool_size": _bounded_int(item.get("pool_size"), 1, 1, 8),
                "prewarm": _as_bool(item.get("prewarm"), False),
            }
    for item in custom_agent_configs(config or load_config()):
        if item["transport"] != "oneshot":
            transports[item["id"]] = {
                "mode": item["transport"],
                "pool_size": item["pool_size"],
                "prewarm": item["prewarm"],
            }
    return {
        "enabled": _as_bool(data.get("enabled"), True),
        "max_processes": _bounded_int(data.get("max_processes"), 4, 1, 32),
        "max_processes_per_agent": _bounded_int(
            data.get("max_processes_per_agent"),
            2,
            1,
            8,
        ),
        "idle_timeout_seconds": _bounded_int(
            data.get("idle_timeout_seconds"),
            300,
            5,
            86_400,
        ),
        "max_requests_per_process": _bounded_int(
            data.get("max_requests_per_process"),
            100,
            1,
            10_000,
        ),
        "transports": transports,
    }


def cli_agent_runtime_config(
    agent_id: str,
    command: list[str] | tuple[str, ...] = (),
) -> dict[str, Any]:
    config = cli_runtime_config()
    normalized_id = _normalize_agent_id(agent_id)
    item = dict(config["transports"].get(normalized_id, {}))
    if "--serve-jsonl" in command:
        item["mode"] = "galaxyssi-jsonl-v1"
    return {
        "enabled": bool(config["enabled"]),
        "mode": _normalize_cli_transport(item.get("mode")),
        "pool_size": _bounded_int(item.get("pool_size"), 1, 1, 8),
        "prewarm": _as_bool(item.get("prewarm"), False),
    }


def acp_runtime_config(config: dict[str, Any] | None = None) -> dict[str, Any]:
    data = (config or load_config()).get("acp_runtime", {})
    if not isinstance(data, dict):
        data = {}
    configured_agents = data.get("agents", {})
    if not isinstance(configured_agents, dict):
        configured_agents = {}
    defaults = DEFAULT_CONFIG["acp_runtime"]["agents"]
    agents: dict[str, dict[str, Any]] = {}
    for agent_id, default in defaults.items():
        incoming = configured_agents.get(agent_id, {})
        if not isinstance(incoming, dict):
            incoming = {}
        command = str(incoming.get("command", default["command"])).strip()
        agents[agent_id] = {
            "enabled": _as_bool(incoming.get("enabled"), bool(default["enabled"])),
            "command": command[:2_000],
            "prewarm": _as_bool(incoming.get("prewarm"), bool(default["prewarm"])),
        }
    return {
        "enabled": _as_bool(data.get("enabled"), True),
        "max_processes": _bounded_int(data.get("max_processes"), 5, 1, 16),
        "idle_timeout_seconds": _bounded_int(
            data.get("idle_timeout_seconds"),
            600,
            30,
            86_400,
        ),
        "agents": agents,
    }


def acp_agent_runtime_config(
    agent_id: str,
    config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    runtime = acp_runtime_config(config)
    normalized_id = _normalize_agent_id(agent_id)
    item = dict(runtime["agents"].get(normalized_id, {}))
    return {
        "runtime_enabled": bool(runtime["enabled"]),
        "enabled": bool(item.get("enabled")),
        "command": str(item.get("command") or "").strip(),
        "prewarm": bool(item.get("prewarm")),
        "max_processes": int(runtime["max_processes"]),
        "idle_timeout_seconds": int(runtime["idle_timeout_seconds"]),
    }


def _merge(target: dict[str, Any], source: dict[str, Any]) -> None:
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            _merge(target[key], value)
        else:
            target[key] = value


def _sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): _sanitize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize(v) for v in value]
    if value is None:
        return ""
    return value


def _normalize_agent_id(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9_-]+", "-", value.strip().lower())
    cleaned = re.sub(r"-+", "-", cleaned).strip("-_")
    return cleaned[:48]


def _normalize_cli_transport(value: Any) -> str:
    normalized = str(value or "oneshot").strip().lower().replace("_", "-")
    aliases = {
        "jsonl": "galaxyssi-jsonl-v1",
        "jsonl-v1": "galaxyssi-jsonl-v1",
        "persistent-jsonl": "galaxyssi-jsonl-v1",
        "app-server": "managed-app-server",
        "session": "native-session",
    }
    normalized = aliases.get(normalized, normalized)
    return normalized if normalized in {
        "oneshot",
        "galaxyssi-jsonl-v1",
        "managed-app-server",
        "native-session",
    } else "oneshot"


def _bounded_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = default
    return max(minimum, min(maximum, parsed))


def _optional_bounded_int(value: Any, minimum: int, maximum: int) -> int | None:
    if value is None or str(value).strip() == "":
        return None
    return _bounded_int(value, minimum, minimum, maximum)


def _currency(value: Any) -> str:
    normalized = str(value or "USD").strip().upper()
    return normalized if len(normalized) == 3 and normalized.isalpha() else "USD"


def _as_bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"", "0", "false", "no", "off"}:
        return False
    return default
