#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def resolve_repo_root(value: str = "") -> Path:
    configured = str(value or os.environ.get("GALAXYSSI_SOURCE_ROOT") or "").strip()
    return (
        Path(configured).expanduser().resolve()
        if configured
        else Path(__file__).resolve().parents[3]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect GalaxySSI self-evolution prerequisites")
    parser.add_argument("--repo-root", default="")
    args = parser.parse_args()

    repo_root = resolve_repo_root(args.repo_root)
    backend = repo_root / "apps/desktop/core/galaxyssi-link/backend"
    if not backend.is_dir():
        parser.error(f"GalaxySSI backend was not found under: {repo_root}")
    sys.path.insert(0, str(backend))

    from evolution_v2.preflight import PreflightInspector

    result = PreflightInspector(repo_root).inspect()
    print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
    return 0 if result["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
