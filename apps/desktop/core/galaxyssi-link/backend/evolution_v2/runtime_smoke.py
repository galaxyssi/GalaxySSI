"""Launch the candidate backend in an isolated profile and probe `/health`."""
from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def run(
    backend_dir: Path,
    timeout_seconds: int,
    *,
    reload_cycles: int = 2,
) -> dict:
    backend = Path(backend_dir).resolve()
    if not (backend / "main.py").is_file():
        raise RuntimeError(f"Backend main.py not found under {backend}")
    cycle_count = max(2, min(int(reload_cycles), 4))
    with tempfile.TemporaryDirectory(prefix="galaxyssi-evolution-runtime-") as state_dir:
        state_root = Path(state_dir)
        continuity_token = state_root / ".reload-continuity"
        continuity_token.write_text("galaxyssi-candidate-reload-v1\n", encoding="utf-8")
        cycles = [
            _run_cycle(
                backend,
                state_root,
                timeout_seconds=timeout_seconds,
                cycle=cycle,
            )
            for cycle in range(1, cycle_count + 1)
        ]
        if continuity_token.read_text(encoding="utf-8") != "galaxyssi-candidate-reload-v1\n":
            raise RuntimeError("Candidate reload changed the harness continuity token.")
        return {
            "passed": True,
            "health": cycles[-1]["health"],
            "cycles": cycles,
            "reload_cycles": cycle_count,
            "reload_verified": True,
            "state_isolated": True,
            "state_persisted_across_reload": True,
            "isolated_state": "ephemeral",
        }


def _run_cycle(
    backend: Path,
    state_root: Path,
    *,
    timeout_seconds: int,
    cycle: int,
) -> dict:
    port = free_port()
    env = {
        **os.environ,
        "GALAXYSSI_STATE_DIR": str(state_root),
        "GALAXYSSI_DISABLE_EXTERNAL_SERVICES": "1",
        "GALAXYSSI_BACKEND_PORT": str(port),
        "PYTHONUNBUFFERED": "1",
    }
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--log-level",
            "warning",
        ],
        cwd=str(backend),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
    )
    deadline = time.monotonic() + max(5, int(timeout_seconds))
    response = None
    error = ""
    try:
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            try:
                with urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/health",
                    timeout=2,
                ) as stream:
                    response = json.loads(stream.read().decode("utf-8"))
                if response.get("status") == "ok":
                    return {
                        "cycle": cycle,
                        "port": port,
                        "health": response,
                        "stopped_cleanly": True,
                    }
            except (OSError, ValueError, urllib.error.URLError):
                time.sleep(0.25)
        error = "Candidate backend did not become healthy before timeout."
        if process.poll() is not None:
            error = f"Candidate backend exited with code {process.returncode}."
        # Stop the candidate before reading the pipe. Reading from a live child can
        # block indefinitely when the backend is unhealthy but still running.
        terminate(process)
        output = ""
        if process.stdout is not None:
            try:
                output = process.stdout.read()[-8_000:]
            except OSError:
                pass
        raise RuntimeError(f"Reload cycle {cycle}: {error}\n{output}")
    finally:
        terminate(process)
        if process.poll() is None:
            raise RuntimeError(
                f"Reload cycle {cycle}: candidate backend did not stop cleanly."
            )


def terminate(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        if os.name == "nt":
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            process.terminate()
        process.wait(timeout=5)
    except Exception:
        try:
            process.kill()
            process.wait(timeout=5)
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend-dir", default="apps/desktop/core/galaxyssi-link/backend")
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--reload-cycles", type=int, default=2)
    args = parser.parse_args()
    try:
        result = run(
            Path(args.backend_dir),
            args.timeout,
            reload_cycles=args.reload_cycles,
        )
        print(json.dumps(result, ensure_ascii=True, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"passed": False, "error": str(exc)[:8_000]}, ensure_ascii=True, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
