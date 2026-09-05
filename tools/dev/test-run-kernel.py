"""Run local kernel regressions without opening the user's Desktop task store."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    backend = root / "apps" / "desktop" / "core" / "galaxyssi-link" / "backend"
    modules = [
        "test_agent_run_kernel",
        "test_desktop_agent_runtime_recovery",
        "test_desktop_agent_runtime_server",
        *sorted(path.stem for path in backend.glob("test_agent_task*.py")),
    ]
    with tempfile.TemporaryDirectory(prefix="galaxyssi-run-kernel-tests-") as home:
        environment = {
            **os.environ, "HOME": home, "USERPROFILE": home,
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        return subprocess.call(
            [sys.executable, "-m", "unittest", *modules, "-q"],
            cwd=backend, env=environment,
        )


if __name__ == "__main__":
    raise SystemExit(main())
