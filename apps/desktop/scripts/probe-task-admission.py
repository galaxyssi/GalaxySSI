"""Opt-in real-provider probe of Desktop admission, context, and task completion."""
from __future__ import annotations

import argparse
import cProfile
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import uuid


def isolate_state(root: Path) -> None:
    os.environ.setdefault("CODEX_HOME", str(Path.home() / ".codex"))
    home = root / "home"
    home.mkdir()
    for name in ("HOME", "USERPROFILE", "APPDATA"):
        os.environ[name] = str(home)
    os.environ.update({
        "GALAXYSSI_STATE_DIR": str(root / "state"),
        "GALAXYSSI_DATA_DIR": str(root / "data"),
        "GALAXYSSI_DATABASE_PATH": str(root / "state/messages.sqlite3"),
        "GALAXYSSI_CONFIG_PATH": str(root / "state/agents.json"),
        "GALAXYSSI_WORKSPACE_ROOT": str(root / "workspaces"),
        "GALAXYSSI_DISABLE_EXTERNAL_SERVICES": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    })


def live_cases(backend, agent: str, timeout: float, report: dict, save) -> None:
    from starlette.requests import Request

    request = Request({"type": "http", "method": "POST", "path": "/api/desktop/tasks",
                       "client": ("127.0.0.1", 12345), "headers": []})
    manager = backend.agent_task_manager
    changed = threading.Event()
    subscription = manager.subscribe(lambda _: changed.set())
    conversation = "admission-probe-" + uuid.uuid4().hex
    token = "GX" + uuid.uuid4().hex[:10]
    cases = [
        ("remember", conversation,
         "\u8bf7\u8bb0\u4f4f\u672c\u6b21\u6d4b\u8bd5\u4ee3\u53f7\uff1a" + token +
         "\u3002\u53ea\u56de\u590d\u5df2\u8bb0\u4f4f\u3002", "\u5df2\u8bb0\u4f4f"),
        ("continuation", conversation,
         "\u4e0a\u4e00\u6761\u6d4b\u8bd5\u4ee3\u53f7\u662f\u4ec0\u4e48\uff1f\u53ea\u8f93\u51fa\u4ee3\u53f7\u3002", token),
        ("independent", "admission-probe-" + uuid.uuid4().hex,
         "\u53ea\u56de\u590d\uff1a\u72ec\u7acb\u4f1a\u8bdd\u9a8c\u8bc1\u5b8c\u6210\u3002", "\u72ec\u7acb\u4f1a\u8bdd\u9a8c\u8bc1\u5b8c\u6210"),
    ]
    owned = []
    try:
        for name, conversation_id, prompt, expected in cases:
            started = time.perf_counter()
            task = backend.api_start_desktop_task(backend.DesktopTaskStartReq(
                prompt=prompt, agent_id=agent, conversation_id=conversation_id,
                response_language="zh-CN"), request)
            task_id = task["task_id"]
            owned.append(task_id)
            accepted = time.perf_counter()
            previous = None
            expired = False
            while True:
                changed.clear()
                current = manager.get(task_id)
                marker = (current.status, bool(current.first_output_at))
                if marker != previous:
                    print(json.dumps({"case": name, "status": current.status,
                                      "has_first_output": marker[1],
                                      "elapsed_ms": round((time.perf_counter() - started) * 1000, 3)}), flush=True)
                    previous = marker
                if current.status in backend.TERMINAL_STATES:
                    break
                remaining = timeout - (time.perf_counter() - started)
                if remaining <= 0:
                    expired = True
                    manager.cancel(task_id)
                    current = manager.get(task_id)
                    break
                changed.wait(min(remaining, 5))
            row = {"case": name, "status": current.status, "harness_timeout": expired,
                   "accepted_ms": round((accepted - started) * 1000, 3),
                   "elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
                   "reply_chars": len(current.result), "expected_reply": expected in current.result,
                   "error_present": bool(current.error),
                   "streamed_output_observed": bool(current.first_output_at)}
            report["real_provider_cases"].append(row)
            save()
            print(json.dumps(row), flush=True)
            if current.status != "completed" or expired:
                break
    finally:
        manager.unsubscribe(subscription)
        for task_id in owned:
            current = manager.get(task_id)
            if current and current.status not in backend.TERMINAL_STATES:
                manager.cancel(task_id)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, default=Path(__file__).resolve().parents[1] / "core/galaxyssi-link/backend")
    parser.add_argument("--agent", default="codex")
    parser.add_argument("--selection-rounds", type=int, default=3)
    parser.add_argument("--live", action="store_true", help="Invoke the configured real CLI using its existing login")
    parser.add_argument("--timeout", type=float, default=180, help="Probe-only per-case observation budget in seconds")
    args = parser.parse_args()
    if args.selection_rounds < 1 or args.timeout <= 0:
        parser.error("Positive rounds and timeout are required")
    backend_path = args.backend.resolve(strict=True)
    root = Path(tempfile.mkdtemp(prefix="galaxyssi-task-admission-"))
    isolate_state(root)
    sys.path.insert(0, str(backend_path))
    import main as backend

    report = {"scope": "desktop_task_admission", "synthetic_prompts": True,
              "real_provider": args.live, "phone_mqtt_tested": False,
              "agent": args.agent, "selection_ms": [], "real_provider_cases": [],
              "measurement_clock": "perf_counter", "clock_resolution_seconds": time.get_clock_info("perf_counter").resolution}
    def save():
        (root / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(json.dumps({"report_directory": str(root), "real_provider": args.live}), flush=True)
    try:
        profiler = cProfile.Profile()
        profiler.enable()
        try:
            for _ in range(args.selection_rounds):
                started = time.perf_counter()
                assert backend._desktop_agent_for("\u4f60\u597d", args.agent) == args.agent
                report["selection_ms"].append(round((time.perf_counter() - started) * 1000, 3))
        finally:
            profiler.disable()
            profiler.dump_stats(str(root / "selection.prof"))
        save()
        print(json.dumps({"selection_ms": report["selection_ms"]}), flush=True)
        if args.live:
            live_cases(backend, args.agent, args.timeout, report, save)
    finally:
        backend.shutdown_acp_agent_runtime()
        backend.shutdown_external_cli_process_pool()
        backend.shutdown_desktop_agent_runtime_server(wait=True)
        save()
    return 0 if not args.live or (len(report["real_provider_cases"]) == 3 and all(
        row["status"] == "completed" and row["expected_reply"]
        for row in report["real_provider_cases"])) else 1


if __name__ == "__main__":
    raise SystemExit(main())
