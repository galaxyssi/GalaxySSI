"""Unified trusted catalog for native tools, MCP, and automation templates."""
from __future__ import annotations

import hashlib
import json
import os
import threading
from dataclasses import dataclass
from typing import Any, Callable, Mapping

from tool_marketplace_lifecycle import MarketplaceLifecycleStore


CONTRACT = "galaxyssi.tool-marketplace/1.1"
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
    def __init__(
        self,
        code: str,
        message: str,
        details: Mapping[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.details = dict(details or {})


@dataclass(frozen=True)
class MarketplacePermission:
    id: str
    title: str
    description: str
    scope: str = "item"
    risk: str = "medium"

    def public(self) -> dict[str, str]:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "scope": self.scope,
            "risk": self.risk,
        }


@dataclass(frozen=True)
class MarketplaceDefinition:
    id: str
    kind: str
    name: str
    summary: str
    version: str = "1.0.0"
    publisher: str = "GalaxySSI"
    tags: tuple[str, ...] = ()
    dependencies: tuple[str, ...] = ()
    capabilities: tuple[str, ...] = ()
    permissions: tuple[MarketplacePermission, ...] = ()
    release_notes: str = ""
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
            "capabilities": list(self.capabilities),
            "permissions": [permission.public() for permission in self.permissions],
            "release_notes": self.release_notes,
            "featured": self.featured,
            "trusted": self.trusted,
            "install_state": state,
            "enabled": bool(enabled),
            "installed_ref": installed_ref,
            "status_detail": status_detail,
        }


def permission(
    permission_id: str,
    title: str,
    description: str,
    *,
    scope: str = "item",
    risk: str = "medium",
) -> MarketplacePermission:
    return MarketplacePermission(permission_id, title, description, scope, risk)


