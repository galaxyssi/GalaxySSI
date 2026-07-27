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


def run(backend_dir: Path, timeout_seconds: int) -> dict:
    backend = Path(backend_dir).resolve()
    if not (backend / "main.py").is_file():
        raise RuntimeError(f"Backend main.py not found under {backend}")
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="signalasi-evolution-runtime-") as state_dir:
        env = {
            **os.environ,
            "SIGNALASI_STATE_DIR": state_dir,
            "SIGNALASI_DISABLE_EXTERNAL_SERVICES": "1",
            "SIGNALASI_BACKEND_PORT": str(port),
            "PYTHONUNBUFFERED": "1",
        }
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
        process = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", str(port), "--log-level", "warning"],
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
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as stream:
                        response = json.loads(stream.read().decode("utf-8"))
                    if response.get("status") == "ok":
                        return {"passed": True, "port": port, "health": response, "state_isolated": True, "isolated_state": "ephemeral"}
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
            raise RuntimeError(f"{error}\n{output}")
        finally:
            terminate(process)


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
    parser.add_argument("--backend-dir", default="apps/desktop/core/signalasi-link/backend")
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    try:
        result = run(Path(args.backend_dir), args.timeout)
        print(json.dumps(result, ensure_ascii=True, sort_keys=True))
        return 0
    except Exception as exc:
        print(json.dumps({"passed": False, "error": str(exc)[:8_000]}, ensure_ascii=True, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
