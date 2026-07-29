from __future__ import annotations

from types import SimpleNamespace
import unittest

from tool_marketplace import ToolMarketplace, ToolMarketplaceError


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
                "id": "signalasi.code-work",
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
        )
        self.store.rows[task.task_id] = task
        return {"task_id": task.task_id, "enabled": task.enabled}

    def delete(self, task_id):
        return self.store.rows.pop(task_id, None) is not None


def native_manifest():
    return {
        "tools": [
            {
                "id": "signalasi.desktop.status",
                "version": "1.0.0",
                "title": "Desktop status",
                "description": "Read bounded Desktop status.",
                "capabilities": ["desktop.status.read"],
                "required_permissions": [],
                "required_consents": [],
                "availability": {"status": "available", "reason": ""},
            },
            {
                "id": "signalasi.desktop.office",
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
        self.mcp = FakeMcpRegistry()
        self.skills = FakeSkillRegistry()
        self.proactive = FakeProactiveRuntime()
        self.marketplace = ToolMarketplace(
            native_manifest=native_manifest,
            mcp_registry=self.mcp,
            skill_registry=self.skills,
            proactive_runtime=self.proactive,
            environment={},
        )

    def test_catalog_unifies_native_mcp_and_automation_items(self):
        catalog = self.marketplace.catalog()
        kinds = {item["kind"] for item in catalog["items"]}

        self.assertEqual({"native_tool", "mcp", "automation"}, kinds)
        self.assertEqual(
            "built_in",
            next(
                item["install_state"]
                for item in catalog["items"]
                if item["id"] == "signalasi.desktop.status"
            ),
        )
        self.assertEqual(
            "needs_setup",
            next(
                item["install_state"]
                for item in catalog["items"]
                if item["id"] == "signalasi.desktop.office"
            ),
        )
        self.assertGreaterEqual(catalog["summary"]["installed"], 2)

    def test_mcp_install_uses_environment_references_without_secret_values(self):
        result = self.marketplace.install("signalasi.mcp.github")

        self.assertTrue(result["changed"])
        self.assertEqual(
            {"Authorization": "SIGNALASI_GITHUB_TOKEN"},
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
            environment={"SIGNALASI_GITHUB_TOKEN": "configured"},
        )

        result = marketplace.install("signalasi.mcp.github")

        self.assertEqual("installed", result["item"]["install_state"])

    def test_endpoint_backed_mcp_requires_explicit_setup(self):
        with self.assertRaises(ToolMarketplaceError) as raised:
            self.marketplace.install("signalasi.mcp.home_assistant")
        self.assertEqual("configuration_required", raised.exception.code)

        result = self.marketplace.install(
            "signalasi.mcp.home_assistant",
            {"endpoint": "https://home.example/mcp"},
        )
        self.assertEqual("needs_setup", result["item"]["install_state"])

    def test_automation_install_and_uninstall_use_durable_task_runtime(self):
        installed = self.marketplace.install(
            "signalasi.automation.desktop-health"
        )
        self.assertEqual("installed", installed["item"]["install_state"])
        self.assertIn(
            "marketplace.desktop-health",
            self.proactive.store.rows,
        )

        removed = self.marketplace.uninstall(
            "signalasi.automation.desktop-health"
        )
        self.assertTrue(removed["changed"])
        self.assertEqual("available", removed["item"]["install_state"])

    def test_built_in_tools_fail_closed_for_uninstall(self):
        with self.assertRaises(ToolMarketplaceError) as raised:
            self.marketplace.uninstall("signalasi.desktop.status")
        self.assertEqual("built_in", raised.exception.code)


if __name__ == "__main__":
    unittest.main()
