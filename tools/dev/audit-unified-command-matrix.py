#!/usr/bin/env python3
"""Generate a per-command readiness and safety audit without dangerous effects."""
from __future__ import annotations

import argparse
import csv
import hashlib
import http.server
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND = REPO_ROOT / "apps" / "desktop" / "core" / "galaxyssi-link" / "backend"
sys.path.insert(0, str(BACKEND))

from unified_commands.engine import UnifiedCommandEngine  # noqa: E402
from unified_commands.catalog import NATIVE_ROOTS  # noqa: E402
from unified_commands.handlers import PROCESS_LOCK, PROCESS_REGISTRY  # noqa: E402
from unified_commands.protocol import CommandRequest, CommandResult, now_iso  # noqa: E402
from unified_commands.store import CommandStore  # noqa: E402


def _unsupported_args() -> dict:
    return {
        "id": "unsupported-audit",
        "path": "unsupported-audit",
        "source": "unsupported-source",
        "destination": "unsupported-destination",
        "url": "http://127.0.0.1/",
        "host": "127.0.0.1",
        "argv": [sys.executable, "-c", "print('unsupported')"],
        "code": "print('unsupported')",
        "text": "unsupported",
    }


def _simulated_high_risk_handler(definition, request) -> CommandResult:
    """Exercise approved dispatch and audit paths without invoking side effects."""
    completed = now_iso()
    canonical_args = json.dumps(
        request.args,
        ensure_ascii=False,
        sort_keys=True,
        default=str,
    ).encode("utf-8")
    return CommandResult(
        "completed",
        definition.command_id,
        request.run_id,
        data={
            "simulated": True,
            "command_id": definition.command_id,
            "risk": definition.risk,
            "args_sha256": hashlib.sha256(canonical_args).hexdigest(),
        },
        display={"type": "approval_simulation_receipt"},
        started_at=completed,
        completed_at=completed,
    )


