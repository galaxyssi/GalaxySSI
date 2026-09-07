"""Durable ownership evidence, written before a guarded command can execute."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re


JOB_NAME = re.compile(r"Global\\GalaxySSI-owned-[0-9a-f]{32}")


class ProcessTerminationPending(RuntimeError):
    pass


def task_journal(root: Path, task_id: str) -> Path:
    return Path(root) / "process-owners" / hashlib.sha256(task_id.encode("utf-8")).hexdigest()


def record_job(root: Path, name: str) -> Path:
    if not JOB_NAME.fullmatch(name):
        raise ValueError("Invalid owned job identity")
    root.mkdir(parents=True, exist_ok=True)
    path = root / (name.rsplit("-", 1)[-1] + ".json")
    # A torn record is intentionally retained and prevents uncertain recovery.
    with path.open("x", encoding="ascii") as stream:
        json.dump({"version": 1, "job": name}, stream)
        stream.flush()
        os.fsync(stream.fileno())
    return path


def assert_quiescent(root: Path) -> None:
    from windows_process_job import active_processes

    records = []
    try:
        if not root.exists():
            return
        for path in root.iterdir():
            if not path.is_file() or path.suffix != ".json" or path.stat().st_size > 1024:
                raise ValueError("Invalid process ownership record")
            row = json.loads(path.read_text(encoding="ascii"))
            name = row.get("job", "")
            if (row.get("version") != 1 or not JOB_NAME.fullmatch(name)
                    or path.stem != name.rsplit("-", 1)[-1]):
                raise ValueError("Invalid process ownership identity")
            if active_processes(name) != 0:
                raise ProcessTerminationPending("Previous isolated tool processes have not exited")
            records.append(path)
        # Only verified records are retired; no PID reuse or timeout-based inference.
        for path in records:
            path.unlink()
    except ProcessTerminationPending:
        raise
    except Exception as error:
        raise ProcessTerminationPending("Could not verify previous isolated tool termination") from error


def retire_job(path: Path, name: str) -> None:
    from windows_process_job import active_processes

    try:
        if active_processes(name) == 0:
            path.unlink(missing_ok=True)
    except OSError:
        pass  # Recovery will retry; an observation error is not termination proof.
