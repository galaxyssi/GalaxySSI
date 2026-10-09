"""Run mocked evidence regressions without importing the active Desktop's state."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


MODULES = (
    "test_collaboration_recall_bridge",
    "test_collaboration_tool_test_bridge",
    "test_codex_tool_evidence",
    "test_agent_tool_evidence",
    "test_codex_conversation_threads",
    "tests.test_mqtt_phone_tool_routing",
)


def main() -> int:
    backend = Path(__file__).resolve().parents[1] / "core" / "galaxyssi-link" / "backend"
    # Some backend modules create durable managers at import time, before setUp patches.
    # Isolate the entire child process, including its module-discovery phase.
    with tempfile.TemporaryDirectory(prefix="galaxyssi-evidence-unit-") as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir()
        environment = dict(os.environ)
        for name in ("HOME", "USERPROFILE", "APPDATA"):
            environment[name] = str(home)
        environment.update({
            "CODEX_HOME": str(home / ".codex"),
            "GALAXYSSI_STATE_DIR": str(root / "state"),
            "GALAXYSSI_DATA_DIR": str(root / "data"),
            "GALAXYSSI_DATABASE_PATH": str(root / "state" / "messages.sqlite3"),
            "GALAXYSSI_CONFIG_PATH": str(root / "state" / "agents.json"),
            "GALAXYSSI_WORKSPACE_ROOT": str(root / "workspaces"),
            "GALAXYSSI_DISABLE_EXTERNAL_SERVICES": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        modules = sys.argv[1:] or MODULES
        return subprocess.run([sys.executable, "-m", "unittest", *modules],
                              cwd=backend, env=environment, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
