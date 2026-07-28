from __future__ import annotations

import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

from desktop_mcp import DesktopMcpRegistry
from mcp_security import McpAuditStore, McpPermissionDenied


FAKE_SERVER = r'''
import json
import sys

source = sys.stdin.buffer
target = sys.stdout.buffer

def read_message():
    headers = {}
    while True:
        line = source.readline()
        if not line:
            return None
        line = line.decode("ascii").strip()
        if not line:
            break
        key, value = line.split(":", 1)
        headers[key.lower()] = value.strip()
    return json.loads(source.read(int(headers["content-length"])).decode("utf-8"))

def send(value):
    body = json.dumps(value, separators=(",", ":")).encode("utf-8")
    target.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body)
    target.flush()

while True:
    message = read_message()
    if message is None:
        break
    request_id = message.get("id")
    method = message.get("method")
    if request_id is None:
        continue
    if method == "initialize":
        result = {"protocolVersion": "2024-11-05", "capabilities": {}, "serverInfo": {"name": "fake", "version": "1"}}
    elif method == "tools/list":
        result = {"tools": [
            {"name": "relay", "description": "Control a relay", "annotations": {"readOnlyHint": False}, "inputSchema": {"type": "object", "properties": {"prompt": {"type": "string"}}}},
            {"name": "get_status", "description": "Read status", "annotations": {"readOnlyHint": True}, "inputSchema": {"type": "object", "properties": {"prompt": {"type": "string"}}}},
            {"name": "delete_device", "description": "Delete a device", "annotations": {"destructiveHint": True}, "inputSchema": {"type": "object", "properties": {"prompt": {"type": "string"}}}}
        ]}
    elif method == "tools/call":
        prompt = message.get("params", {}).get("arguments", {}).get("prompt", "")
        result = {"content": [{"type": "text", "text": "MCP_OK:" + prompt}]}
    else:
        result = {}
    send({"jsonrpc": "2.0", "id": request_id, "result": result})
'''


class DesktopMcpRegistryTest(unittest.TestCase):
    def test_configured_stdio_server_can_be_probed_matched_and_called(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "fake_mcp.py"
            server.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")
            command = f'"{sys.executable}" "{server}"'
            registry = DesktopMcpRegistry(root / "mcp.json")
            saved = registry.upsert({
                "id": "home-relay",
                "name": "Home Relay",
                "command": command,
                "default_tool": "relay",
                "triggers": ["relay"],
                "auto_invoke": True,
            })

            self.assertTrue(saved["configured"])
            self.assertEqual(registry.match("Turn the relay on").id, "home-relay")
            probe = registry.probe("home-relay")
            self.assertEqual(probe["status"], "ready")
            self.assertEqual(probe["tools"][0]["name"], "relay")
            processes = []
            result = registry.invoke_prompt(
                "home-relay",
                "Turn the relay on",
                process_callback=processes.append,
                explicit_user_selection=True,
                audit_context={"caller_id": "test", "task_id": "task-1"},
            )
            self.assertEqual(result["result"], "MCP_OK:Turn the relay on")
            self.assertEqual(result["security"]["risk"], "medium")
            self.assertEqual(len(processes), 1)
            self.assertIsNotNone(processes[0].poll())
            audit = registry.audit("home-relay")
            self.assertEqual(len(audit), 1)
            self.assertEqual(audit[0]["status"], "succeeded")
            self.assertEqual(audit[0]["task_id"], "task-1")

    def test_read_only_and_high_risk_tools_follow_connection_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "fake_mcp.py"
            server.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")
            registry = DesktopMcpRegistry(
                root / "mcp.json",
                audit_store=McpAuditStore(root / "audit.json"),
            )
            command = f'"{sys.executable}" "{server}"'
            registry.upsert({
                "id": "governed",
                "name": "Governed",
                "command": command,
                "default_tool": "get_status",
                "permission_mode": "read_only",
            })

            read_result = registry.invoke_prompt("governed", "status")
            self.assertEqual(read_result["security"]["risk"], "low")

            registry.upsert({
                "id": "governed",
                "name": "Governed",
                "command": command,
                "default_tool": "relay",
                "permission_mode": "read_only",
            })
            with self.assertRaises(McpPermissionDenied):
                registry.invoke_prompt("governed", "turn on", explicit_user_selection=True)

            registry.upsert({
                "id": "governed",
                "name": "Governed",
                "command": command,
                "default_tool": "delete_device",
                "permission_mode": "trusted",
            })
            with self.assertRaises(McpPermissionDenied):
                registry.invoke_prompt("governed", "delete")
            allowed = registry.invoke_prompt(
                "governed",
                "delete",
                explicit_user_selection=True,
            )
            self.assertEqual(allowed["security"]["risk"], "high")
            self.assertEqual(
                [entry["status"] for entry in registry.audit("governed")],
                ["succeeded", "denied", "denied", "succeeded"],
            )

    def test_permission_mode_persists_and_deleted_connection_clears_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "fake_mcp.py"
            server.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")
            command = f'"{sys.executable}" "{server}"'
            registry = DesktopMcpRegistry(root / "mcp.json")
            registry.upsert({
                "id": "persistent",
                "name": "Persistent",
                "command": command,
                "default_tool": "get_status",
                "permission_mode": "trusted",
            })
            registry.invoke_prompt("persistent", "status")

            reopened = DesktopMcpRegistry(root / "mcp.json")
            self.assertEqual(reopened.list()[0]["permission_mode"], "trusted")
            self.assertEqual(len(reopened.audit("persistent")), 1)
            self.assertTrue(reopened.delete("persistent"))
            self.assertEqual(reopened.audit("persistent"), [])

    def test_trigger_matching_requires_auto_invoke_unless_connection_is_named(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = DesktopMcpRegistry(Path(directory) / "mcp.json")
            registry.upsert({
                "id": "private-tool",
                "name": "Private Tool",
                "command": "python server.py",
                "triggers": ["account"],
                "auto_invoke": False,
            })

            self.assertIsNone(registry.match("Check my account"))
            self.assertEqual(registry.match("Use Private Tool to check my account").id, "private-tool")


if __name__ == "__main__":
    unittest.main()
