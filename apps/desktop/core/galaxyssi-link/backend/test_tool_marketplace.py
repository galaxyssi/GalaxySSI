from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest

from tool_marketplace import ToolMarketplace, ToolMarketplaceError
from tool_marketplace_lifecycle import MarketplaceLifecycleStore


class FakeMcpRegistry:
    def __init__(self) -> None:
        self.rows: dict[str, dict] = {}

    def list(self, include_configuration: bool = False):
        return [dict(value) for value in self.rows.values()]

    def upsert(self, value):
        row = {
            **dict(value),
            "enabled": bool(value.get("enabled", True)),
            "state": "configured",
            "last_error": "",
        }
        self.rows[row["id"]] = row
        return dict(row)

    def delete(self, connection_id):
        return self.rows.pop(connection_id, None) is not None


class FakeSkillRegistry:
    def list(self):
        return [
            {
                "id": "galaxyssi.code-work",
                "name": "Code work",
                "description": "Build and verify projects.",
                "source": "builtin",
                "enabled": True,
            },
            {
                "id": "user.release",
                "name": "Release",
                "description": "Prepare a release.",
                "source": "user",
                "enabled": False,
            },
        ]


class FakeProactiveStore:
    def __init__(self) -> None:
        self.rows: dict[str, SimpleNamespace] = {}

    def tasks(self, limit=1_000):
        return list(self.rows.values())[:limit]


class FakeProactiveRuntime:
    def __init__(self) -> None:
        self.store = FakeProactiveStore()

    def create(self, **value):
        task = SimpleNamespace(
            task_id=value["task_id"],
            enabled=bool(value.get("enabled", True)),
            public=lambda: {
                "task_id": value["task_id"],
                "name": value["name"],
                "trigger": dict(value["trigger"]),
                "action": dict(value["action"]),
                "policy": dict(value.get("policy") or {}),
                "enabled": bool(value.get("enabled", True)),
            },
        )
        self.store.rows[task.task_id] = task
        return {"task_id": task.task_id, "enabled": task.enabled}

    def delete(self, task_id):
        return self.store.rows.pop(task_id, None) is not None

    def update(self, task_id, *, enabled=None):
        task = self.store.rows[task_id]
        if enabled is not None:
            task.enabled = bool(enabled)
        return task.public()


def native_manifest():
    return {
        "tools": [
            {
                "id": "galaxyssi.desktop.status",
                "version": "1.0.0",
                "title": "Desktop status",
                "description": "Read bounded Desktop status.",
                "capabilities": ["desktop.status.read"],
                "required_permissions": [],
                "required_consents": [],
                "availability": {"status": "available", "reason": ""},
            },
            {
                "id": "galaxyssi.desktop.office",
                "version": "1.0.0",
                "title": "Office conversion",
                "description": "Convert trusted Office files.",
                "capabilities": ["desktop.office.convert"],
                "required_permissions": [],
                "required_consents": [],
                "availability": {
                    "status": "requires_setup",
                    "reason": "Microsoft Office is required",
                },
            },
        ]
    }


class ToolMarketplaceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mcp = FakeMcpRegistry()
        self.skills = FakeSkillRegistry()
        self.proactive = FakeProactiveRuntime()
        self.lifecycle = MarketplaceLifecycleStore(Path(self.temp.name) / "lifecycle.json")
        self.marketplace = ToolMarketplace(
            native_manifest=native_manifest,
            mcp_registry=self.mcp,
            skill_registry=self.skills,
            proactive_runtime=self.proactive,
            environment={},
            lifecycle_store=self.lifecycle,
        )

    def approved(self, item_id: str) -> list[str]:
        item = next(
            item
            for item in self.marketplace.catalog()["items"]
            if item["id"] == item_id
        )
        return [
            permission["id"]
            for permission in item["permission_diff"]["added"]
        ]

    def test_catalog_unifies_native_mcp_and_automation_items(self):
        catalog = self.marketplace.catalog()
        kinds = {item["kind"] for item in catalog["items"]}

        self.assertEqual({"native_tool", "mcp", "automation"}, kinds)
        self.assertEqual(
            "built_in",
            next(
                item["install_state"]
                for item in catalog["items"]
                if item["id"] == "galaxyssi.desktop.status"
            ),
        )
        self.assertEqual(
            "needs_setup",
            next(
                item["install_state"]
                for item in catalog["items"]
                if item["id"] == "galaxyssi.desktop.office"
            ),
        )
        self.assertGreaterEqual(catalog["summary"]["installed"], 2)

    def test_mcp_install_uses_environment_references_without_secret_values(self):
        result = self.marketplace.install(
            "galaxyssi.mcp.github",
            approved_permissions=self.approved("galaxyssi.mcp.github"),
        )

        self.assertTrue(result["changed"])
        self.assertEqual(
            {"Authorization": "GALAXYSSI_GITHUB_TOKEN"},
            self.mcp.rows["marketplace.github"]["header_env"],
        )
        self.assertNotIn("credentials", self.mcp.rows["marketplace.github"])
        self.assertEqual("needs_setup", result["item"]["install_state"])

    def test_mcp_becomes_installed_when_required_environment_is_available(self):
        marketplace = ToolMarketplace(
            native_manifest=native_manifest,
            mcp_registry=self.mcp,
            skill_registry=self.skills,
            proactive_runtime=self.proactive,
            environment={"GALAXYSSI_GITHUB_TOKEN": "configured"},
            lifecycle_store=self.lifecycle,
        )

        permissions = [
            permission["id"]
            for permission in next(
                item
                for item in marketplace.catalog()["items"]
                if item["id"] == "galaxyssi.mcp.github"
            )["permission_diff"]["added"]
        ]
        result = marketplace.install(
            "galaxyssi.mcp.github",
            approved_permissions=permissions,
        )

        self.assertEqual("installed", result["item"]["install_state"])

    def test_endpoint_backed_mcp_requires_explicit_setup(self):
        with self.assertRaises(ToolMarketplaceError) as raised:
            self.marketplace.install(
                "galaxyssi.mcp.home_assistant",
                approved_permissions=self.approved("galaxyssi.mcp.home_assistant"),
            )
        self.assertEqual("configuration_required", raised.exception.code)

        result = self.marketplace.install(
            "galaxyssi.mcp.home_assistant",
            {"endpoint": "https://home.example/mcp"},
            self.approved("galaxyssi.mcp.home_assistant"),
        )
        self.assertEqual("needs_setup", result["item"]["install_state"])

    def test_automation_install_and_uninstall_use_durable_task_runtime(self):
        installed = self.marketplace.install(
            "galaxyssi.automation.desktop-health",
            approved_permissions=self.approved("galaxyssi.automation.desktop-health"),
        )
        self.assertEqual("installed", installed["item"]["install_state"])
        self.assertIn(
            "marketplace.desktop-health",
            self.proactive.store.rows,
        )

        removed = self.marketplace.uninstall(
            "galaxyssi.automation.desktop-health"
        )
        self.assertTrue(removed["changed"])
        self.assertEqual("available", removed["item"]["install_state"])
        self.assertTrue(removed["item"]["rollback_available"])

        restored = self.marketplace.rollback("galaxyssi.automation.desktop-health")
        self.assertTrue(restored["changed"])
        self.assertEqual("installed", restored["item"]["install_state"])

    def test_install_requires_explicit_new_permission_approval(self):
        with self.assertRaises(ToolMarketplaceError) as raised:
            self.marketplace.install("galaxyssi.mcp.github")

        self.assertEqual("permission_confirmation_required", raised.exception.code)
        self.assertEqual(
            {"network.github", "repositories.read", "repositories.write"},
            {
                permission["id"]
                for permission in raised.exception.details["permissions"]
            },
        )

    def test_revoke_preserves_configuration_and_install_restores_access(self):
        item_id = "galaxyssi.mcp.github"
        self.marketplace.install(
            item_id,
            approved_permissions=self.approved(item_id),
        )

        revoked = self.marketplace.revoke(item_id)
        self.assertTrue(revoked["item"]["revoked"])
        self.assertFalse(self.mcp.rows["marketplace.github"]["enabled"])

        restored = self.marketplace.install(item_id)
        self.assertFalse(restored["item"]["revoked"])
        self.assertTrue(self.mcp.rows["marketplace.github"]["enabled"])

    def test_catalog_reports_version_and_permission_diff(self):
        item_id = "galaxyssi.mcp.github"
        configuration = {
            "id": "marketplace.github",
            "name": "GitHub",
            "transport": "streamable_http",
            "endpoint": "https://api.githubcopilot.com/mcp/",
            "enabled": True,
        }
        self.mcp.upsert(configuration)
        self.lifecycle.ensure_active(
            item_id,
            version="0.9.0",
            permissions=["network.github", "repositories.read"],
            capabilities=["repositories.read"],
            snapshot={"configuration": configuration},
        )

        item = next(
            item
            for item in self.marketplace.catalog()["items"]
            if item["id"] == item_id
        )

        self.assertTrue(item["update_available"])
        self.assertEqual("0.9.0", item["installed_version"])
        self.assertEqual(
            ["repositories.write"],
            [permission["id"] for permission in item["permission_diff"]["added"]],
        )

    def test_lifecycle_receipts_reject_embedded_secret_values(self):
        with self.assertRaises(ValueError):
            self.lifecycle.activate(
                "galaxyssi.mcp.unsafe",
                version="1.0.0",
                permissions=["network"],
                capabilities=["query"],
                snapshot={
                    "configuration": {
                        "endpoint": "https://example.test/mcp",
                        "access_token": "must-not-be-stored",
                    }
                },
            )

    def test_built_in_tools_fail_closed_for_uninstall(self):
        with self.assertRaises(ToolMarketplaceError) as raised:
            self.marketplace.uninstall("galaxyssi.desktop.status")
        self.assertEqual("built_in", raised.exception.code)


if __name__ == "__main__":
    unittest.main()