MCP_CATALOG = (
    MarketplaceDefinition(
        id="galaxyssi.mcp.github",
        kind=MCP,
        name="GitHub",
        summary="Repositories, issues, pull requests, and code workflows.",
        tags=("development", "source-control"),
        dependencies=("GALAXYSSI_GITHUB_TOKEN",),
        capabilities=("repositories.read", "repositories.write", "pull_requests.manage"),
        permissions=(
            permission("network.github", "Connect to GitHub", "Send requests to the configured GitHub MCP endpoint.", risk="low"),
            permission("repositories.read", "Read repositories", "Read repository content, issues, and pull requests."),
            permission("repositories.write", "Change repositories", "Create or update repository content and pull requests.", risk="high"),
        ),
        release_notes="Initial signed GitHub MCP catalog release.",
        install={
            "id": "marketplace.github",
            "name": "GitHub",
            "transport": "streamable_http",
            "endpoint": "https://api.githubcopilot.com/mcp/",
            "header_env": {"Authorization": "GALAXYSSI_GITHUB_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["github", "repository", "pull request", "issue"],
            "permission_mode": "ask_for_changes",
            "import_source": "galaxyssi_marketplace",
        },
    ),
    MarketplaceDefinition(
        id="galaxyssi.mcp.notion",
        kind=MCP,
        name="Notion",
        summary="Search, read, and update a trusted Notion workspace.",
        tags=("knowledge", "documents"),
        dependencies=("GALAXYSSI_NOTION_TOKEN",),
        capabilities=("workspace.search", "pages.read", "pages.write"),
        permissions=(
            permission("network.notion", "Connect to Notion", "Send requests to the configured Notion MCP endpoint.", risk="low"),
            permission("workspace.read", "Read workspace", "Search and read pages shared with the integration."),
            permission("workspace.write", "Change workspace", "Create or update pages shared with the integration.", risk="high"),
        ),
        release_notes="Initial signed Notion MCP catalog release.",
        install={
            "id": "marketplace.notion",
            "name": "Notion",
            "transport": "streamable_http",
            "endpoint": "https://mcp.notion.com/mcp",
            "header_env": {"Authorization": "GALAXYSSI_NOTION_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["notion", "workspace page"],
            "permission_mode": "ask_for_changes",
            "import_source": "galaxyssi_marketplace",
        },
    ),
    MarketplaceDefinition(
        id="galaxyssi.mcp.home_assistant",
        kind=MCP,
        name="Home Assistant",
        summary="Read and control trusted smart-home entities and automations.",
        tags=("smart-home", "automation"),
        dependencies=("endpoint", "GALAXYSSI_HOME_ASSISTANT_TOKEN"),
        capabilities=("entities.read", "services.call", "automations.run"),
        permissions=(
            permission("network.home_assistant", "Connect to Home Assistant", "Connect to the user-provided Home Assistant endpoint.", risk="low"),
            permission("smart_home.read", "Read smart-home state", "Read exposed entities and automation state."),
            permission("smart_home.control", "Control smart-home devices", "Call services and run exposed automations.", risk="high"),
        ),
        release_notes="Initial signed Home Assistant MCP catalog release.",
        install={
            "id": "marketplace.home-assistant",
            "name": "Home Assistant",
            "transport": "streamable_http",
            "endpoint": "",
            "header_env": {"Authorization": "GALAXYSSI_HOME_ASSISTANT_TOKEN"},
            "header_templates": {"Authorization": "Bearer {value}"},
            "triggers": ["home assistant", "smart home"],
            "permission_mode": "ask_for_changes",
            "import_source": "galaxyssi_marketplace",
        },
    ),
)


AUTOMATION_CATALOG = (
    MarketplaceDefinition(
        id="galaxyssi.automation.desktop-health",
        kind=AUTOMATION,
        name="Desktop health check",
        summary="Check Desktop runtime health every hour and retain a verified result.",
        tags=("health", "runtime"),
        dependencies=("galaxyssi.desktop.runtime.status",),
        capabilities=("desktop.status.read", "automation.schedule"),
        permissions=(
            permission("desktop.status.read", "Read Desktop status", "Read local GalaxySSI runtime health.", risk="low"),
            permission("automation.schedule", "Run on a schedule", "Run this automation every hour.", risk="low"),
        ),
        release_notes="Initial health-check automation template.",
        install={
            "task_id": "marketplace.desktop-health",
            "name": "Desktop health check",
            "trigger": {"kind": "interval", "interval_seconds": 3600, "time_zone": "UTC"},
            "action": {
                "kind": "native_tool",
                "target_id": "galaxyssi.desktop.runtime.status",
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
        id="galaxyssi.automation.morning-brief",
        kind=AUTOMATION,
        name="Morning brief",
        summary="Ask an available research Agent for a concise daily brief.",
        tags=("research", "daily"),
        dependencies=("agent:hermes",),
        capabilities=("agent.hermes.execute", "web.research", "notifications.write"),
        permissions=(
            permission("agent.hermes.execute", "Run Hermes", "Send the brief task to the configured Hermes Agent."),
            permission("network.web", "Access current web sources", "Retrieve current evidence for the brief."),
            permission("notifications.write", "Send a notification", "Deliver the completed brief to an authorized phone."),
        ),
        release_notes="Initial morning-brief automation template.",
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
        id="galaxyssi.automation.weekly-project-review",
        kind=AUTOMATION,
        name="Weekly project review",
        summary="Review the active project and report verified progress once a week.",
        tags=("project", "development"),
        dependencies=("agent:codex",),
        capabilities=("agent.codex.execute", "workspace.read", "automation.schedule"),
        permissions=(
            permission("agent.codex.execute", "Run Codex", "Send the project review task to the configured Codex Agent."),
            permission("workspace.read", "Read active project", "Read files in the selected project workspace."),
            permission("automation.schedule", "Run on a schedule", "Run this review once a week.", risk="low"),
        ),
        release_notes="Initial weekly project-review automation template.",
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
        lifecycle_store: MarketplaceLifecycleStore | None = None,
    ) -> None:
        self._native_manifest = native_manifest
        self._mcp_registry = mcp_registry
        self._skill_registry = skill_registry
        self._proactive_runtime = proactive_runtime
        self.environment = environment if environment is not None else os.environ
        self.lifecycle = lifecycle_store or MarketplaceLifecycleStore()

    def catalog(self, kind: str = "") -> dict[str, Any]:
        normalized_kind = str(kind or "").strip().casefold()
        if normalized_kind and normalized_kind not in {NATIVE_TOOL, MCP, AUTOMATION}:
            raise ToolMarketplaceError("invalid_kind", "Marketplace kind is invalid")
        items = [
            self._with_lifecycle(item)
            for item in self._native_items() + self._mcp_items() + self._automation_items()
        ]
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
        approved_permissions: list[str] | None = None,
    ) -> dict[str, Any]:
        definition = self._definition(item_id)
        current_item = self._item(item_id)
        self._require_permission_approval(current_item, approved_permissions or [])
        if definition.kind == NATIVE_TOOL:
            if current_item["install_state"] == "unavailable":
                raise ToolMarketplaceError("tool_unavailable", "This native tool is unavailable")
            return {"contract": CONTRACT, "changed": False, "item": current_item}
        current_snapshot = self._current_snapshot(definition)
        self._seed_lifecycle(definition, current_item, current_snapshot)
        if definition.kind == MCP:
            result = self._install_mcp(definition, configuration or {})
        elif definition.kind == AUTOMATION:
            result = self._install_automation(definition)
        else:
            raise ToolMarketplaceError("unsupported_kind", "Marketplace item kind is unsupported")
        self.lifecycle.activate(
            definition.id,
            version=definition.version,
            permissions=self._permission_ids(definition),
            capabilities=list(definition.capabilities),
            snapshot=self._current_snapshot(definition),
        )
        return {
            **result,
            "contract": CONTRACT,
            "item": self._item(definition.id),
        }

    def uninstall(self, item_id: str) -> dict[str, Any]:
        definition = self._definition(item_id)
        if definition.kind == NATIVE_TOOL:
            raise ToolMarketplaceError("built_in", "Built-in tools cannot be uninstalled")
        current_item = self._item(item_id)
        current_snapshot = self._current_snapshot(definition)
        self._seed_lifecycle(definition, current_item, current_snapshot)
        if definition.kind == MCP:
            registry = self._mcp()
            ref = str((definition.install or {}).get("id") or "")
            changed = bool(registry.delete(ref))
        else:
            runtime = self._proactive()
            ref = str((definition.install or {}).get("task_id") or "")
            changed = bool(runtime.delete(ref))
        if changed or self.lifecycle.record(item_id).get("active"):
            self.lifecycle.uninstall(item_id)
        return {"contract": CONTRACT, "changed": changed, "item": self._item(item_id)}

    def revoke(self, item_id: str) -> dict[str, Any]:
        definition = self._definition(item_id)
        if definition.kind == NATIVE_TOOL:
            raise ToolMarketplaceError("built_in", "Built-in tool access is controlled by its system permissions")
        current_item = self._item(item_id)
        current_snapshot = self._current_snapshot(definition)
        if not current_snapshot:
            raise ToolMarketplaceError("not_installed", "Marketplace item is not installed")
        self._seed_lifecycle(definition, current_item, current_snapshot)
        if definition.kind == MCP:
            value = dict(current_snapshot["configuration"])
            value["enabled"] = False
            self._mcp().upsert(value)
        else:
            ref = str((definition.install or {}).get("task_id") or "")
            self._proactive().update(ref, enabled=False)
        self.lifecycle.revoke(item_id)
        return {"contract": CONTRACT, "changed": True, "item": self._item(item_id)}

    def rollback(self, item_id: str) -> dict[str, Any]:
        definition = self._definition(item_id)
        if definition.kind == NATIVE_TOOL:
            raise ToolMarketplaceError("built_in", "Built-in tools follow the Desktop release lifecycle")
        candidate = self.lifecycle.rollback_candidate(item_id)
        if not candidate:
            raise ToolMarketplaceError("rollback_unavailable", "No rollback version is available")
        snapshot = dict(candidate.get("snapshot") or {})
        try:
            if definition.kind == MCP:
                configuration = dict(snapshot.get("configuration") or {})
                if not configuration:
                    raise ValueError("MCP rollback snapshot is incomplete")
                self._mcp().upsert(configuration)
            else:
                task = dict(snapshot.get("task") or {})
                if not task:
                    raise ValueError("Automation rollback snapshot is incomplete")
                self._restore_automation(task)
        except (RuntimeError, ValueError) as exc:
            raise ToolMarketplaceError(
                "rollback_failed",
                f"Rollback could not restore the previous release: {exc}",
            ) from exc
        record = self.lifecycle.commit_rollback(item_id)
        return {
            "contract": CONTRACT,
            "changed": True,
            "restored_version": str((record.get("active") or {}).get("version") or ""),
            "item": self._item(item_id),
        }

    def _native_items(self) -> list[dict[str, Any]]:
        manifest = dict(self._native_provider()())
        result: list[dict[str, Any]] = []
        for tool in list(manifest.get("tools") or []):
            availability = dict(tool.get("availability") or {})
            availability_state = str(availability.get("status") or "unavailable")
            permission_values = [
                value
                for value in list(tool.get("required_permissions") or [])
                + list(tool.get("required_consents") or [])
                if isinstance(value, Mapping) and str(value.get("id") or "")
            ]
            state = {
                "available": "built_in",
                "requires_setup": "needs_setup",
            }.get(availability_state, "unavailable")
            definition = MarketplaceDefinition(
                id=str(tool.get("id") or ""),
                kind=NATIVE_TOOL,
                name=str(tool.get("title") or tool.get("id") or "Native tool"),
                summary=str(tool.get("description") or "GalaxySSI native capability"),
                version=str(tool.get("version") or "1.0.0"),
                tags=tuple(str(value) for value in list(tool.get("capabilities") or [])),
                capabilities=tuple(str(value) for value in list(tool.get("capabilities") or [])),
                dependencies=tuple(
                    str(value.get("id") or "")
                    for value in permission_values
                ),
                permissions=tuple(
                    permission(
                        str(value.get("id") or ""),
                        str(value.get("title") or value.get("id") or "Permission"),
                        str(value.get("description") or "Required by this native tool."),
                        scope="native_tool",
                        risk=str(tool.get("risk") or "medium"),
                    )
                    for value in permission_values
                ),
                release_notes="Delivered and updated with the signed GalaxySSI Desktop release.",
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
                publisher="GalaxySSI" if skill.get("source") == "builtin" else "Local user",
                tags=("skill", "workflow"),
                capabilities=tuple(
                    str(value)
                    for value in list(skill.get("capabilities") or skill.get("triggers") or [])
                    if str(value)
                ),
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

    def _with_lifecycle(self, item: Mapping[str, Any]) -> dict[str, Any]:
        value = dict(item)
        item_id = str(value.get("id") or "")
        try:
            record = self.lifecycle.record(item_id)
        except ValueError:
            record = {
                "active": None,
                "history": [],
                "revoked": False,
                "revision": 0,
            }
        active = dict(record.get("active") or {})
        installed = str(value.get("install_state") or "") in {
            "built_in",
            "installed",
            "needs_setup",
        }
        available_permissions = {
            str(permission_value.get("id") or ""): dict(permission_value)
            for permission_value in list(value.get("permissions") or [])
            if isinstance(permission_value, Mapping) and str(permission_value.get("id") or "")
        }
        current_permissions = set(
            str(permission_id)
            for permission_id in list(active.get("permissions") or [])
            if str(permission_id)
        )
        if installed and not active:
            current_permissions = set(available_permissions)
        added = sorted(set(available_permissions) - current_permissions)
        removed = sorted(current_permissions - set(available_permissions))
        unchanged = sorted(current_permissions & set(available_permissions))
        rollback_versions = [
            str(release.get("version") or "")
            for release in list(record.get("history") or [])
            if isinstance(release, Mapping) and str(release.get("version") or "")
        ]
        installed_version = str(active.get("version") or "") if installed else ""
        if installed and not installed_version:
            installed_version = str(value.get("version") or "")
        value.update(
            {
                "available_version": str(value.get("version") or ""),
                "installed_version": installed_version,
                "update_available": bool(
                    installed_version
                    and self._compare_versions(str(value.get("version") or ""), installed_version) > 0
                ),
                "capability_manifest_digest": self._manifest_digest(value),
                "permission_diff": {
                    "added": [available_permissions[permission_id] for permission_id in added],
                    "removed": [{"id": permission_id, "title": permission_id} for permission_id in removed],
                    "unchanged": [available_permissions[permission_id] for permission_id in unchanged],
                    "requires_approval": bool(added),
                },
                "rollback_versions": rollback_versions,
                "rollback_available": bool(rollback_versions),
                "revocable": bool(
                    value.get("kind") in {MCP, AUTOMATION}
                    and self._is_managed_definition(item_id)
                    and installed
                ),
                "revoked": bool(record.get("revoked")),
                "lifecycle_revision": int(record.get("revision") or 0),
            }
        )
        return value

    def _require_permission_approval(
        self,
        item: Mapping[str, Any],
        approved_permissions: list[str],
    ) -> None:
        diff = dict(item.get("permission_diff") or {})
        added = [
            dict(value)
            for value in list(diff.get("added") or [])
            if isinstance(value, Mapping) and str(value.get("id") or "")
        ]
        approved = {str(value) for value in approved_permissions}
        missing = [value for value in added if str(value["id"]) not in approved]
        if missing:
            raise ToolMarketplaceError(
                "permission_confirmation_required",
                "Review and approve the new permissions before installing this release",
                {
                    "item_id": str(item.get("id") or ""),
                    "permissions": missing,
                    "installed_version": str(item.get("installed_version") or ""),
                    "available_version": str(item.get("available_version") or ""),
                },
            )

    def _seed_lifecycle(
        self,
        definition: MarketplaceDefinition,
        item: Mapping[str, Any],
        snapshot: Mapping[str, Any],
    ) -> None:
        if not snapshot or self.lifecycle.record(definition.id).get("active"):
            return
        self.lifecycle.ensure_active(
            definition.id,
            version=str(item.get("installed_version") or definition.version),
            permissions=[
                str(value.get("id") or "")
                for value in list(item.get("permissions") or [])
                if isinstance(value, Mapping) and str(value.get("id") or "")
            ],
            capabilities=[
                str(value)
                for value in list(item.get("capabilities") or [])
                if str(value)
            ],
            snapshot=snapshot,
        )

    def _current_snapshot(self, definition: MarketplaceDefinition) -> dict[str, Any]:
        if definition.kind == MCP:
            ref = str((definition.install or {}).get("id") or "")
            connection = next(
                (
                    dict(value)
                    for value in self._mcp().list(include_configuration=True)
                    if str(value.get("id") or "") == ref
                ),
                None,
            )
            return {"configuration": self._mcp_configuration_snapshot(connection)} if connection else {}
        if definition.kind == AUTOMATION:
            ref = str((definition.install or {}).get("task_id") or "")
            task = next(
                (
                    task_value
                    for task_value in self._proactive().store.tasks(limit=1_000)
                    if str(getattr(task_value, "task_id", "")) == ref
                ),
                None,
            )
            if task is None:
                return {}
            raw_public = task.public() if callable(getattr(task, "public", None)) else {}
            if raw_public:
                public = {
                    "task_id": str(raw_public.get("task_id") or ref),
                    "name": str(raw_public.get("name") or ""),
                    "trigger": dict(raw_public.get("trigger") or {}),
                    "action": dict(raw_public.get("action") or {}),
                    "policy": dict(raw_public.get("policy") or {}),
                    "enabled": bool(raw_public.get("enabled", True)),
                }
            else:
                install = dict(definition.install or {})
                public = {
                    "task_id": ref,
                    "name": str(install.get("name") or ""),
                    "trigger": dict(install.get("trigger") or {}),
                    "action": dict(install.get("action") or {}),
                    "policy": dict(install.get("policy") or {}),
                    "enabled": bool(getattr(task, "enabled", True)),
                }
            return {"task": public}
        return {}

    @staticmethod
    def _mcp_configuration_snapshot(
        connection: Mapping[str, Any] | None,
    ) -> dict[str, Any]:
        if not connection:
            return {}
        allowed = {
            "id",
            "name",
            "transport",
            "command",
            "command_argv",
            "environment_env",
            "endpoint",
            "working_directory",
            "header_env",
            "header_templates",
            "protocol_version",
            "stdio_framing",
            "allow_insecure_http",
            "default_tool",
            "triggers",
            "enabled",
            "auto_invoke",
            "permission_mode",
            "timeout_seconds",
            "import_source",
        }
        return {key: value for key, value in connection.items() if key in allowed}

    def _restore_automation(self, task: Mapping[str, Any]) -> None:
        runtime = self._proactive()
        task_id = str(task.get("task_id") or "")
        if not task_id:
            raise ValueError("Automation rollback snapshot has no task id")
        runtime.delete(task_id)
        runtime.create(
            task_id=task_id,
            name=str(task.get("name") or task_id),
            trigger=dict(task.get("trigger") or {}),
            action=dict(task.get("action") or {}),
            policy=dict(task.get("policy") or {}),
            enabled=bool(task.get("enabled", True)),
        )

    @staticmethod
    def _permission_ids(definition: MarketplaceDefinition) -> list[str]:
        return [permission_value.id for permission_value in definition.permissions]

    @staticmethod
    def _compare_versions(left: str, right: str) -> int:
        def parts(value: str) -> tuple[int, ...]:
            values = []
            for part in str(value).split(".")[:4]:
                digits = "".join(character for character in part if character.isdigit())
                values.append(int(digits or 0))
            return tuple((values + [0, 0, 0, 0])[:4])

        return (parts(left) > parts(right)) - (parts(left) < parts(right))

    @staticmethod
    def _manifest_digest(item: Mapping[str, Any]) -> str:
        value = {
            "id": item.get("id"),
            "kind": item.get("kind"),
            "version": item.get("version"),
            "capabilities": item.get("capabilities"),
            "permissions": item.get("permissions"),
            "dependencies": item.get("dependencies"),
        }
        return hashlib.sha256(
            json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    @staticmethod
    def _is_managed_definition(item_id: str) -> bool:
        return any(
            definition.id == str(item_id)
            for definition in MCP_CATALOG + AUTOMATION_CATALOG
        )

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
