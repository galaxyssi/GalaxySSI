import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from desktop_native_tools import (
    APP_LAUNCH,
    APP_LIST,
    ARCHIVE_CREATE,
    BROWSER_OPEN,
    FILE_LIST,
    FILE_READ_TEXT,
    FILE_SHA256,
    FILE_WRITE_TEXT,
    HOST_FILE_SEARCH,
    OFFICE_CONVERT,
    OFFICE_INSPECT,
    PROCESS_LIST,
    RUNTIME_STATUS,
    SYSTEM_STATUS,
    TERMINAL_RUN,
    TOOL_VERSION,
    WEB_FETCH,
    DesktopNativeToolRegistry,
    _digest,
)
from web_intelligence import TOOL_OPERATIONS as WEB_INTELLIGENCE_OPERATIONS


class DesktopNativeToolRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.launched = []
        self.opened_urls = []
        workspace_root = self.root / "workspaces"
        self.registry = DesktopNativeToolRegistry(
            state_root=self.root / "state",
            workspace_root=workspace_root,
            known_roots={"workspace": workspace_root},
            app_catalog=lambda: [{"id": "notepad", "name": "Notepad", "kind": "executable", "launch": "notepad.exe"}],
            app_launcher=lambda item: self.launched.append(item),
            browser_opener=lambda url: self.opened_urls.append(url) or True,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(self, tool_id, arguments, *, key="", confirmed=False, invocation_id="invocation-1"):
        confirmation = None
        if confirmed:
            confirmation = {
                "decision": "approved",
                "tool_id": tool_id,
                "tool_version": TOOL_VERSION,
                "arguments_sha256": _digest(arguments),
                "expires_at": int(__import__("time").time() * 1000) + 60_000,
            }
        return self.registry.invoke(tool_id, arguments, {
            "invocation_id": invocation_id,
            "idempotency_key": key,
            "confirmation": confirmation,
        })

    def workspace(self, name="task-a"):
        path = self.root / "workspaces" / name
        path.mkdir(parents=True, exist_ok=True)
        return path

    def test_manifest_exposes_typed_windows_file_terminal_and_office_tools(self):
        manifest = self.registry.manifest()
        tools = {item["id"]: item for item in manifest["tools"]}

        self.assertEqual("galaxyssi.desktop-native-tools/1.2", manifest["contract_version"])
        for tool_id in (
            SYSTEM_STATUS, RUNTIME_STATUS, PROCESS_LIST, FILE_LIST, FILE_READ_TEXT, FILE_WRITE_TEXT,
            FILE_SHA256, ARCHIVE_CREATE, TERMINAL_RUN, OFFICE_INSPECT, OFFICE_CONVERT,
            APP_LIST, APP_LAUNCH, HOST_FILE_SEARCH, BROWSER_OPEN, WEB_FETCH,
            *WEB_INTELLIGENCE_OPERATIONS.keys(),
        ):
            self.assertIn(tool_id, tools)
            self.assertEqual("desktop", tools[tool_id]["location"])
            self.assertFalse(tools[tool_id]["input_schema"]["additionalProperties"])
        self.assertEqual([], tools[FILE_WRITE_TEXT]["required_consents"])
        self.assertEqual([], tools[ARCHIVE_CREATE]["required_consents"])
        self.assertEqual([], tools[OFFICE_CONVERT]["required_consents"])
        self.assertEqual(
            ["galaxyssi.consent.desktop.execute"],
            [item["id"] for item in tools[TERMINAL_RUN]["required_consents"]],
        )

    def test_web_intelligence_tools_delegate_to_bounded_native_service(self):
        calls = []

        class StubWebIntelligence:
            def invoke(self, operation, arguments):
                calls.append((operation, arguments))
                return {
                    "protocol": "galaxyssi.web-intelligence.v1",
                    "operation": operation,
                    "request_id": "web-test",
                    "status": "completed",
                    "started_at_millis": 1,
                    "completed_at_millis": 2,
                    "receipts": [],
                    "results": [],
                }

        self.registry.web_intelligence = StubWebIntelligence()
        tool_id = "galaxyssi.web.intelligence.search"
        result = self.invoke(tool_id, {"query": "GalaxySSI", "limit": 5})

        self.assertEqual("succeeded", result["status"])
        self.assertEqual("galaxyssi.web-intelligence.v1", result["output"]["protocol"])
        self.assertEqual([("search", {"query": "GalaxySSI", "limit": 5})], calls)
        self.assertEqual("passed", result["verification"]["status"])

    def test_search_launch_and_browser_tools_are_bounded(self):
        source = self.workspace() / "release-notes.md"
        source.write_text("ready", encoding="utf-8")

        searched = self.invoke(HOST_FILE_SEARCH, {
            "root": "workspace", "query": "release", "extensions": ["md"], "max_depth": 4, "max_entries": 10,
        })
        applications = self.invoke(APP_LIST, {"query": "note", "max_entries": 10})
        launched = self.invoke(APP_LAUNCH, {"name": "Notepad"})
        opened = self.invoke(BROWSER_OPEN, {"url": "https://example.com/docs"})
        blocked = self.invoke(WEB_FETCH, {"url": "http://127.0.0.1:8765", "max_bytes": 4096})

        self.assertEqual(searched["output"]["files"][0]["name"], "release-notes.md")
        self.assertEqual(applications["output"]["applications"][0]["name"], "Notepad")
        self.assertEqual(launched["status"], "succeeded")
        self.assertEqual(self.launched[0]["id"], "notepad")
        self.assertEqual(opened["status"], "succeeded")
        self.assertEqual(self.opened_urls, ["https://example.com/docs"])
        self.assertEqual(blocked["error"]["code"], "private_network_blocked")

    def test_workspace_path_escape_is_rejected(self):
        result = self.invoke(FILE_READ_TEXT, {"workspace_id": "task-a", "path": "../secret.txt"})

        self.assertEqual("failed", result["status"])
        self.assertEqual("invalid_path", result["error"]["code"])
        audit = self.registry.audit(limit=1)
        self.assertEqual(FILE_READ_TEXT, audit[0]["tool_id"])
        self.assertEqual("failed", audit[0]["status"])
        self.assertEqual("invalid_path", audit[0]["error_code"])
        self.assertEqual(_digest({"workspace_id": "task-a", "path": "../secret.txt"}), audit[0]["input_sha256"])

    def test_bounded_workspace_write_is_direct_and_replays_same_receipt(self):
        arguments = {
            "workspace_id": "task-a",
            "path": "src/hello.txt",
            "content": "hello",
            "mode": "create",
        }
        accepted = self.invoke(FILE_WRITE_TEXT, arguments, key="write-1")
        replayed = self.invoke(
            FILE_WRITE_TEXT,
            arguments,
            key="write-1",
            invocation_id="invocation-2",
        )

        self.assertEqual("succeeded", accepted["status"])
        self.assertEqual("hello", (self.workspace() / "src" / "hello.txt").read_text(encoding="utf-8"))
        self.assertTrue(replayed["receipt"]["replayed"])
        self.assertEqual("invocation-1", replayed["receipt"]["original_invocation_id"])
        audit = self.registry.audit(tool_id=FILE_WRITE_TEXT)
        self.assertEqual(2, len(audit))
        self.assertTrue(audit[0]["replayed"])
        self.assertEqual("invocation-2", audit[0]["invocation_id"])
        self.assertEqual("invocation-1", audit[0]["original_invocation_id"])

    def test_workspace_write_rejects_host_execution_configuration(self):
        result = self.invoke(
            FILE_WRITE_TEXT,
            {
                "workspace_id": "task-a",
                "path": ".galaxyssi-task.json",
                "content": '{"task_id":"attacker"}',
                "mode": "create",
            },
            key="protected-write-1",
        )

        self.assertEqual("failed", result["status"])
        self.assertEqual(
            "host_execution_config_write_blocked",
            result["error"]["code"],
        )
        self.assertFalse(
            (self.workspace() / ".galaxyssi-task.json").exists()
        )

    def test_idempotency_key_cannot_be_reused_with_different_input(self):
        first = {"workspace_id": "task-a", "path": "a.txt", "content": "one", "mode": "create"}
        second = {"workspace_id": "task-a", "path": "b.txt", "content": "two", "mode": "create"}
        self.assertEqual("succeeded", self.invoke(FILE_WRITE_TEXT, first, key="same")["status"])

        result = self.invoke(FILE_WRITE_TEXT, second, key="same", invocation_id="invocation-2")

        self.assertEqual("failed", result["status"])
        self.assertEqual("idempotency_key_conflict", result["error"]["code"])
        self.assertFalse((self.workspace() / "b.txt").exists())

        replay = self.invoke(FILE_WRITE_TEXT, first, key="same", invocation_id="invocation-3")
        self.assertEqual("succeeded", replay["status"])
        self.assertTrue(replay["receipt"]["replayed"])

    def test_read_list_and_hash_return_host_observed_evidence(self):
        source = self.workspace() / "data.txt"
        source.write_text("GalaxySSI", encoding="utf-8")

        listing = self.invoke(FILE_LIST, {"workspace_id": "task-a"})
        read = self.invoke(FILE_READ_TEXT, {"workspace_id": "task-a", "path": "data.txt"})
        hashed = self.invoke(FILE_SHA256, {"workspace_id": "task-a", "path": "data.txt"})

        self.assertEqual("succeeded", listing["status"])
        self.assertEqual("data.txt", listing["output"]["entries"][0]["path"])
        self.assertEqual("GalaxySSI", read["output"]["text"])
        self.assertEqual(read["output"]["sha256"], hashed["output"]["sha256"])
        self.assertEqual("passed", hashed["verification"]["status"])

    def test_archive_contains_only_explicit_workspace_files(self):
        workspace = self.workspace()
        (workspace / "a.txt").write_text("a", encoding="utf-8")
        (workspace / "folder").mkdir()
        (workspace / "folder" / "b.txt").write_text("b", encoding="utf-8")
        arguments = {
            "workspace_id": "task-a",
            "paths": ["a.txt", "folder"],
            "output_path": "outputs/result.zip",
        }

        result = self.invoke(ARCHIVE_CREATE, arguments, key="zip-1")

        self.assertEqual("succeeded", result["status"])
        with zipfile.ZipFile(workspace / "outputs" / "result.zip") as archive:
            self.assertEqual(["a.txt", "folder/b.txt"], sorted(archive.namelist()))
        self.assertEqual("application/zip", result["artifacts"][0]["mime_type"])

    def test_terminal_uses_argument_array_and_blocks_general_shells(self):
        arguments = {
            "workspace_id": "task-a",
            "argv": ["cmd.exe", "/c", "echo unsafe"],
            "timeout_seconds": 10,
        }

        result = self.invoke(TERMINAL_RUN, arguments, key="terminal-1")

        self.assertEqual("failed", result["status"])
        self.assertEqual("shell_blocked", result["error"]["code"])

    def test_terminal_returns_exit_code_and_bounded_output(self):
        self.workspace()
        arguments = {
            "workspace_id": "task-a",
            "argv": ["python", "-c", "print('ok')"],
            "timeout_seconds": 10,
        }
        with patch.object(self.registry, "_resolve_executable", return_value=sys.executable):
            result = self.invoke(TERMINAL_RUN, arguments, key="terminal-2")

        self.assertEqual("succeeded", result["status"])
        self.assertEqual(0, result["output"]["exit_code"])
        self.assertEqual("ok", result["output"]["stdout"].strip())

    def test_terminal_rolls_back_indirect_host_configuration_write(self):
        workspace = self.workspace()
        metadata = workspace / ".galaxyssi-task.json"
        metadata.write_text('{"task_id":"trusted"}', encoding="utf-8")
        arguments = {
            "workspace_id": "task-a",
            "argv": [
                "python",
                "-c",
                (
                    "from pathlib import Path;"
                    "Path('.galaxyssi-task.json').write_text("
                    "'{\\\"task_id\\\":\\\"attacker\\\"}', encoding='utf-8')"
                ),
            ],
            "timeout_seconds": 10,
        }

        with patch.object(
            self.registry,
            "_resolve_executable",
            return_value=sys.executable,
        ):
            result = self.invoke(
                TERMINAL_RUN,
                arguments,
                key="terminal-protected-1",
                confirmed=True,
            )

        self.assertEqual("failed", result["status"])
        self.assertEqual(
            "host_execution_config_write_blocked",
            result["error"]["code"],
        )
        self.assertEqual(
            '{"task_id":"trusted"}',
            metadata.read_text(encoding="utf-8"),
        )

    def test_docx_inspection_does_not_execute_active_content(self):
        source = self.workspace() / "report.docx"
        document_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Hello report</w:t></w:r></w:p></w:body>
</w:document>"""
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr("word/document.xml", document_xml)

        result = self.invoke(OFFICE_INSPECT, {"workspace_id": "task-a", "path": "report.docx"})

        self.assertEqual("succeeded", result["status"])
        self.assertEqual("word", result["output"]["document_type"])
        self.assertEqual(["Hello report"], result["output"]["text_items"])

    def test_office_conversion_is_direct_and_verifies_artifact(self):
        source = self.workspace() / "report.docx"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr(
                "word/document.xml",
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body/></w:document>',
            )
        arguments = {
            "workspace_id": "task-a",
            "path": "report.docx",
            "output_format": "pdf",
            "output_path": "outputs/report.pdf",
        }

        with patch.object(self.registry, "_run_office_conversion", side_effect=lambda _id, _src, dst, _fmt: dst.write_bytes(b"%PDF-test")):
            result = self.invoke(OFFICE_CONVERT, arguments, key="office-1")

        self.assertEqual("succeeded", result["status"])
        self.assertEqual("application/pdf", result["output"]["mime_type"])
        self.assertEqual("passed", result["verification"]["status"])
        self.assertEqual("desktop_workspace", result["artifacts"][0]["location"])

    def test_excel_text_conversion_flattens_rows_instead_of_creating_empty_output(self):
        source = self.workspace() / "data.xlsx"
        with zipfile.ZipFile(source, "w") as archive:
            archive.writestr(
                "xl/workbook.xml",
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<sheets><sheet name="Sheet1" sheetId="1"/></sheets></workbook>',
            )
            archive.writestr(
                "xl/sharedStrings.xml",
                '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<si><t>Name</t></si><si><t>GalaxySSI</t></si></sst>',
            )
            archive.writestr(
                "xl/worksheets/sheet1.xml",
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
                '<row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row>'
                '</sheetData></worksheet>',
            )
        arguments = {
            "workspace_id": "task-a",
            "path": "data.xlsx",
            "output_format": "txt",
            "output_path": "outputs/data.txt",
        }

        result = self.invoke(OFFICE_CONVERT, arguments, key="office-text-1")

        self.assertEqual("succeeded", result["status"])
        self.assertEqual("Name\tGalaxySSI", (self.workspace() / "outputs" / "data.txt").read_text(encoding="utf-8"))

    @unittest.skipUnless(sys.platform == "win32", "Windows-only host probes")
    def test_windows_status_and_process_inventory_execute_real_host_probes(self):
        status = self.invoke(SYSTEM_STATUS, {})
        processes = self.invoke(PROCESS_LIST, {"max_entries": 5})

        self.assertEqual("succeeded", status["status"])
        self.assertGreater(status["output"]["logical_cpu_count"], 0)
        self.assertEqual("succeeded", processes["status"])
        self.assertGreater(processes["output"]["count"], 0)


if __name__ == "__main__":
    unittest.main()
