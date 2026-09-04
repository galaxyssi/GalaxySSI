from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from mcp_security import (
    McpAuditStore,
    assess_mcp_tool,
    decide_mcp_permission,
    new_audit_record,
    sanitize_mcp_parameters,
    sanitize_mcp_text,
)


class McpSecurityTest(unittest.TestCase):
    def test_assessment_uses_annotations_names_and_actual_arguments(self):
        read = assess_mcp_tool(
            {"name": "get_weather", "annotations": {"readOnlyHint": True}},
            {"city": "Shanghai"},
            transport="https",
        )
        self.assertEqual(read.risk, "low")
        self.assertIn("mcp.network.connect", read.permissions)

        destructive = assess_mcp_tool(
            {"name": "delete_project", "annotations": {"destructiveHint": True}},
            {"project_path": "C:/work", "api_token": "top-secret"},
            transport="stdio",
        )
        self.assertEqual(destructive.risk, "high")
        self.assertIn("mcp.files.access", destructive.permissions)
        self.assertIn("mcp.secrets.use", destructive.permissions)
        self.assertEqual(destructive.parameter_preview["api_token"], "[REDACTED]")

    def test_permission_matrix_allows_enabled_connections_without_internal_approval(self):
        high = assess_mcp_tool(
            {"name": "delete_account", "annotations": {"destructiveHint": True}},
            {},
            transport="stdio",
        )
        self.assertTrue(decide_mcp_permission("ask_for_changes", high, explicit_user_selection=False).allowed)
        self.assertTrue(decide_mcp_permission("ask_for_changes", high, explicit_user_selection=True).allowed)
        self.assertTrue(decide_mcp_permission("trusted", high, explicit_user_selection=False).allowed)
        self.assertTrue(decide_mcp_permission("trusted", high, explicit_user_selection=True).allowed)
        self.assertFalse(decide_mcp_permission("disabled", high, explicit_user_selection=True).allowed)

    def test_parameter_redaction_removes_nested_and_inline_secrets(self):
        value = sanitize_mcp_parameters({
            "password": "secret-value",
            "nested": {
                "authorization": "Bearer abcdefghijklmnop",
                "url": "https://example.test/action?token=secret#fragment",
                "note": "token=inline-secret",
            },
        })
        serialized = json.dumps(value)
        self.assertNotIn("secret-value", serialized)
        self.assertNotIn("abcdefghijklmnop", serialized)
        self.assertNotIn("inline-secret", serialized)
        self.assertNotIn("fragment", serialized)
        error = sanitize_mcp_text(
            "request failed: token=inline-secret at https://example.test/mcp?api_key=secret"
        )
        self.assertNotIn("inline-secret", error)
        self.assertNotIn("api_key=secret", error)

    def test_audit_store_is_bounded_filterable_and_never_contains_raw_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audit.json"
            store = McpAuditStore(path)
            for index in range(3):
                store.append(new_audit_record(
                    audit_id=f"audit-{index}",
                    timestamp_ms=index + 1,
                    connection_id="one" if index < 2 else "two",
                    connection_name="Connection",
                    tool_name="get_status",
                    transport="stdio",
                    source="desktop-mcp:one",
                    source_sha256="a" * 64,
                    caller_id="test",
                    task_id=f"task-{index}",
                    conversation_id="conversation",
                    risk="low",
                    permissions=("mcp.data.read",),
                    permission_mode="read_only",
                    permission_decision="allowed_read_only",
                    parameter_preview={"token": "[REDACTED]"},
                    input_sha256="b" * 64,
                    status="succeeded",
                    duration_ms=12,
                    output_sha256="c" * 64,
                ))
            self.assertEqual(len(store.list(connection_id="one")), 2)
            self.assertEqual(store.list(limit=1)[0]["audit_id"], "audit-2")
            self.assertNotIn("raw-secret", path.read_text(encoding="utf-8"))
            self.assertEqual(store.clear("one"), 2)
            self.assertEqual(len(store.list()), 1)


if __name__ == "__main__":
    unittest.main()
