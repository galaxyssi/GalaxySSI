"""Unified trusted catalog for native tools, MCP, and automation templates."""
from __future__ import annotations

import os
import threading
from dataclasses import dataclass
from typing import Any, Callable, Mapping


CONTRACT = "signalasi.tool-marketplace/1.0"
NATIVE_TOOL = "native_tool"
MCP = "mcp"
AUTOMATION = "automation"
INSTALL_STATES = {
    "built_in",
    "available",
    "installed",
    "needs_setup",
    "unavailable",
}


class ToolMarketplaceError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class MarketplaceDefinition:
    id: str
    kind: str
    name: str
    summary: str
    version: str = "1.0.0"
    publisher: str = "SignalASI"
    tags: tuple[str, ...] = ()
    dependencies: tuple[str, ...] = ()
    featured: bool = True
    trusted: bool = True
    install: Mapping[str, Any] | None = None

    def public(
        self,
        *,
        state: str,
        enabled: bool = False,
        installed_ref: str = "",
        status_detail: str = "",
    ) -> dict[str, Any]:
        if state not in INSTALL_STATES:
            raise ValueError(f"Unsupported marketplace state: {state}")
        return {
            "id": self.id,
            "kind": self.kind,
            "name": self.name,
            "summary": self.summary,
            "version": self.version,
            "publisher": self.publisher,
            "tags": list(self.tags),
            "dependencies": list(self.dependencies),
            "featured": self.featured,
            "trusted": self.trusted,
            "install_state": state,
            "enabled": bool(enabled),
            "installed_ref": installed_ref,
            "status_detail": status_detail,
        }


