from __future__ import annotations

import json
import os
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from desktop_mcp import DesktopMcpRegistry
from mcp_config_import import (
    McpConfigImportError,
    discover_mcp_config_sources,
    parse_mcp_import,
)


ENV_SERVER = r'''
import json
import os
import sys

while True:
    line = sys.stdin.readline()
    if not line:
        break
    message = json.loads(line)
    request_id = message.get("id")
    method = message.get("method")
    if request_id is None:
        continue
    if method == "initialize":
        result = {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "serverInfo": {"name": "import-test", "version": "1"},
        }
    elif method == "tools/list":
        result = {
            "tools": [
                {
                    "name": "environment",
                    "description": "Read imported environment",
                    "annotations": {"readOnlyHint": True},
                    "inputSchema": {"type": "object", "properties": {}},
                }
            ]
        }
    elif method == "tools/call":
        result = {
            "content": [
                {
                    "type": "text",
                    "text": (
                        os.environ.get("MCP_TEST_TOKEN", "")
                        + "|"
                        + os.environ.get("UNRELATED_HOST_SECRET", "")
                    ),
                }
            ]
        }
    else:
        result = {}
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": request_id, "result": result}) + "\n")
    sys.stdout.flush()
'''


class McpConfigImportTest(unittest.TestCase):
    def test_claude_json_import_redacts_environment_values(self):
        secret = "never-store-this-token"
        content = json.dumps(
            {
                "mcpServers": {
                    "github-tools": {
                        "command": "npx",
                        "args": ["-y", "@example/github-mcp"],
                        "env": {
                            "GITHUB_TOKEN": secret,
                            "CACHE_DIR": "${MCP_CACHE_DIR}",
                        },
                    }
                }
            }
        )
        document = parse_mcp_import(
            content,
            source_hint="claude",
            file_name="claude_desktop_config.json",
        )
        candidate = document.candidates[0]
        self.assertTrue(candidate.importable)
        self.assertEqual("claude", candidate.source)
        self.assertEqual(
            ["npx", "-y", "@example/github-mcp"],
            candidate.connection["command_argv"],
        )
        self.assertEqual(
            {
                "GITHUB_TOKEN": "GITHUB_TOKEN",
                "CACHE_DIR": "MCP_CACHE_DIR",
            },
            candidate.connection["environment_env"],
        )
        self.assertNotIn(secret, json.dumps(document.public(), sort_keys=True))

    def test_codex_toml_imports_stdio_and_http_profiles(self):
        content = textwrap.dedent(
            """
            [mcp_servers.context7]
            command = "npx"
            args = ["-y", "@upstash/context7-mcp"]
            env_vars = ["LOCAL_TOKEN"]
            cwd = "."
            tool_timeout_sec = 45
            enabled = true

            [mcp_servers.figma]
            url = "https://mcp.figma.com/mcp"
            bearer_token_env_var = "FIGMA_OAUTH_TOKEN"
            env_http_headers = { "X-Figma-Region" = "FIGMA_REGION" }
            default_tools_approval_mode = "prompt"
            """
        )
        document = parse_mcp_import(
            content,
            source_hint="codex",
            file_name="config.toml",
        )
        by_id = {candidate.connection["id"]: candidate for candidate in document.candidates}
        self.assertEqual({"context7", "figma"}, set(by_id))
        self.assertEqual(45, by_id["context7"].connection["timeout_seconds"])
        self.assertEqual(
            {"LOCAL_TOKEN": "LOCAL_TOKEN"},
            by_id["context7"].connection["environment_env"],
        )
        self.assertEqual(
            {
                "Authorization": "FIGMA_OAUTH_TOKEN",
                "X-Figma-Region": "FIGMA_REGION",
            },
            by_id["figma"].connection["header_env"],
        )
        self.assertEqual("ask_for_changes", by_id["figma"].connection["permission_mode"])

    def test_openclaw_json5_imports_nested_servers_and_scoped_approval(self):
        content = textwrap.dedent(
            """
            {
              // OpenClaw accepts JSON5.
              mcp: {
                servers: {
                  docs: {
                    command: "npx",
                    args: ["-y", "@example/docs-mcp"],
                    env: { DOCS_TOKEN: "${OPENCLAW_DOCS_TOKEN}" },
                  },
                  remote: {
                    url: "https://mcp.example.com/mcp",
                    headers: { Authorization: "Bearer ${OPENCLAW_REMOTE_TOKEN}" },
                    codex: { defaultToolsApprovalMode: "approve" },
                    requestTimeoutMs: 15000,
                  },
                },
              },
            }
            """
        )
        document = parse_mcp_import(
            content,
            source_hint="openclaw",
            file_name="openclaw.json",
        )
        by_id = {candidate.connection["id"]: candidate for candidate in document.candidates}
        self.assertEqual("openclaw", document.source)
        self.assertEqual(
            {"DOCS_TOKEN": "OPENCLAW_DOCS_TOKEN"},
            by_id["docs"].connection["environment_env"],
        )
        self.assertEqual(
            {"Authorization": "OPENCLAW_REMOTE_TOKEN"},
            by_id["remote"].connection["header_env"],
        )
        self.assertEqual(
            {"Authorization": "Bearer {value}"},
            by_id["remote"].connection["header_templates"],
        )
        self.assertEqual("trusted", by_id["remote"].connection["permission_mode"])
        self.assertEqual(15, by_id["remote"].connection["timeout_seconds"])
        with tempfile.TemporaryDirectory() as directory:
            registry = DesktopMcpRegistry(Path(directory) / "registry.json")
            registry.upsert(by_id["remote"].connection)
            with patch.dict(
                os.environ,
                {"OPENCLAW_REMOTE_TOKEN": "runtime-only-token"},
                clear=False,
            ):
                arguments = registry._args(registry.get("remote"))
            self.assertEqual(
                "Bearer runtime-only-token",
                arguments.request_headers["Authorization"],
            )
            self.assertNotIn(
                "runtime-only-token",
                (Path(directory) / "registry.json").read_text(encoding="utf-8"),
            )

    def test_hermes_yaml_imports_stdio_and_http_servers(self):
        content = textwrap.dedent(
            """
            model: test-model
            mcp_servers:
              filesystem:
                command: npx
                args:
                  - -y
                  - "@modelcontextprotocol/server-filesystem"
                  - /tmp
                env:
                  FILESYSTEM_TOKEN: "${HERMES_FILESYSTEM_TOKEN}"
                timeout: 45
              company_api:
                url: https://mcp.example.com/mcp
                headers:
                  Authorization: "Bearer ${HERMES_COMPANY_TOKEN}"
                connect_timeout: 12
            """
        )
        document = parse_mcp_import(
            content,
            source_hint="hermes",
            file_name="config.yaml",
        )
        by_id = {candidate.connection["id"]: candidate for candidate in document.candidates}
        self.assertEqual("hermes", document.source)
        self.assertTrue(by_id["filesystem"].importable)
        self.assertEqual(45, by_id["filesystem"].connection["timeout_seconds"])
        self.assertEqual(
            {"FILESYSTEM_TOKEN": "HERMES_FILESYSTEM_TOKEN"},
            by_id["filesystem"].connection["environment_env"],
        )
        self.assertTrue(by_id["company_api"].importable)
        self.assertEqual(
            {"Authorization": "HERMES_COMPANY_TOKEN"},
            by_id["company_api"].connection["header_env"],
        )
        self.assertEqual(
            {"Authorization": "Bearer {value}"},
            by_id["company_api"].connection["header_templates"],
        )

    def test_hermes_tool_filters_are_not_silently_broadened(self):
        content = textwrap.dedent(
            """
            mcp_servers:
              github:
                command: npx
                args: ["-y", "@example/github-mcp"]
                tools:
                  include: [list_issues]
            """
        )
        candidate = parse_mcp_import(
            content,
            source_hint="hermes",
            file_name="config.yaml",
        ).candidates[0]
        self.assertFalse(candidate.importable)
        self.assertTrue(
            any("filters" in warning.casefold() for warning in candidate.warnings)
        )

    def test_credential_in_command_argument_is_removed_and_blocked(self):
        secret = "private-token-value"
        content = json.dumps(
            {
                "mcpServers": {
                    "unsafe": {
                        "command": "node",
                        "args": ["server.js", "--api-key", secret],
                    }
                }
            }
        )
        candidate = parse_mcp_import(content, source_hint="claude").candidates[0]
        self.assertFalse(candidate.importable)
        serialized = json.dumps(candidate.public(set()))
        self.assertNotIn(secret, serialized)
        self.assertIn("<credential-not-imported>", serialized)

    def test_imported_stdio_uses_argv_and_environment_mapping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "env server.py"
            server.write_text(textwrap.dedent(ENV_SERVER), encoding="utf-8")
            content = json.dumps(
                {
                    "mcpServers": {
                        "environment": {
                            "command": sys.executable,
                            "args": [str(server)],
                            "env": {"MCP_TEST_TOKEN": "${HOST_MCP_TEST_TOKEN}"},
                        }
                    }
                }
            )
            candidate = parse_mcp_import(content, source_hint="claude").candidates[0]
            registry = DesktopMcpRegistry(root / "registry.json")
            with patch.dict(
                os.environ,
                {
                    "HOST_MCP_TEST_TOKEN": "environment-isolated",
                    "UNRELATED_HOST_SECRET": "must-not-leak",
                },
                clear=False,
            ):
                saved = registry.upsert(candidate.connection)
                self.assertEqual(
                    [sys.executable, str(server)],
                    saved["command_argv"],
                )
                self.assertEqual("ready", registry.probe("environment")["status"])
                result = registry.invoke_prompt(
                    "environment",
                    "read",
                    explicit_user_selection=True,
                )
            self.assertEqual("environment-isolated|", result["result"])
            persisted = (root / "registry.json").read_text(encoding="utf-8")
            self.assertNotIn("environment-isolated", persisted)
            self.assertNotIn("must-not-leak", persisted)
            self.assertIn("HOST_MCP_TEST_TOKEN", persisted)

    def test_invalid_or_empty_configuration_fails_cleanly(self):
        with self.assertRaises(McpConfigImportError):
            parse_mcp_import("{}", source_hint="auto")
        with self.assertRaises(McpConfigImportError):
            parse_mcp_import("{bad", source_hint="auto")
        with self.assertRaises(McpConfigImportError):
            parse_mcp_import(
                '{"mcpServers": {}, "mcpServers": {}}',
                source_hint="claude",
            )
        with self.assertRaises(McpConfigImportError):
            parse_mcp_import(
                "mcp_servers:\n  docs: {}\n  docs: {}\n",
                source_hint="hermes",
                file_name="config.yaml",
            )

    def test_known_configuration_files_are_discovered_without_scanning_home(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            appdata = root / "appdata"
            claude = appdata / "Claude" / "claude_desktop_config.json"
            codex = root / ".codex" / "config.toml"
            openclaw = root / ".openclaw" / "openclaw.json"
            hermes = root / ".hermes" / "config.yaml"
            for path, content in (
                (claude, '{"mcpServers": {}}'),
                (codex, "[mcp_servers]"),
                (openclaw, '{"mcp": {"servers": {}}}'),
                (hermes, "mcp_servers: {}"),
            ):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            with patch.dict(
                os.environ,
                {
                    "APPDATA": str(appdata),
                    "OPENCLAW_CONFIG_PATH": str(openclaw),
                },
                clear=False,
            ):
                sources = discover_mcp_config_sources(root)
            self.assertEqual(
                {"claude", "codex", "openclaw", "hermes"},
                {source["source"] for source in sources},
            )

    def test_preview_and_commit_api_reparse_the_same_digest(self):
        import desktop_mcp
        import main

        content = json.dumps(
            {
                "mcpServers": {
                    "docs": {
                        "command": "npx",
                        "args": ["-y", "@example/docs-mcp"],
                    }
                }
            }
        )
        request = SimpleNamespace(client=SimpleNamespace(host="127.0.0.1"))
        with tempfile.TemporaryDirectory() as directory:
            registry = DesktopMcpRegistry(Path(directory) / "registry.json")
            previous = desktop_mcp._MCP
            desktop_mcp._MCP = registry
            try:
                preview = main.api_desktop_mcp_import_preview(
                    main.DesktopMcpImportPreviewReq(
                        content=content,
                        file_name=".mcp.json",
                    ),
                    request,
                )
                self.assertEqual(1, preview["summary"]["importable"])
                committed = main.api_desktop_mcp_import_commit(
                    main.DesktopMcpImportCommitReq(
                        content=content,
                        file_name=".mcp.json",
                        digest=preview["digest"],
                        selected_ids=["docs"],
                    ),
                    request,
                )
            finally:
                desktop_mcp._MCP = previous
            self.assertEqual(["docs"], [item["id"] for item in committed["imported"]])
            self.assertEqual("docs", registry.list(include_configuration=True)[0]["id"])


if __name__ == "__main__":
    unittest.main()