class SafeRuntimeFixture:
    def __init__(self, root: Path, engine: UnifiedCommandEngine):
        self.root = root
        self.engine = engine
        self.httpd: http.server.ThreadingHTTPServer | None = None
        self.http_thread: threading.Thread | None = None
        self.process: subprocess.Popen | None = None

    def prepare(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "sample.txt").write_text("GalaxySSI audit\n", encoding="utf-8")
        (self.root / "copy-source.txt").write_text("copy\n", encoding="utf-8")
        (self.root / "move-source.txt").write_text("move\n", encoding="utf-8")
        (self.root / "notes.md").write_text("# Audit\n", encoding="utf-8")
        (self.root / "tools").mkdir()
        (self.root / "tools" / "audit-tool.py").write_text(
            "print('audit-tool')\n",
            encoding="utf-8",
        )
        (self.root / "package.json").write_text(
            json.dumps(
                {
                    "name": "galaxyssi-command-audit",
                    "version": "1.0.0",
                    "scripts": {
                        "check": "node -e \"console.log('check')\"",
                        "check:android": "node -e \"console.log('android')\"",
                        "format": "node -e \"console.log('format')\"",
                        "deploy": "node -e \"console.log('deploy')\"",
                        "release": "node -e \"console.log('release')\"",
                        "rollback": "node -e \"console.log('rollback')\"",
                    },
                }
            ),
            encoding="utf-8",
        )
        conn = sqlite3.connect(self.root / "sample.sqlite3")
        try:
            conn.execute("CREATE TABLE audit_item (id INTEGER PRIMARY KEY, value TEXT)")
            conn.execute("INSERT INTO audit_item(value) VALUES ('ready')")
            conn.commit()
        finally:
            conn.close()
        self._prepare_git()
        self._prepare_http()
        self._prepare_process()
        self._seed_state_services()

    def close(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
        with PROCESS_LOCK:
            PROCESS_REGISTRY.pop("audit-process", None)
        if self.httpd is not None:
            self.httpd.shutdown()
            self.httpd.server_close()
        if self.http_thread is not None:
            self.http_thread.join(timeout=3)

    @property
    def url(self) -> str:
        if self.httpd is None:
            return ""
        return f"http://127.0.0.1:{self.httpd.server_port}/"

    @property
    def port(self) -> int:
        return self.httpd.server_port if self.httpd is not None else 9

    def _prepare_git(self) -> None:
        git = shutil.which("git")
        if not git:
            return
        commands = (
            [git, "init", "--quiet"],
            [git, "config", "user.name", "GalaxySSI Audit"],
            [git, "config", "user.email", "galaxyssi-audit@example.invalid"],
            [git, "add", "."],
            [git, "commit", "-m", "audit fixture", "--quiet"],
            [git, "remote", "add", "origin", "https://github.com/galaxyssi/GalaxySSI.git"],
        )
        for command in commands:
            subprocess.run(
                command,
                cwd=self.root,
                capture_output=True,
                check=False,
                shell=False,
            )

    def _prepare_http(self) -> None:
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"GalaxySSI command audit")

            def log_message(self, *_args):
                return

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.http_thread = threading.Thread(
            target=self.httpd.serve_forever,
            daemon=True,
        )
        self.http_thread.start()

    def _prepare_process(self) -> None:
        output_dir = self.root / ".galaxyssi_command_processes"
        output_dir.mkdir()
        stdout_path = output_dir / "audit-process.stdout.log"
        stderr_path = output_dir / "audit-process.stderr.log"
        stdout_handle = stdout_path.open("wb")
        stderr_handle = stderr_path.open("wb")
        try:
            self.process = subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    "import time; print('audit-process-ready', flush=True); time.sleep(120)",
                ],
                cwd=self.root,
                stdout=stdout_handle,
                stderr=stderr_handle,
                stdin=subprocess.PIPE,
                shell=False,
            )
        finally:
            stdout_handle.close()
            stderr_handle.close()
        time.sleep(0.1)
        with PROCESS_LOCK:
            PROCESS_REGISTRY["audit-process"] = {
                "id": "audit-process",
                "process": self.process,
                "argv": [
                    sys.executable,
                    "-c",
                    "import time; print('audit-process-ready', flush=True); time.sleep(120)",
                ],
                "cwd": str(self.root),
                "started_at": datetime.now(timezone.utc).isoformat(),
                "stdout_path": str(stdout_path),
                "stderr_path": str(stderr_path),
            }

    def _seed_state_services(self) -> None:
        for root in NATIVE_ROOTS:
            self.engine.execute(
                CommandRequest(
                    f"{root}.create",
                    {
                        "id": f"audit-{root}",
                        "name": f"Audit {root}",
                        "body": f"Audit {root} record",
                        "value": {"audit": True},
                        "command": {"command_id": "commands.list"},
                        "cron": "0 9 * * *",
                    },
                    workspace=str(self.root),
                    approve=True,
                )
            )

    def args_for(self, command: dict) -> dict:
        command_id = command["command_id"]
        root = command["root"]
        action = command["action"]
        args = {
            "id": f"audit-{root}",
            "name": f"Audit {root}",
            "value": {"audit": True},
            "body": "GalaxySSI audit",
            "content": "GalaxySSI audit",
            "query": "audit",
            "limit": 10,
            "timeout": 20,
        }
        if command_id == "help.show":
            args["command"] = "file.read"
        elif command_id == "file.list":
            args["path"] = "."
        elif command_id == "file.read":
            args["path"] = "sample.txt"
        elif command_id == "file.write":
            args["path"] = "write-result.txt"
        elif command_id == "file.move":
            args.update(
                source="move-source.txt",
                destination="move-result.txt",
            )
        elif command_id == "file.copy":
            args.update(
                source="copy-source.txt",
                destination="copy-result.txt",
            )
        elif command_id == "file.mkdir":
            args["path"] = "created-directory"
        elif command_id == "process.output":
            args["id"] = "audit-process"
        elif root == "port":
            args["port"] = self.port
        elif root == "database":
            args["path"] = "sample.sqlite3"
        elif root == "checksum":
            args["path"] = "sample.txt"
        elif root == "archive":
            args.update(path="sample.txt", output="sample.zip")
        elif root in {"web", "http", "url", "browser", "playwright", "chromium", "webhook"}:
            args["url"] = self.url
        elif root == "dns":
            args["host"] = "localhost"
        elif root in {"device", "android"}:
            args["argv"] = ["devices", "-l"]
            args["text"] = "GalaxySSI"
        elif root == "ssh":
            args.update(host="127.0.0.1", argv=["echo", "GalaxySSI"])
        elif root == "scp":
            args.update(source="sample.txt", destination="scp-result.txt")
        elif root == "node":
            args["code"] = "console.log('GalaxySSI audit')"
        elif root == "smtp":
            args.update(host="127.0.0.1", **{"from": "a@example.invalid", "to": "b@example.invalid"})
        elif root in {"schedule", "cron", "watch", "trigger", "queue", "worker", "automation"}:
            args.update(
                command={"command_id": "commands.list"},
                cron="0 9 * * *",
                interval_seconds=60,
            )
        return args


