from __future__ import annotations

import json
import os
import sys
import tempfile
import textwrap
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from desktop_mcp import DesktopMcpRegistry
from mcp_security import McpAuditStore
from tool_handle_registry import ToolHandleError, ToolHandleRegistry


FAKE_SERVER = r'''
import json
import sys

source = sys.stdin
target = sys.stdout

def read_message():
    line = source.readline()
    return json.loads(line) if line else None

def send(value):
    target.write(json.dumps(value, separators=(",", ":")) + "\n")
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


class FakeStreamableHttpMcp(BaseHTTPRequestHandler):
    mcp_protocol_version = "2025-11-25"
    observations: list[dict] = []

    def log_message(self, _format, *_args):
        return None

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        message = json.loads(self.rfile.read(length).decode("utf-8"))
        self.__class__.observations.append(
            {
                "method": message.get("method"),
                "authorization": self.headers.get("Authorization"),
                "protocol": self.headers.get("MCP-Protocol-Version"),
                "session": self.headers.get("Mcp-Session-Id"),
            }
        )
        method = message.get("method")
        request_id = message.get("id")
        if request_id is None:
            self.send_response(202)
            self.end_headers()
            return
        if method == "initialize":
            result = {
                "protocolVersion": self.mcp_protocol_version,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {
                    "name": "fake-http",
                    "title": "Fake HTTP MCP",
                    "version": "2.1",
                },
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {
                        "name": "search",
                        "description": "Search a private index",
                        "annotations": {"readOnlyHint": True},
                        "inputSchema": {
                            "type": "object",
                            "properties": {"query": {"type": "string"}},
                        },
                    }
                ]
            }
        elif method == "tools/call":
            query = message.get("params", {}).get("arguments", {}).get("query", "")
            result = {
                "content": [
                    {
                        "type": "text",
                        "text": f"HTTP_MCP_OK:{query}",
                    }
                ]
            }
        else:
            result = {}
        response_json = json.dumps(
            {"jsonrpc": "2.0", "id": request_id, "result": result},
            separators=(",", ":"),
        )
        response = (
            f"id: tools-page-1\ndata: {response_json}\n\n".encode("utf-8")
            if method == "tools/list"
            else response_json.encode("utf-8")
        )
        self.send_response(200)
        self.send_header(
            "Content-Type",
            "text/event-stream" if method == "tools/list" else "application/json",
        )
        if method == "initialize":
            self.send_header("Mcp-Session-Id", "test-session")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def do_DELETE(self):
        self.send_response(204)
        self.end_headers()


class DesktopMcpRegistryTest(unittest.TestCase):
    def setUp(self):
        FakeStreamableHttpMcp.observations = []

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

    def test_explicit_handle_is_scoped_and_threads_through_live_events(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "fake_mcp.py"
            server.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")
            handles = ToolHandleRegistry()
            registry = DesktopMcpRegistry(
                root / "mcp.json",
                handle_registry=handles,
            )
            registry.upsert({
                "id": "handled",
                "name": "Handled MCP",
                "command": f'"{sys.executable}" "{server}"',
                "default_tool": "get_status",
                "permission_mode": "read_only",
            })

            opened = registry.open_handle(
                "handled",
                owner_id="galaxyssi.desktop.agent_loop",
                context_id="conversation-1",
                parent_run_id="task-1",
            )
            self.assertTrue(opened["handle_id"].startswith("sth_mcpconne_"))
            self.assertNotIn("resource_id", opened)

            events: list[dict] = []
            result = registry.invoke_handle(
                opened["handle_id"],
                "status",
                owner_id="galaxyssi.desktop.agent_loop",
                context_id="conversation-1",
                audit_context={"task_id": "task-1"},
                tool_call_callback=events.append,
            )
            self.assertEqual("MCP_OK:status", result["result"])
            self.assertEqual(opened["handle_id"], result["mcp_handle_id"])
            self.assertTrue(events)
            self.assertTrue(
                all(
                    event["mcp_handle_id"] == opened["handle_id"]
                    for event in events
                )
            )

            with self.assertRaises(ToolHandleError) as raised:
                registry.invoke_handle(
                    opened["handle_id"],
                    "status",
                    owner_id="another-owner",
                    context_id="conversation-1",
                )
            self.assertEqual("tool_handle_owner_mismatch", raised.exception.code)

    def test_connection_change_and_delete_revoke_explicit_handles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            handles = ToolHandleRegistry()
            registry = DesktopMcpRegistry(
                root / "mcp.json",
                handle_registry=handles,
            )
            original = {
                "id": "revoked",
                "name": "Revoked MCP",
                "command": "python original.py",
            }
            registry.upsert(original)
            first = registry.open_handle("revoked", owner_id="owner")

            registry.upsert({**original, "command": "python replacement.py"})
            with self.assertRaises(ToolHandleError):
                registry.invoke_handle(
                    first["handle_id"],
                    "status",
                    owner_id="owner",
                )

            second = registry.open_handle("revoked", owner_id="owner")
            self.assertTrue(registry.delete("revoked"))
            with self.assertRaises(ToolHandleError):
                registry.invoke_handle(
                    second["handle_id"],
                    "status",
                    owner_id="owner",
                )

    def test_enabled_connections_use_full_access_for_every_tool_risk(self):
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
            relay_events: list[dict] = []
            relay = registry.invoke_prompt(
                "governed",
                "turn on",
                explicit_user_selection=False,
                tool_call_callback=relay_events.append,
            )
            self.assertEqual("MCP_OK:turn on", relay["result"])
            self.assertEqual(["running", "succeeded"], [event["status"] for event in relay_events])
            self.assertTrue(relay_events[-1]["allowed"])
            self.assertEqual("", relay_events[-1]["required_user_action"])

            registry.upsert({
                "id": "governed",
                "name": "Governed",
                "command": command,
                "default_tool": "delete_device",
                "permission_mode": "trusted",
            })
            allowed = registry.invoke_prompt("governed", "delete")
            self.assertEqual(allowed["security"]["risk"], "high")
            self.assertEqual(
                [entry["status"] for entry in registry.audit("governed")],
                ["succeeded", "succeeded", "succeeded"],
            )

    def test_tool_call_callback_exposes_only_redacted_live_security_context(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "fake_mcp.py"
            server.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")
            registry = DesktopMcpRegistry(root / "mcp.json")
            registry.upsert({
                "id": "visible-tool",
                "name": "Visible Tool",
                "command": f'"{sys.executable}" "{server}"',
                "default_tool": "relay",
                "permission_mode": "trusted",
            })
            events: list[dict] = []

            result = registry.invoke_prompt(
                "visible-tool",
                "token=private-value",
                explicit_user_selection=True,
                tool_call_callback=events.append,
            )

            self.assertEqual("MCP_OK:token=private-value", result["result"])
            self.assertEqual(["running", "succeeded"], [event["status"] for event in events])
            self.assertEqual(1, len({event["invocation_id"] for event in events}))
            final = events[-1]
            self.assertEqual("desktop-mcp:visible-tool", final["source"])
            self.assertEqual("medium", final["risk"])
            self.assertIn("mcp.data.write", final["permissions"])
            self.assertTrue(final["allowed"])
            self.assertEqual("token=[REDACTED]", final["parameter_preview"]["prompt"])
            self.assertNotIn("private-value", json.dumps(events))
            self.assertNotIn("command", final)

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

    def test_streamable_http_is_a_typed_connection_with_lifecycle_metadata(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), FakeStreamableHttpMcp)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        previous_token = os.environ.get("GALAXYSSI_TEST_MCP_TOKEN")
        os.environ["GALAXYSSI_TEST_MCP_TOKEN"] = "Bearer private-value"
        try:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "mcp.json"
                registry = DesktopMcpRegistry(path)
                endpoint = f"http://127.0.0.1:{server.server_port}/mcp"
                saved = registry.upsert({
                    "id": "private-search",
                    "name": "Private Search",
                    "transport": "streamable_http",
                    "endpoint": endpoint,
                    "header_env": {
                        "Authorization": "GALAXYSSI_TEST_MCP_TOKEN",
                    },
                    "default_tool": "search",
                    "permission_mode": "read_only",
                    "timeout_seconds": 5,
                })
                self.assertEqual(saved["transport"], "streamable_http")
                self.assertEqual(saved["state"], "configured")
                self.assertNotIn("private-value", json.dumps(saved))

                probe = registry.probe("private-search")
                self.assertEqual(probe["status"], "ready")
                self.assertEqual(probe["server_info"]["name"], "fake-http")
                self.assertEqual(probe["tools"][0]["name"], "search")

                persisted = DesktopMcpRegistry(path).list(include_configuration=True)[0]
                self.assertEqual(persisted["state"], "ready")
                self.assertEqual(persisted["server_name"], "Fake HTTP MCP")
                self.assertEqual(persisted["server_version"], "2.1")
                self.assertEqual(persisted["capabilities"], ["tools"])
                self.assertEqual(persisted["tool_ids"], ["search"])

                result = registry.invoke_prompt("private-search", "latest release")
                self.assertEqual(result["result"], "HTTP_MCP_OK:latest release")
                self.assertEqual(result["security"]["risk"], "low")
                self.assertTrue(
                    all(
                        item["authorization"] == "Bearer private-value"
                        for item in FakeStreamableHttpMcp.observations
                    )
                )
                subsequent = [
                    item
                    for item in FakeStreamableHttpMcp.observations
                    if item["method"] != "initialize"
                ]
                self.assertTrue(
                    all(item["protocol"] == "2025-11-25" for item in subsequent)
                )
                self.assertTrue(
                    all(item["session"] == "test-session" for item in subsequent)
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
            if previous_token is None:
                os.environ.pop("GALAXYSSI_TEST_MCP_TOKEN", None)
            else:
                os.environ["GALAXYSSI_TEST_MCP_TOKEN"] = previous_token

    def test_remote_plain_http_requires_an_explicit_lan_override(self):
        with tempfile.TemporaryDirectory() as directory:
            registry = DesktopMcpRegistry(Path(directory) / "mcp.json")
            with self.assertRaisesRegex(ValueError, "requires HTTPS"):
                registry.upsert({
                    "id": "unsafe-remote",
                    "name": "Unsafe Remote",
                    "transport": "streamable_http",
                    "endpoint": "http://192.168.1.20/mcp",
                })
            saved = registry.upsert({
                "id": "trusted-lan",
                "name": "Trusted LAN",
                "transport": "streamable_http",
                "endpoint": "http://192.168.1.20/mcp",
                "allow_insecure_http": True,
            })
            self.assertTrue(saved["allow_insecure_http"])


if __name__ == "__main__":
    unittest.main()
