import os
import http.server
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from unified_commands.engine import UnifiedCommandEngine
from unified_commands.capabilities import EXTERNAL_HISTORY_ACTIONS
from unified_commands.handlers import PROCESS_LOCK, PROCESS_REGISTRY
from unified_commands.parser import parse_slash_command
from unified_commands.protocol import CommandRequest, CommandResult, now_iso
from unified_commands.store import CommandStore


class UnifiedCommandsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.workspace = Path(self.tmp.name) / "workspace"
        self.workspace.mkdir()
        self.engine = UnifiedCommandEngine(CommandStore(Path(self.tmp.name) / "commands.sqlite3"))

    def tearDown(self):
        with PROCESS_LOCK:
            items = list(PROCESS_REGISTRY.values())
            PROCESS_REGISTRY.clear()
        for item in items:
            process = item["process"]
            stdin = getattr(process, "stdin", None)
            if stdin is not None and not stdin.closed:
                try:
                    stdin.close()
                except Exception:
                    pass
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except Exception:
                    process.kill()
        self.tmp.cleanup()

    def test_slash_parser_builds_structured_request(self):
        request = parse_slash_command(
            '/file write --path notes/today.txt --content "hello world" --approve',
            workspace=str(self.workspace),
        )
        self.assertEqual(request.command_id, "file.write")
        self.assertEqual(request.args["path"], "notes/today.txt")
        self.assertEqual(request.args["content"], "hello world")
        self.assertTrue(request.approve)

    def test_unknown_command_returns_not_found_not_prompt_fallback(self):
        result = self.engine.execute(CommandRequest("dragon.fly", workspace=str(self.workspace)))
        self.assertEqual(result.status, "not_found")
        self.assertEqual(result.error_code, "command_not_found")

    def test_file_write_runs_without_internal_approval(self):
        result = self.engine.execute(CommandRequest("file.write", {"path": "a.txt", "content": "x"}, workspace=str(self.workspace)))
        self.assertEqual(result.status, "completed")
        self.assertEqual((self.workspace / "a.txt").read_text(encoding="utf-8"), "x")

    def test_high_risk_dry_run_runs_without_internal_approval(self):
        result = self.engine.execute(
            CommandRequest("file.write", {"path": "a.txt", "content": "x", "dry_run": True}, workspace=str(self.workspace))
        )
        self.assertEqual(result.status, "completed")

    def test_file_write_read_and_snapshot_are_deterministic(self):
        first = self.engine.execute(
            CommandRequest("file.write", {"path": "a.txt", "content": "one"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(first.status, "completed")
        second = self.engine.execute(
            CommandRequest("file.write", {"path": "a.txt", "content": "two"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(second.status, "completed")
        self.assertTrue(second.data["snapshot_path"])
        self.assertEqual(Path(second.data["snapshot_path"]).read_text(encoding="utf-8"), "one")
        read = self.engine.execute(CommandRequest("file.read", {"path": "a.txt"}, workspace=str(self.workspace)))
        self.assertEqual(read.status, "completed")
        self.assertEqual(read.data["content"], "two")

    def test_workspace_escape_is_denied(self):
        result = self.engine.execute(
            CommandRequest("file.read", {"path": "../outside.txt"}, workspace=str(self.workspace))
        )
        self.assertEqual(result.status, "denied")
        self.assertEqual(result.error_code, "workspace_path_denied")

    def test_commands_and_capabilities_are_structured(self):
        commands = self.engine.execute(CommandRequest("commands.list", workspace=str(self.workspace)))
        self.assertEqual(commands.status, "completed")
        self.assertGreaterEqual(commands.data["catalog_size"], 620)
        self.assertGreaterEqual(len(commands.data["roots"]), 101)
        missing_handlers = [item["command_id"] for item in commands.data["commands"] if not item["handler"]]
        self.assertEqual(missing_handlers, [])
        capabilities = self.engine.execute(CommandRequest("capabilities.list", workspace=str(self.workspace)))
        self.assertEqual(capabilities.status, "completed")
        self.assertEqual(capabilities.data["registered_count"], commands.data["catalog_size"])
        self.assertEqual(capabilities.data["handler_bound_count"], commands.data["catalog_size"])
        self.assertEqual(
            sum(capabilities.data["status_counts"].values()),
            commands.data["catalog_size"],
        )
        self.assertEqual(
            capabilities.data["runnable_count"] + capabilities.data["unavailable_count"],
            commands.data["catalog_size"],
        )
        by_id = {
            item["command_id"]: item
            for item in capabilities.data["capabilities"]
        }
        self.assertEqual(by_id["commands.list"]["status"], "ready")
        self.assertEqual(by_id["file.read"]["status"], "needs_input")
        self.assertEqual(by_id["camera.run"]["status"], "unsupported")
        self.assertEqual(by_id["codex.run"]["status"], "unsupported")
        self.assertEqual(by_id["archive.stop"]["status"], "unsupported")
        self.assertEqual(by_id["memory.create"]["implementation"], "sqlite_state_service")
        self.assertEqual(by_id["web.inspect"]["implementation"], "external_adapter")
        self.assertLess(capabilities.data["ready_count"], commands.data["catalog_size"])

    def test_every_command_has_one_truthful_capability_classification(self):
        result = self.engine.execute(
            CommandRequest("capabilities.list", workspace=str(self.workspace))
        )
        self.assertEqual(result.status, "completed")
        capabilities = result.data["capabilities"]
        allowed = {
            "ready",
            "needs_input",
            "needs_configuration",
            "missing_runtime",
            "unsupported",
        }
        self.assertEqual(len(capabilities), len(self.engine.registry.list()))
        self.assertEqual(
            {item["command_id"] for item in capabilities},
            {item["command_id"] for item in self.engine.registry.list()},
        )
        self.assertTrue(all(item["status"] in allowed for item in capabilities))
        self.assertTrue(all(item["registered"] for item in capabilities))
        self.assertTrue(all(item["handler_bound"] for item in capabilities))
        self.assertGreater(result.data["unsupported_count"], 0)
        self.assertGreater(result.data["needs_input_count"], 0)

    def test_all_write_and_high_risk_commands_bypass_internal_approval(self):
        failures = []
        protected = [
            command for command in self.engine.registry.list()
            if command["risk"] in {"write", "high"}
        ]
        for command in protected:
            result = self.engine.execute(
                CommandRequest(
                    command["command_id"],
                    {"dry_run": True},
                    workspace=str(self.workspace),
                )
            )
            if result.error_code == "approval_required" or command["requires_approval"]:
                failures.append(
                    (command["command_id"], result.status, result.error_code)
                )
        self.assertGreater(len(protected), 0)
        self.assertEqual(failures, [])

    def test_all_high_risk_commands_simulate_dispatch_without_side_effects(self):
        high_risk = [
            command
            for command in self.engine.registry.list()
            if command["risk"] == "high"
        ]
        before = sorted(
            path.relative_to(self.workspace).as_posix()
            for path in self.workspace.rglob("*")
        )
        failures = []

        def simulated_handler(definition, request):
            completed = now_iso()
            return CommandResult(
                "completed",
                definition.command_id,
                request.run_id,
                data={
                    "simulated": True,
                    "command_id": definition.command_id,
                },
                display={"type": "full_access_simulation_receipt"},
                started_at=completed,
                completed_at=completed,
            )

        for command in high_risk:
            command_id = command["command_id"]
            original_handler = self.engine.registry.handler(command_id)
            self.assertIsNotNone(original_handler)
            try:
                self.engine.registry.register(command_id, simulated_handler)
                dispatched = self.engine.execute(
                    CommandRequest(
                        command_id,
                        source="full_access_simulation",
                        requested_by="test",
                        workspace=str(self.workspace),
                    )
                )
            finally:
                self.engine.registry.register(command_id, original_handler)
            if (
                dispatched.status != "completed"
                or dispatched.data.get("simulated") is not True
                or dispatched.display.get("type")
                != "full_access_simulation_receipt"
            ):
                failures.append(
                    (command_id, "dispatched", dispatched.public())
                )

        after = sorted(
            path.relative_to(self.workspace).as_posix()
            for path in self.workspace.rglob("*")
        )
        with closing(sqlite3.connect(self.engine.store.path)) as conn:
            simulated_runs = conn.execute(
                """
                SELECT COUNT(*)
                FROM command_runs
                WHERE source = 'full_access_simulation' AND status = 'completed'
                """
            ).fetchone()[0]
            simulated_receipts = conn.execute(
                """
                SELECT COUNT(*)
                FROM command_audit
                WHERE event_type = 'command_completed'
                  AND run_id IN (
                      SELECT run_id
                      FROM command_runs
                      WHERE source = 'full_access_simulation'
                  )
                """
            ).fetchone()[0]

        self.assertEqual(len(high_risk), 328)
        self.assertEqual(failures, [])
        self.assertEqual(before, after)
        self.assertEqual(simulated_runs, len(high_risk))
        self.assertEqual(simulated_receipts, len(high_risk))

    def test_adb_inspect_reports_missing_or_ambiguous_device_cleanly(self):
        no_device = subprocess.CompletedProcess(
            ["adb", "devices"],
            0,
            stdout="List of devices attached\n\n",
            stderr="",
        )
        with (
            patch(
                "unified_commands.handlers.shutil.which",
                return_value="adb",
            ),
            patch(
                "unified_commands.handlers.subprocess.run",
                return_value=no_device,
            ),
        ):
            result = self.engine.execute(
                CommandRequest(
                    "android.inspect",
                    workspace=str(self.workspace),
                )
            )
        self.assertEqual(result.status, "unavailable")
        self.assertEqual(result.error_code, "adb_device_unavailable")

        multiple_devices = subprocess.CompletedProcess(
            ["adb", "devices"],
            0,
            stdout=(
                "List of devices attached\n"
                "phone-one\tdevice\n"
                "phone-two\tdevice\n"
            ),
            stderr="",
        )
        with (
            patch(
                "unified_commands.handlers.shutil.which",
                return_value="adb",
            ),
            patch(
                "unified_commands.handlers.subprocess.run",
                return_value=multiple_devices,
            ),
        ):
            result = self.engine.execute(
                CommandRequest(
                    "device.inspect",
                    workspace=str(self.workspace),
                )
            )
        self.assertEqual(result.status, "unavailable")
        self.assertEqual(
            result.error_code,
            "adb_device_selection_required",
        )

    def test_registered_only_commands_report_unavailable_when_invoked(self):
        matrix = self.engine.execute(
            CommandRequest("capabilities.list", workspace=str(self.workspace))
        )
        unsupported = [
            item["command_id"]
            for item in matrix.data["capabilities"]
            if item["status"] == "unsupported"
        ]
        failures = []
        for command_id in unsupported:
            result = self.engine.execute(
                CommandRequest(
                    command_id,
                    {
                        "id": "unsupported-check",
                        "path": "unsupported-check",
                        "source": "unsupported-source",
                        "destination": "unsupported-destination",
                        "url": "http://127.0.0.1/",
                        "host": "127.0.0.1",
                        "argv": [sys.executable, "-c", "print('unsupported')"],
                        "code": "print('unsupported')",
                        "text": "unsupported",
                    },
                    workspace=str(self.workspace),
                    approve=True,
                )
            )
            if result.status != "unavailable":
                failures.append((command_id, result.public()))
        self.assertGreater(len(unsupported), 0)
        self.assertEqual(failures, [])

    def test_non_high_read_only_gaps_have_real_observation_handlers(self):
        recovered = {
            f"{root}.{action}"
            for root, actions in EXTERNAL_HISTORY_ACTIONS.items()
            for action in actions
        } | {"shell.list"}
        self.assertEqual(len(recovered), 65)

        seeded = self.engine.execute(
            CommandRequest(
                "codex.status",
                {"token": "must-not-leak"},
                workspace=str(self.workspace),
            )
        )
        self.assertEqual(seeded.status, "completed")

        matrix = self.engine.execute(
            CommandRequest("capabilities.list", workspace=str(self.workspace))
        )
        by_id = {
            item["command_id"]: item
            for item in matrix.data["capabilities"]
        }
        self.assertEqual(
            [
                item["command_id"]
                for item in matrix.data["capabilities"]
                if item["status"] == "unsupported"
                and item["risk"] != "high"
            ],
            [],
        )
        failures = []
        for command_id in sorted(recovered):
            capability = by_id[command_id]
            if capability["status"] != "ready":
                failures.append(
                    (command_id, "capability", capability["status"])
                )
                continue
            result = self.engine.execute(
                CommandRequest(
                    command_id,
                    {"query": "codex" if command_id == "codex.search" else ""},
                    workspace=str(self.workspace),
                )
            )
            if result.status != "completed":
                failures.append(
                    (command_id, result.status, result.error_code)
                )
        self.assertEqual(failures, [])

        received = self.engine.execute(
            CommandRequest("codex.receive", workspace=str(self.workspace))
        )
        searched = self.engine.execute(
            CommandRequest(
                "codex.search",
                {"query": "codex.status"},
                workspace=str(self.workspace),
            )
        )
        inspected = self.engine.execute(
            CommandRequest("codex.inspect", workspace=str(self.workspace))
        )
        shells = self.engine.execute(
            CommandRequest("shell.list", workspace=str(self.workspace))
        )
        self.assertTrue(
            any(
                item["command_id"] == "codex.status"
                for item in received.data["items"]
            )
        )
        self.assertNotIn(
            "must-not-leak",
            str(received.data),
        )
        self.assertTrue(
            any(
                item["command_id"] == "codex.status"
                for item in searched.data["items"]
            )
        )
        self.assertEqual(
            inspected.data["latest"]["command_id"],
            "codex.status",
        )
        self.assertEqual(shells.status, "completed")
        self.assertIn("shells", shells.data)

    def test_native_services_have_required_sqlite_tables(self):
        tables = set(self.engine.store.table_names())
        self.assertTrue({
            "command_kv",
            "command_entities",
            "command_events",
            "command_text_records",
            "command_schedules",
            "command_usage",
        }.issubset(tables))

    def test_native_roots_persist_to_specialized_tables(self):
        config = self.engine.execute(
            CommandRequest("config.create", {"id": "theme", "value": {"mode": "dark"}}, workspace=str(self.workspace), approve=True)
        )
        memory = self.engine.execute(
            CommandRequest("memory.create", {"id": "m1", "body": "remember this"}, workspace=str(self.workspace), approve=True)
        )
        schedule = self.engine.execute(
            CommandRequest(
                "schedule.create",
                {"id": "daily", "command": "/commands", "cron": "0 9 * * *"},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        usage = self.engine.execute(
            CommandRequest("usage.create", {"id": "tokens", "metric": "tokens", "amount": 42}, workspace=str(self.workspace), approve=True)
        )
        audit = self.engine.execute(
            CommandRequest("audit.create", {"id": "event-1", "event_type": "check"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(config.status, "completed")
        self.assertEqual(memory.status, "completed")
        self.assertEqual(schedule.status, "completed")
        self.assertEqual(usage.status, "completed")
        self.assertEqual(audit.status, "completed")
        self.assertEqual(self.engine.store.get_kv("config", "theme")["value"]["mode"], "dark")
        self.assertEqual(self.engine.store.get_text_record("m1")["value"]["body"], "remember this")
        self.assertEqual(self.engine.store.get_schedule("daily")["value"]["schedule"]["cron"], "0 9 * * *")
        self.assertEqual(self.engine.store.get_usage("tokens")["value"]["amount"], 42)
        self.assertEqual(self.engine.store.get_event("event-1")["name"], "check")

    def test_all_registered_commands_dry_run_without_prompt_fallback(self):
        commands = self.engine.registry.list()
        self.assertGreaterEqual(len(commands), 620)
        self.assertGreaterEqual(len(self.engine.registry.roots()), 101)
        failures = []
        for command in commands:
            result = self.engine.execute(
                CommandRequest(
                    command["command_id"],
                    {"dry_run": True},
                    workspace=str(self.workspace),
                    approve=True,
                )
            )
            if result.status != "completed" or result.error_code:
                failures.append((command["command_id"], result.status, result.error_code))
        self.assertEqual(failures, [])

    def test_all_registered_commands_dispatch_without_unhandled_exceptions(self):
        commands = self.engine.registry.list()
        failures = []
        for command in commands:
            safe_id = command["command_id"].replace(".", "-")
            args = {"path": f"{safe_id}.txt", "content": "dispatch", "id": f"{safe_id}-dispatch"}
            if command["command_id"] == "file.copy":
                (self.workspace / "copy-source.txt").write_text("copy", encoding="utf-8")
                args.update({"source": "copy-source.txt", "destination": "copy-destination.txt"})
            elif command["command_id"] == "file.move":
                (self.workspace / "move-source.txt").write_text("move", encoding="utf-8")
                args.update({"source": "move-source.txt", "destination": "move-destination.txt"})
            elif command["command_id"] == "file.delete":
                (self.workspace / "delete-target.txt").write_text("delete", encoding="utf-8")
                args.update({"path": "delete-target.txt"})
            elif command["command_id"] == "file.mkdir":
                args.update({"path": "dispatch-dir"})
            result = self.engine.execute(
                CommandRequest(
                    command["command_id"],
                    args,
                    workspace=str(self.workspace),
                    approve=True,
                )
            )
            if result.error_code == "command_failed":
                failures.append((command["command_id"], result.message))
        self.assertEqual(failures, [])

    def test_git_status_uses_argument_array(self):
        os.system(f'git -C "{self.workspace}" init --quiet')
        result = self.engine.execute(CommandRequest("git.status", workspace=str(self.workspace)))
        self.assertEqual(result.status, "completed")
        self.assertIn("##", result.data["stdout"])

    def test_git_diff_log_and_branch_use_argument_arrays(self):
        os.system(f'git -C "{self.workspace}" init --quiet')
        os.system(f'git -C "{self.workspace}" config user.name "GalaxySSI Test"')
        os.system(f'git -C "{self.workspace}" config user.email "galaxyssi-test@example.invalid"')
        (self.workspace / "tracked.txt").write_text("one\n", encoding="utf-8")
        os.system(f'git -C "{self.workspace}" add tracked.txt')
        os.system(f'git -C "{self.workspace}" commit -m initial --quiet')
        (self.workspace / "tracked.txt").write_text("two\n", encoding="utf-8")
        diff = self.engine.execute(CommandRequest("git.diff", {"file": "tracked.txt"}, workspace=str(self.workspace)))
        log = self.engine.execute(CommandRequest("git.log", {"limit": 5}, workspace=str(self.workspace)))
        branch = self.engine.execute(CommandRequest("git.branch", workspace=str(self.workspace)))
        self.assertEqual(diff.status, "completed")
        self.assertIn("-one", diff.data["stdout"])
        self.assertEqual(log.status, "completed")
        self.assertIn("initial", log.data["stdout"])
        self.assertEqual(branch.status, "completed")
        self.assertIn("*", branch.data["stdout"] + branch.data["stderr"])

    def test_file_move_copy_delete_and_mkdir_are_real(self):
        mkdir = self.engine.execute(CommandRequest("file.mkdir", {"path": "dir"}, workspace=str(self.workspace), approve=True))
        self.assertEqual(mkdir.status, "completed")
        (self.workspace / "dir" / "a.txt").write_text("alpha", encoding="utf-8")
        copy = self.engine.execute(
            CommandRequest(
                "file.copy",
                {"source": "dir/a.txt", "destination": "copy.txt"},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        self.assertEqual(copy.status, "completed")
        self.assertEqual((self.workspace / "copy.txt").read_text(encoding="utf-8"), "alpha")
        move = self.engine.execute(
            CommandRequest(
                "file.move",
                {"source": "copy.txt", "destination": "moved.txt"},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        delete = self.engine.execute(CommandRequest("file.delete", {"path": "moved.txt"}, workspace=str(self.workspace), approve=True))
        self.assertEqual(move.status, "completed")
        self.assertFalse((self.workspace / "copy.txt").exists())
        self.assertEqual(delete.status, "completed")
        self.assertFalse((self.workspace / "moved.txt").exists())
        self.assertTrue(Path(delete.data["deleted_path"]).exists())

    def test_project_status_reports_package_scripts(self):
        (self.workspace / "package.json").write_text(
            '{"scripts":{"check":"node -e \\"console.log(1)\\""}}',
            encoding="utf-8",
        )
        result = self.engine.execute(CommandRequest("project.status", workspace=str(self.workspace)))
        self.assertEqual(result.status, "completed")
        self.assertIn("check", result.data["package_scripts"])

    def test_shell_run_executes_argument_array(self):
        result = self.engine.execute(
            CommandRequest(
                "shell.run",
                {"argv": [sys.executable, "-c", "print('shell-ok')"]},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        self.assertEqual(result.status, "completed")
        self.assertIn("shell-ok", result.data["stdout"])

    def test_npm_script_handler_runs_selected_script(self):
        npm = "npm.cmd" if os.name == "nt" else "npm"
        if shutil.which(npm) is None:
            self.skipTest("npm is not installed in this environment")
        (self.workspace / "package.json").write_text(
            '{"scripts":{"check":"node -e \\"console.log(\\\\\\"checked\\\\\\")\\""}}',
            encoding="utf-8",
        )
        result = self.engine.execute(
            CommandRequest(
                "test.run",
                {"script": "check", "timeout": 30},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        self.assertEqual(result.status, "completed", result.data.get("stderr"))
        self.assertIn("checked", result.data["stdout"])

    def test_process_lifecycle_is_controlled_by_registry(self):
        argv = [sys.executable, "-c", "import time; time.sleep(30)"]
        start = self.engine.execute(
            CommandRequest("process.start", {"id": "proc-test", "argv": argv}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(start.status, "completed")
        self.assertEqual(start.data["process"]["status"], "running")
        restart = self.engine.execute(
            CommandRequest("process.restart", {"id": "proc-test"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(restart.status, "completed")
        self.assertEqual(restart.data["process"]["status"], "running")
        stop = self.engine.execute(
            CommandRequest("process.stop", {"id": "proc-test"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(stop.status, "completed")
        self.assertEqual(stop.data["process"]["status"], "exited")

    def test_process_stdin_output_and_kill_are_controlled_by_registry(self):
        argv = [
            sys.executable,
            "-c",
            "import sys,time; line=sys.stdin.readline().strip(); print('got-' + line, flush=True); time.sleep(30)",
        ]
        start = self.engine.execute(
            CommandRequest("process.start", {"id": "proc-io", "argv": argv}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(start.status, "completed")
        write = self.engine.execute(
            CommandRequest("process.stdin", {"id": "proc-io", "text": "hello"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(write.status, "completed")
        output = None
        for _ in range(20):
            output = self.engine.execute(CommandRequest("process.output", {"id": "proc-io"}, workspace=str(self.workspace)))
            if "got-hello" in output.data.get("stdout", ""):
                break
            time.sleep(0.1)
        self.assertEqual(output.status, "completed")
        self.assertIn("got-hello", output.data["stdout"])
        killed = self.engine.execute(CommandRequest("process.kill", {"id": "proc-io"}, workspace=str(self.workspace), approve=True))
        self.assertEqual(killed.status, "completed")
        self.assertEqual(killed.data["process"]["status"], "exited")

    def test_process_stop_unknown_returns_not_found(self):
        result = self.engine.execute(
            CommandRequest("process.stop", {"id": "missing"}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(result.status, "not_found")
        self.assertEqual(result.error_code, "process_not_found")

    def test_port_status_returns_structured_probe(self):
        result = self.engine.execute(CommandRequest("port.status", {"port": 9}, workspace=str(self.workspace)))
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.data["port"], 9)
        invalid = self.engine.execute(CommandRequest("port.status", {"port": "not-a-port"}, workspace=str(self.workspace)))
        self.assertEqual(invalid.status, "failed")
        self.assertEqual(invalid.error_code, "port_invalid")

    def test_document_and_inventory_handlers_inspect_workspace(self):
        (self.workspace / "notes.md").write_text("# Notes", encoding="utf-8")
        (self.workspace / "tools").mkdir()
        (self.workspace / "tools" / "helper.ps1").write_text("Write-Output ok", encoding="utf-8")
        documents = self.engine.execute(CommandRequest("document.list", workspace=str(self.workspace)))
        inventory = self.engine.execute(CommandRequest("tool.list", workspace=str(self.workspace)))
        self.assertEqual(documents.status, "completed")
        self.assertTrue(any(item["path"] == "notes.md" for item in documents.data["documents"]))
        self.assertEqual(inventory.status, "completed")
        self.assertTrue(any(item["path"].endswith("helper.ps1") for item in inventory.data["entries"]))

    def test_deploy_release_rollback_run_package_scripts(self):
        npm = "npm.cmd" if os.name == "nt" else "npm"
        if shutil.which(npm) is None:
            self.skipTest("npm is not installed in this environment")
        (self.workspace / "package.json").write_text(
            '{"scripts":{"deploy":"node -e \\"console.log(\\\\\\"deployed\\\\\\")\\""}}',
            encoding="utf-8",
        )
        result = self.engine.execute(
            CommandRequest("deploy.run", {"timeout": 30}, workspace=str(self.workspace), approve=True)
        )
        self.assertEqual(result.status, "completed", result.data.get("stderr"))
        self.assertIn("deployed", result.data["stdout"])

    def test_pr_and_issue_handlers_do_not_fake_success_without_repo(self):
        pr = self.engine.execute(CommandRequest("pr.list", workspace=str(self.workspace)))
        issue = self.engine.execute(CommandRequest("issue.list", workspace=str(self.workspace)))
        self.assertEqual(pr.status, "unavailable")
        self.assertEqual(pr.error_code, "git_repository_required")
        self.assertEqual(issue.status, "unavailable")
        self.assertEqual(issue.error_code, "git_repository_required")

    def test_web_http_adapter_fetches_real_local_response(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"hello-web")

            def log_message(self, *args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/"
            result = self.engine.execute(CommandRequest("web.inspect", {"url": url}, workspace=str(self.workspace)))
            self.assertEqual(result.status, "completed")
            self.assertEqual(result.data["status_code"], 200)
            self.assertIn("hello-web", result.data["body"])
        finally:
            server.shutdown()
            server.server_close()

    def test_node_adapter_executes_when_runtime_exists(self):
        if shutil.which("node") is None:
            self.skipTest("node is not installed in this environment")
        result = self.engine.execute(
            CommandRequest(
                "node.run",
                {"code": "console.log('node-ok')", "timeout": 15},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        self.assertEqual(result.status, "completed", result.data.get("stderr"))
        self.assertIn("node-ok", result.data["stdout"])

    def test_communication_and_worker_adapters_persist_state(self):
        message = self.engine.execute(
            CommandRequest("message.send", {"id": "msg-1", "body": "hello"}, workspace=str(self.workspace), approve=True)
        )
        contact = self.engine.execute(
            CommandRequest("contact.sync", {"id": "contact-1", "name": "Ada"}, workspace=str(self.workspace), approve=True)
        )
        worker = self.engine.execute(
            CommandRequest(
                "worker.sync",
                {"id": "worker-1", "command": "/commands", "interval_seconds": 60},
                workspace=str(self.workspace),
                approve=True,
            )
        )
        self.assertEqual(message.status, "completed")
        self.assertEqual(contact.status, "completed")
        self.assertEqual(worker.status, "completed")
        listed_messages = self.engine.execute(CommandRequest("message.list", workspace=str(self.workspace)))
        listed_contacts = self.engine.execute(CommandRequest("contact.list", workspace=str(self.workspace)))
        listed_workers = self.engine.execute(CommandRequest("worker.list", workspace=str(self.workspace)))
        self.assertTrue(any(item["id"] == "msg-1" for item in listed_messages.data["items"]))
        self.assertTrue(any(item["id"] == "contact-1" for item in listed_contacts.data["items"]))
        self.assertTrue(any(item["id"] == "worker-1" for item in listed_workers.data["items"]))

    def test_external_adapters_return_structured_failures(self):
        webhook = self.engine.execute(
            CommandRequest("webhook.send", {"url": "not-a-url"}, workspace=str(self.workspace), approve=True)
        )
        smtp = self.engine.execute(CommandRequest("smtp.send", workspace=str(self.workspace), approve=True))
        browser = self.engine.execute(CommandRequest("browser.inspect", {"url": "nope"}, workspace=str(self.workspace)))
        ssh = self.engine.execute(CommandRequest("ssh.run", workspace=str(self.workspace), approve=True))
        self.assertEqual(webhook.status, "failed")
        self.assertEqual(webhook.error_code, "url_invalid")
        self.assertEqual(smtp.status, "failed")
        self.assertEqual(smtp.error_code, "smtp_required_fields_missing")
        self.assertEqual(browser.status, "failed")
        self.assertEqual(browser.error_code, "url_invalid")
        self.assertIn(ssh.status, {"failed", "unavailable"})
        self.assertIn(ssh.error_code, {"ssh_host_required", "prerequisite_unavailable"})

    def test_added_root_catalog_reaches_required_surface(self):
        roots = set(self.engine.registry.roots())
        self.assertGreaterEqual(len(roots), 101)
        self.assertTrue({
            "playwright",
            "chromium",
            "dns",
            "camera",
            "microphone",
            "notification",
            "archive",
            "checksum",
            "database",
            "python",
            "package",
            "workspace",
        }.issubset(roots))

    def test_added_local_tool_roots_have_real_handlers(self):
        target = self.workspace / "sample.txt"
        target.write_text("abc", encoding="utf-8")
        checksum = self.engine.execute(CommandRequest("checksum.run", {"path": "sample.txt"}, workspace=str(self.workspace), approve=True))
        archive = self.engine.execute(
            CommandRequest("archive.run", {"path": "sample.txt", "output": "sample.zip"}, workspace=str(self.workspace), approve=True)
        )
        env = self.engine.execute(CommandRequest("env.list", {"limit": 5}, workspace=str(self.workspace)))
        python = self.engine.execute(
            CommandRequest("python.run", {"code": "print('python-ok')"}, workspace=str(self.workspace), approve=True)
        )
        package = self.engine.execute(CommandRequest("package.status", workspace=str(self.workspace)))
        self.assertEqual(checksum.status, "completed")
        self.assertEqual(checksum.data["sha256"], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        self.assertEqual(archive.status, "completed")
        self.assertTrue((self.workspace / "sample.zip").is_file())
        self.assertEqual(env.status, "completed")
        self.assertTrue(env.data["values_redacted"])
        self.assertEqual(python.status, "completed")
        self.assertIn("python-ok", python.data["stdout"])
        self.assertEqual(package.status, "completed")
        self.assertIn("package_json", package.data)

    def test_database_dns_and_phone_permission_roots_are_structured(self):
        db_path = self.workspace / "sample.sqlite3"
        import sqlite3

        conn = sqlite3.connect(db_path)
        try:
            conn.execute("CREATE TABLE demo (id INTEGER PRIMARY KEY)")
            conn.commit()
        finally:
            conn.close()
        database = self.engine.execute(CommandRequest("database.list", {"path": "sample.sqlite3"}, workspace=str(self.workspace)))
        dns = self.engine.execute(CommandRequest("dns.inspect", {"host": "localhost"}, workspace=str(self.workspace)))
        camera = self.engine.execute(CommandRequest("camera.status", workspace=str(self.workspace)))
        microphone = self.engine.execute(CommandRequest("microphone.run", workspace=str(self.workspace), approve=True))
        self.assertEqual(database.status, "completed")
        self.assertIn("demo", database.data["tables"])
        self.assertEqual(dns.status, "completed")
        self.assertTrue(dns.data["addresses"])
        self.assertEqual(camera.status, "completed")
        self.assertFalse(camera.data["configured"])
        self.assertEqual(microphone.status, "unavailable")
        self.assertEqual(microphone.error_code, "phone_action_unavailable")

    def test_fastapi_command_endpoints(self):
        with patch.dict(
            os.environ,
            {
                "GALAXYSSI_DISABLE_EXTERNAL_SERVICES": "1",
                "GALAXYSSI_COMMAND_DB": str(Path(self.tmp.name) / "api-commands.sqlite3"),
            },
        ):
            from types import SimpleNamespace
            from main import UnifiedCommandReq, api_execute_unified_command, api_list_unified_commands

            listed = api_list_unified_commands("")
            self.assertGreaterEqual(listed["catalog_size"], 620)
            executed = api_execute_unified_command(
                UnifiedCommandReq(
                    command_id="commands.list",
                    args={"dry_run": True},
                    workspace=str(self.workspace),
                ),
                SimpleNamespace(client=SimpleNamespace(host="testclient")),
            )
            self.assertEqual(executed["status"], "completed")

    def test_default_engine_reopens_the_configured_store(self):
        import unified_commands.engine as engine_module

        original_engine = engine_module._default_engine
        first_path = Path(self.tmp.name) / "first-default.sqlite3"
        second_path = Path(self.tmp.name) / "second-default.sqlite3"
        try:
            with patch.dict(os.environ, {"GALAXYSSI_COMMAND_DB": str(first_path)}):
                first = engine_module.default_command_engine()
            with patch.dict(os.environ, {"GALAXYSSI_COMMAND_DB": str(second_path)}):
                second = engine_module.default_command_engine()

            self.assertEqual(first_path, first.store.path)
            self.assertEqual(second_path, second.store.path)
            self.assertIsNot(first, second)
            self.assertTrue(first_path.is_file())
            self.assertTrue(second_path.is_file())
        finally:
            engine_module._default_engine = original_engine


if __name__ == "__main__":
    unittest.main()
