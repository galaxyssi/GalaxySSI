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
        "test_mqtt_agent_recovery",
        "test_mqtt_task_turn_routing",
        "test_mqtt_codex_steering",
        "test_attachment_request_broker",
        "test_attachment_recovery_phases",
        "tests.test_mqtt_durable_delivery",
        "tests.test_link_delivery",
        *sorted(path.stem for path in backend.glob("test_blob_*.py")),
    ]
    with tempfile.TemporaryDirectory(prefix="galaxyssi-run-kernel-tests-") as home:
        environment = {
            **os.environ, "HOME": home, "USERPROFILE": home,
            "APPDATA": home, "GALAXYSSI_STATE_DIR": str(Path(home) / "GalaxySSI"),
            "GALAXYSSI_DATA_DIR": str(Path(home) / "data"),
            "GALAXYSSI_DATABASE_PATH": str(Path(home) / "messages.sqlite3"),
            "GALAXYSSI_CONFIG_PATH": str(Path(home) / "agents.json"),
            "GALAXYSSI_WORKSPACE_ROOT": str(Path(home) / "workspaces"),
            "GALAXYSSI_DISABLE_EXTERNAL_SERVICES": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        if sys.argv[1:2] == ["--pytest"]:
            return subprocess.call(
                [sys.executable, "-m", "pytest", *(sys.argv[2:] or ["-q", "core/galaxyssi-link/backend"])],
                cwd=root / "apps" / "desktop", env=environment,
            )
        return subprocess.call(
            [sys.executable, "-m", "unittest", *(sys.argv[1:] or modules), "-q"],
            cwd=backend, env=environment,
        )


if __name__ == "__main__":
    raise SystemExit(main())
