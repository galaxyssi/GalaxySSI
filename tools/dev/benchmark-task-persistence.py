"""Isolated local persistence benchmark; does not exercise providers or UI latency."""

import argparse
import json
import math
import os
from pathlib import Path
import statistics
import sys
import tempfile
import time


def distribution(samples: list[float]) -> dict:
    ordered = sorted(samples)
    return {"p50_ms": round(statistics.median(ordered), 3),
            "p95_ms": round(ordered[max(0, math.ceil(len(ordered) * .95) - 1)], 3),
            "p99_ms": round(ordered[max(0, math.ceil(len(ordered) * .99) - 1)], 3)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, default=Path(__file__).resolve().parents[2]
                        / "apps/desktop/core/galaxyssi-link/backend")
    parser.add_argument("--tasks", type=int, default=100)
    arguments = parser.parse_args()
    if arguments.tasks < 1:
        parser.error("--tasks must be positive")
    sys.path.insert(0, str(arguments.backend.resolve()))
    with tempfile.TemporaryDirectory(prefix="galaxyssi-task-persistence-bench-") as home:
        os.environ.update(HOME=home, USERPROFILE=home, APPDATA=home,
                          GALAXYSSI_STATE_DIR=str(Path(home) / "state"),
                          GALAXYSSI_DATA_DIR=str(Path(home) / "data"))
        from agent_task_manager import AgentTaskManager

        path = Path(home) / "benchmark.sqlite3"
        manager = AgentTaskManager(state_path=path)
        latencies = []
        for index in range(arguments.tasks):
            started = time.perf_counter()
            task = manager.create_external(
                task_id=f"benchmark-{index}", agent_id="codex", contact_id="codex",
                source_message_id=f"message-{index}", prompt="Inspect repository context. " * 150,
                client_route_id="benchmark-phone", conversation_id=f"conversation-{index}",
                on_event=lambda _: None,
            )
            latencies.append((time.perf_counter() - started) * 1000)
            for status, result in (("running", ""), ("completed", "verified output\n" * 2500)):
                started = time.perf_counter()
                manager.update(task.task_id, status, result=result)
                latencies.append((time.perf_counter() - started) * 1000)
        started = time.perf_counter()
        restored = AgentTaskManager(state_path=path)
        reopen_ms = (time.perf_counter() - started) * 1000
        last = restored.get(f"benchmark-{arguments.tasks - 1}")
        assert last.result == "verified output\n" * 2500
        assert restored._store.count() == arguments.tasks
        print(json.dumps({"tasks": arguments.tasks, "saves": len(latencies),
                          **distribution(latencies), "reopen_ms": round(reopen_ms, 3),
                          "database_bytes": sum(p.stat().st_size for p in Path(home).glob("*.sqlite3")),
                          "scope": "local persistence only; not a device/provider/UI SLO"}))


if __name__ == "__main__":
    main()