MCP_CATALOG = (
    MarketplaceDefinition(
        id="signalasi.mcp.github",
        kind=MCP,
        name="GitHub",
        summary="Repositories, issues, pull requests, and code workflows.",
        tags=("development", "source-control"),
        dependencies=("SIGNALASI_GITHUB_TOKEN",),
        install={
            "id": "marketplace.github",
            "name": "GitHub",
            "transport": "streamable_http",
            "endpoint": "https://api.githubcopilot.com/mcp/",
            "header_env": {"Authorization": "SIGNALASI_GITHUB_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["github", "repository", "pull request", "issue"],
            "permission_mode": "ask_for_changes",
            "import_source": "signalasi_marketplace",
        },
    ),
    MarketplaceDefinition(
        id="signalasi.mcp.notion",
        kind=MCP,
        name="Notion",
        summary="Search, read, and update a trusted Notion workspace.",
        tags=("knowledge", "documents"),
        dependencies=("SIGNALASI_NOTION_TOKEN",),
        install={
            "id": "marketplace.notion",
            "name": "Notion",
            "transport": "streamable_http",
            "endpoint": "https://mcp.notion.com/mcp",
            "header_env": {"Authorization": "SIGNALASI_NOTION_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["notion", "workspace page"],
            "permission_mode": "ask_for_changes",
            "import_source": "signalasi_marketplace",
        },
    ),
    MarketplaceDefinition(
        id="signalasi.mcp.home_assistant",
        kind=MCP,
        name="Home Assistant",
        summary="Read and control trusted smart-home entities and automations.",
        tags=("smart-home", "automation"),
        dependencies=("endpoint", "SIGNALASI_HOME_ASSISTANT_TOKEN"),
        install={
            "id": "marketplace.home-assistant",
            "name": "Home Assistant",
            "transport": "streamable_http",
            "endpoint": "",
            "header_env": {"Authorization": "SIGNALASI_HOME_ASSISTANT_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["home assistant", "smart home"],
            "permission_mode": "ask_for_changes",
            "import_source": "signalasi_marketplace",
        },
    ),
)


AUTOMATION_CATALOG = (
    MarketplaceDefinition(
        id="signalasi.automation.desktop-health",
        kind=AUTOMATION,
        name="Desktop health check",
        summary="Check Desktop runtime health every hour and retain a verified result.",
        tags=("health", "runtime"),
        dependencies=("signalasi.desktop.runtime.status",),
        install={
            "task_id": "marketplace.desktop-health",
            "name": "Desktop health check",
            "trigger": {"kind": "interval", "interval_seconds": 3600, "time_zone": "UTC"},
            "action": {
                "kind": "native_tool",
                "target_id": "signalasi.desktop.runtime.status",
                "arguments": {"refresh": True},
                "delivery": {"mode": "store"},
            },
            "policy": {
                "misfire": "fire_once",
                "max_attempts": 2,
                "max_consecutive_failures": 5,
                "network": "any",
            },
        },
    ),
    MarketplaceDefinition(
        id="signalasi.automation.morning-brief",
        kind=AUTOMATION,
        name="Morning brief",
        summary="Ask an available research Agent for a concise daily brief.",
        tags=("research", "daily"),
        dependencies=("agent:hermes",),
        install={
            "task_id": "marketplace.morning-brief",
            "name": "Morning brief",
            "trigger": {"kind": "cron", "cron": "0 9 * * *", "time_zone": "UTC"},
            "action": {
                "kind": "agent",
                "target_id": "hermes",
                "prompt": "Prepare a concise current morning brief with direct sources.",
                "delivery": {"mode": "notify"},
            },
            "policy": {
                "misfire": "fire_once",
                "max_attempts": 3,
                "max_consecutive_failures": 5,
                "network": "any",
            },
        },
    ),
    MarketplaceDefinition(
        id="signalasi.automation.weekly-project-review",
        kind=AUTOMATION,
        name="Weekly project review",
        summary="Review the active project and report verified progress once a week.",
        tags=("project", "development"),
        dependencies=("agent:codex",),
        install={
            "task_id": "marketplace.weekly-project-review",
            "name": "Weekly project review",
            "trigger": {"kind": "cron", "cron": "0 17 * * 5", "time_zone": "UTC"},
            "action": {
                "kind": "agent",
                "target_id": "codex",
                "prompt": "Inspect the active project and report verified progress, blockers, and next actions.",
                "delivery": {"mode": "notify"},
            },
            "policy": {
                "misfire": "fire_once",
                "max_attempts": 3,
                "max_consecutive_failures": 5,
                "network": "any",
            },
        },
    ),
)


class ToolMarketplace:
    def __init__(
        self,
        *,
        native_manifest: Callable[[], Mapping[str, Any]] | None = None,
        mcp_registry: Any = None,
        skill_registry: Any = None,
        proactive_runtime: Any = None,
        environment: Mapping[str, str] | None = None,
    ) -> None:
        self._native_manifest = native_manifest
        self._mcp_registry = mcp_registry
        self._skill_registry = skill_registry
        self._proactive_runtime = proactive_runtime
        self.environment = environment if environment is not None else os.environ

    def catalog(self, kind: str = "") -> dict[str, Any]:
        normalized_kind = str(kind or "").strip().casefold()
        if normalized_kind and normalized_kind not in {NATIVE_TOOL, MCP, AUTOMATION}:
            raise ToolMarketplaceError("invalid_kind", "Marketplace kind is invalid")
        items = self._native_items() + self._mcp_items() + self._automation_items()
        if normalized_kind:
            items = [item for item in items if item["kind"] == normalized_kind]
        items.sort(key=lambda item: (item["kind"], not item["featured"], item["name"].casefold()))
        counts = {
            state: sum(1 for item in items if item["install_state"] == state)
            for state in sorted(INSTALL_STATES)
        }
        return {
            "contract": CONTRACT,
            "items": items,
            "summary": {
                "total": len(items),
                "installed": counts["built_in"] + counts["installed"],
                "needs_setup": counts["needs_setup"],
                "unavailable": counts["unavailable"],
                "by_state": counts,
            },
        }

    def install(
        self,
        item_id: str,
        configuration: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        definition = self._definition(item_id)
        if definition.kind == NATIVE_TOOL:
            item = self._item(item_id)
            if item["install_state"] == "unavailable":
                raise ToolMarketplaceError("tool_unavailable", "This native tool is unavailable")
            return {"contract": CONTRACT, "changed": False, "item": item}
        if definition.kind == MCP:
            return self._install_mcp(definition, configuration or {})
        if definition.kind == AUTOMATION:
            return self._install_automation(definition)
        raise ToolMarketplaceError("unsupported_kind", "Marketplace item kind is unsupported")

    def uninstall(self, item_id: str) -> dict[str, Any]:
        definition = self._definition(item_id)
        if definition.kind == NATIVE_TOOL:
            raise ToolMarketplaceError("built_in", "Built-in tools cannot be uninstalled")
        if definition.kind == MCP:
            registry = self._mcp()
            ref = str((definition.install or {}).get("id") or "")
            changed = bool(registry.delete(ref))
        else:
            runtime = self._proactive()
            ref = str((definition.install or {}).get("task_id") or "")
            changed = bool(runtime.delete(ref))
        return {"contract": CONTRACT, "changed": changed, "item": self._item(item_id)}

    def _native_items(self) -> list[dict[str, Any]]:
        manifest = dict(self._native_provider()())
        result: list[dict[str, Any]] = []
        for tool in list(manifest.get("tools") or []):
            availability = dict(tool.get("availability") or {})
            availability_state = str(availability.get("status") or "unavailable")
            state = {
                "available": "built_in",
                "requires_setup": "needs_setup",
            }.get(availability_state, "unavailable")
            definition = MarketplaceDefinition(
                id=str(tool.get("id") or ""),
                kind=NATIVE_TOOL,
                name=str(tool.get("title") or tool.get("id") or "Native tool"),
                summary=str(tool.get("description") or "SignalASI native capability"),
                version=str(tool.get("version") or "1.0.0"),
                tags=tuple(str(value) for value in list(tool.get("capabilities") or [])),
                dependencies=tuple(
                    str(value.get("id") or "")
                    for value in list(tool.get("required_permissions") or [])
                    + list(tool.get("required_consents") or [])
                    if isinstance(value, Mapping) and str(value.get("id") or "")
                ),
            )
            result.append(
                definition.public(
                    state=state,
                    enabled=state == "built_in",
                    installed_ref=definition.id if state == "built_in" else "",
                    status_detail=str(availability.get("reason") or ""),
                )
            )
        return result

    def _mcp_items(self) -> list[dict[str, Any]]:
        connections = {
            str(item.get("id") or ""): item
            for item in self._mcp().list(include_configuration=True)
        }
        result: list[dict[str, Any]] = []
        for definition in MCP_CATALOG:
            install = dict(definition.install or {})
            ref = str(install.get("id") or "")
            connection = connections.get(ref)
            missing = self._missing_mcp_configuration(install, connection)
            if connection is None:
                state = "available"
                enabled = False
                detail = ""
            elif missing:
                state = "needs_setup"
                enabled = bool(connection.get("enabled"))
                detail = ", ".join(missing)
            elif str(connection.get("state") or "") == "error":
                state = "needs_setup"
                enabled = bool(connection.get("enabled"))
                detail = str(connection.get("last_error") or "")
            else:
                state = "installed"
                enabled = bool(connection.get("enabled"))
                detail = ""
            result.append(
                definition.public(
                    state=state,
                    enabled=enabled,
                    installed_ref=ref if connection else "",
                    status_detail=detail,
                )
            )
        return result

    def _automation_items(self) -> list[dict[str, Any]]:
        tasks = {
            str(task.task_id): task
            for task in self._proactive().store.tasks(limit=1_000)
        }
        result = []
        for definition in AUTOMATION_CATALOG:
            ref = str((definition.install or {}).get("task_id") or "")
            task = tasks.get(ref)
            result.append(
                definition.public(
                    state="installed" if task else "available",
                    enabled=bool(task and task.enabled),
                    installed_ref=ref if task else "",
                )
            )
        for skill in self._skills().list():
            definition = MarketplaceDefinition(
                id=str(skill.get("id") or ""),
                kind=AUTOMATION,
                name=str(skill.get("name") or skill.get("id") or "Automation"),
                summary=str(skill.get("description") or "Reusable Agent workflow"),
                publisher="SignalASI" if skill.get("source") == "builtin" else "Local user",
                tags=("skill", "workflow"),
                featured=skill.get("source") == "builtin",
                trusted=skill.get("source") == "builtin",
            )
            result.append(
                definition.public(
                    state="built_in" if skill.get("source") == "builtin" else "installed",
                    enabled=bool(skill.get("enabled", True)),
                    installed_ref=definition.id,
                )
            )
        return result

    def _install_mcp(
        self,
        definition: MarketplaceDefinition,
        configuration: Mapping[str, Any],
    ) -> dict[str, Any]:
        value = dict(definition.install or {})
        if configuration.get("endpoint"):
            value["endpoint"] = str(configuration["endpoint"]).strip()
        environment_name = str(configuration.get("token_environment") or "").strip()
        if environment_name:
            header_env = dict(value.get("header_env") or {})
            if len(header_env) != 1:
                raise ToolMarketplaceError("invalid_configuration", "This item does not accept one token environment")
            value["header_env"] = {next(iter(header_env)): environment_name}
        if not str(value.get("endpoint") or "").strip():
            raise ToolMarketplaceError("configuration_required", "This MCP requires a server endpoint")
        installed = self._mcp().upsert(value)
        return {"contract": CONTRACT, "changed": True, "installed": installed, "item": self._item(definition.id)}

    def _install_automation(self, definition: MarketplaceDefinition) -> dict[str, Any]:
        value = dict(definition.install or {})
        installed = self._proactive().create(
            task_id=str(value["task_id"]),
            name=str(value["name"]),
            trigger=dict(value["trigger"]),
            action=dict(value["action"]),
            policy=dict(value.get("policy") or {}),
            enabled=True,
        )
        return {"contract": CONTRACT, "changed": True, "installed": installed, "item": self._item(definition.id)}

    def _missing_mcp_configuration(
        self,
        install: Mapping[str, Any],
        connection: Mapping[str, Any] | None,
    ) -> list[str]:
        if connection is None:
            return []
        missing: list[str] = []
        if not str(connection.get("endpoint") or install.get("endpoint") or ""):
            missing.append("endpoint")
        for environment_name in dict(
            connection.get("header_env") or install.get("header_env") or {}
        ).values():
            if not str(self.environment.get(str(environment_name)) or ""):
                missing.append(str(environment_name))
        return missing

    def _item(self, item_id: str) -> dict[str, Any]:
        return next(
            (item for item in self.catalog()["items"] if item["id"] == str(item_id)),
            {},
        )

    def _definition(self, item_id: str) -> MarketplaceDefinition:
        normalized = str(item_id or "").strip()
        for definition in MCP_CATALOG + AUTOMATION_CATALOG:
            if definition.id == normalized:
                return definition
        native = next(
            (item for item in self._native_items() if item["id"] == normalized),
            None,
        )
        if native:
            return MarketplaceDefinition(
                id=native["id"],
                kind=NATIVE_TOOL,
                name=native["name"],
                summary=native["summary"],
                version=native["version"],
            )
        raise ToolMarketplaceError("item_not_found", "Marketplace item was not found")

    def _native_provider(self) -> Callable[[], Mapping[str, Any]]:
        if self._native_manifest is None:
            from desktop_native_tools import desktop_native_tool_registry

            self._native_manifest = desktop_native_tool_registry().manifest
        return self._native_manifest

    def _mcp(self):
        if self._mcp_registry is None:
            from desktop_mcp import desktop_mcp_registry

            self._mcp_registry = desktop_mcp_registry()
        return self._mcp_registry

    def _skills(self):
        if self._skill_registry is None:
            from desktop_skills import desktop_skill_registry

            self._skill_registry = desktop_skill_registry()
        return self._skill_registry

    def _proactive(self):
        if self._proactive_runtime is None:
            from proactive_dispatcher import proactive_task_runtime

            self._proactive_runtime = proactive_task_runtime()
        return self._proactive_runtime


_MARKETPLACE: ToolMarketplace | None = None
_MARKETPLACE_LOCK = threading.Lock()


def tool_marketplace() -> ToolMarketplace:
    global _MARKETPLACE
    with _MARKETPLACE_LOCK:
        if _MARKETPLACE is None:
            _MARKETPLACE = ToolMarketplace()
        return _MARKETPLACE