def audit(workspace: Path, execute_safe: bool = False) -> dict:
    with tempfile.TemporaryDirectory(prefix="galaxyssi-command-audit-") as temp:
        engine = UnifiedCommandEngine(
            CommandStore(Path(temp) / "unified-command-audit.sqlite3")
        )
        execution_root = Path(temp) / "workspace"
        fixture = SafeRuntimeFixture(execution_root, engine)
        if execute_safe:
            fixture.prepare()
        matrix_result = engine.execute(
            CommandRequest("capabilities.list", workspace=str(workspace))
        )
        capabilities = {
            item["command_id"]: item
            for item in matrix_result.data["capabilities"]
        }
        rows = []
        try:
            for command in engine.registry.list():
                command_id = command["command_id"]
                capability = capabilities[command_id]
                protected = command["risk"] in {"write", "high"}
                approval_gate = "not_required"
                if protected:
                    denied = engine.execute(
                        CommandRequest(
                            command_id,
                            {"dry_run": True},
                            workspace=str(workspace),
                        )
                    )
                    approval_gate = (
                        "passed"
                        if denied.status == "denied"
                        and denied.error_code == "approval_required"
                        else f"failed:{denied.status}:{denied.error_code}"
                    )
                dry_run = engine.execute(
                    CommandRequest(
                        command_id,
                        {"dry_run": True},
                        workspace=str(workspace),
                        approve=True,
                    )
                )
                dry_run_status = (
                    "passed"
                    if dry_run.status == "completed" and not dry_run.error_code
                    else f"failed:{dry_run.status}:{dry_run.error_code}"
                )
                unsupported_dispatch = "not_applicable"
                if capability["status"] == "unsupported":
                    result = engine.execute(
                        CommandRequest(
                            command_id,
                            _unsupported_args(),
                            workspace=str(workspace),
                            approve=True,
                        )
                    )
                    unsupported_dispatch = (
                        "passed"
                        if result.status == "unavailable"
                        else f"failed:{result.status}:{result.error_code}"
                    )
                safe_execution = "not_requested"
                safe_result_status = ""
                safe_error_code = ""
                simulated_approval = "not_applicable"
                if execute_safe:
                    if command["risk"] == "high":
                        original_handler = engine.registry.handler(command_id)
                        if original_handler is None:
                            simulated_approval = "failed:handler_missing"
                            safe_execution = "failed:handler_missing"
                        else:
                            try:
                                engine.registry.register(
                                    command_id,
                                    _simulated_high_risk_handler,
                                )
                                result = engine.execute(
                                    CommandRequest(
                                        command_id,
                                        fixture.args_for(command),
                                        source="approval_simulation",
                                        requested_by="command_audit",
                                        workspace=str(execution_root),
                                        approve=True,
                                    )
                                )
                            finally:
                                engine.registry.register(
                                    command_id,
                                    original_handler,
                                )
                            safe_result_status = result.status
                            safe_error_code = result.error_code
                            if (
                                result.status == "completed"
                                and result.data.get("simulated") is True
                                and result.display.get("type")
                                == "approval_simulation_receipt"
                            ):
                                simulated_approval = "passed"
                                safe_execution = "simulated_approval_passed"
                            else:
                                simulated_approval = (
                                    f"failed:{result.status}:{result.error_code}"
                                )
                                safe_execution = simulated_approval
                    elif capability["status"] in {"ready", "needs_input"}:
                        result = engine.execute(
                            CommandRequest(
                                command_id,
                                fixture.args_for(command),
                                workspace=str(execution_root),
                                approve=True,
                            )
                        )
                        safe_result_status = result.status
                        safe_error_code = result.error_code
                        if result.status == "completed":
                            safe_execution = "passed"
                        elif (
                            result.status == "unavailable"
                            and result.error_code
                            in {
                                "adb_device_unavailable",
                                "adb_device_selection_required",
                            }
                        ):
                            safe_execution = (
                                f"environment_unavailable:{result.error_code}"
                            )
                        else:
                            safe_execution = (
                                f"failed:{result.status}:{result.error_code}"
                            )
                    elif capability["status"] == "unsupported":
                        safe_execution = "unsupported_verified"
                    else:
                        safe_execution = capability["status"]
                rows.append(
                    {
                        **command,
                        **{
                            f"capability_{key}": value
                            for key, value in capability.items()
                            if key not in {"command_id", "risk"}
                        },
                        "approval_gate": approval_gate,
                        "approved_dry_run": dry_run_status,
                        "unsupported_dispatch": unsupported_dispatch,
                        "safe_execution": safe_execution,
                        "safe_result_status": safe_result_status,
                        "safe_error_code": safe_error_code,
                        "simulated_approval": simulated_approval,
                    }
                )
        finally:
            if execute_safe:
                fixture.close()
    failures = [
        row
        for row in rows
        if row["approval_gate"].startswith("failed:")
        or row["approved_dry_run"].startswith("failed:")
        or row["unsupported_dispatch"].startswith("failed:")
        or row["safe_execution"].startswith("failed:")
        or row["simulated_approval"].startswith("failed:")
    ]
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": str(workspace),
        "catalog_size": len(rows),
        "status_counts": dict(
            sorted(Counter(row["capability_status"] for row in rows).items())
        ),
        "implementation_counts": dict(
            sorted(Counter(row["capability_implementation"] for row in rows).items())
        ),
        "risk_counts": dict(
            sorted(Counter(row["risk"] for row in rows).items())
        ),
        "audit_failures": len(failures),
        "safe_execution_counts": dict(
            sorted(Counter(row["safe_execution"] for row in rows).items())
        ),
        "rows": rows,
    }


def write_report(report: dict, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / "unified-command-audit.json"
    csv_path = output_dir / "unified-command-audit.csv"
    summary_path = output_dir / "unified-command-audit-summary.json"
    json_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    rows = report["rows"]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {key: value for key, value in report.items() if key != "rows"}
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", default=str(REPO_ROOT))
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--execute-safe", action="store_true")
    args = parser.parse_args()
    workspace = Path(args.workspace).expanduser().resolve()
    report = audit(workspace, execute_safe=args.execute_safe)
    write_report(report, Path(args.output_dir).expanduser().resolve())
    print(json.dumps({key: value for key, value in report.items() if key != "rows"}))
    return 1 if report["audit_failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
