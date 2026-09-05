"""Shared storage paths and transaction ownership for Desktop Run data."""

from __future__ import annotations

import os
from pathlib import Path
import sqlite3


RUN_KERNEL_DATABASE_NAME = "agent-run-events-v1.sqlite3"


def desktop_state_root() -> Path:
    configured = os.environ.get("GALAXYSSI_STATE_DIR", "").strip()
    return Path(configured) if configured else Path(os.environ.get("APPDATA") or Path.home()) / "GalaxySSI"


def run_kernel_database_path() -> Path:
    return desktop_state_root() / RUN_KERNEL_DATABASE_NAME


def require_shared_transaction(connection: sqlite3.Connection, path: Path) -> None:
    if not connection.in_transaction:
        raise ValueError("Run persistence requires an active caller-owned transaction")
    databases = connection.execute("PRAGMA database_list").fetchall()
    main = next((row[2] for row in databases if row[1] == "main"), "")
    if not main or Path(main).resolve() != Path(path).resolve():
        raise ValueError("Run persistence transaction belongs to another database")
