"""Subprocess execution helpers that never invoke a shell."""
from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

from .common import redact_text


@dataclass
class CommandResult:
    argv: list[str]
    cwd: str
    returncode: int
    stdout: str
    duration_millis: int

    @property
    def ok(self) -> bool:
        return self.returncode == 0


class SafeRunner:
    def run(
        self,
        argv: Sequence[str],
        cwd: Path,
        *,
        timeout_seconds: int = 120,
        environment: Mapping[str, str] | None = None,
        input_text: str | None = None,
    ) -> CommandResult:
        import time

        values = [str(item) for item in argv]
        if not values or any("\x00" in item for item in values):
            raise ValueError("Unsafe command arguments")
        env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "CI": "1"}
        if environment:
            env.update({str(key): str(value) for key, value in environment.items()})
        started = time.monotonic()
        completed = subprocess.run(
            values,
            cwd=str(Path(cwd)),
            stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=max(1, int(timeout_seconds)),
            shell=False,
            check=False,
            env=env,
        )
        return CommandResult(
            argv=values,
            cwd=str(cwd),
            returncode=completed.returncode,
            stdout=redact_text(completed.stdout, maximum=2_000_000),
            duration_millis=int((time.monotonic() - started) * 1_000),
        )

    @staticmethod
    def which(name: str) -> str:
        return shutil.which(name) or ""
