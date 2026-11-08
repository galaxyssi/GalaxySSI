"""Read native Codex JSONL without delaying visible answers until CLI shutdown."""

from __future__ import annotations

import json
import logging
import subprocess
import threading
import time
from collections.abc import Callable
from pathlib import Path


log = logging.getLogger(__name__)


def supports_json_stream(command: list[str]) -> bool:
    return bool(command) and Path(command[0]).name.lower() in {
        "codex", "codex.exe", "codex.cmd", "codex.bat",
    } and "exec" in command


def collect_codex_stream(
    process: subprocess.Popen,
    *,
    input_bytes: bytes | None,
    timeout: float | None,
    on_event: Callable[[str, str, int], None],
) -> tuple[bytes, bytes]:
    started = time.monotonic()
    stdout: list[bytes] = []
    stderr: list[bytes] = []
    answers: dict[str, str] = {}

    def emit(kind: str, text: str = "") -> None:
        try:
            on_event(kind, text, int((time.monotonic() - started) * 1000))
        except Exception:
            log.warning("Codex progress delivery failed", exc_info=True)

    def read_stdout() -> None:
        for line in iter(process.stdout.readline, b""):
            stdout.append(line)
            try:
                event = json.loads(line)
            except (ValueError, UnicodeError):
                continue
            if not isinstance(event, dict):
                continue
            kind = event.get("type")
            if kind == "turn.started":
                emit("model_started")
            elif kind == "error" and str(event.get("message", "")).startswith("Reconnecting..."):
                emit("reconnecting")
            elif kind == "item.completed":
                item = event.get("item")
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "agent_message" and item.get("text"):
                    answers[str(item.get("id") or len(answers))] = str(item["text"])
                    emit("answer", "\n\n".join(answers.values()))
                elif item.get("type") == "error" and "Falling back from WebSockets" in str(item.get("message", "")):
                    emit("https_fallback")
            elif kind == "turn.completed":
                emit("model_completed")

    def read_stderr() -> None:
        for line in iter(process.stderr.readline, b""):
            stderr.append(line)

    def write_stdin() -> None:
        if process.stdin is not None:
            try:
                if input_bytes is not None:
                    process.stdin.write(input_bytes)
                    process.stdin.flush()
            except (BrokenPipeError, OSError):
                pass
            finally:
                process.stdin.close()

    readers = [threading.Thread(target=read_stdout, daemon=True), threading.Thread(target=read_stderr, daemon=True)]
    writer = threading.Thread(target=write_stdin, daemon=True)
    for reader in readers:
        reader.start()
    writer.start()
    try:
        process.wait(timeout=timeout)
    except BaseException:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=3)
        raise
    finally:
        writer.join(timeout=3)
        for reader, pipe in zip(readers, (process.stdout, process.stderr)):
            reader.join(timeout=3)
            if not reader.is_alive():
                pipe.close()
    return b"".join(stdout), b"".join(stderr)


def final_codex_answer(stdout: str) -> str:
    answers: dict[str, str] = {}
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict) or event.get("type") != "item.completed":
            continue
        item = event.get("item")
        if isinstance(item, dict) and item.get("type") == "agent_message" and item.get("text"):
            answers[str(item.get("id") or len(answers))] = str(item["text"])
    return "\n\n".join(answers.values())
