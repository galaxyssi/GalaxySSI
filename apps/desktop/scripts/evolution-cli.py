#!/usr/bin/env python3
"""Local CLI for preflight, research, roadmap, diagnostics, health, and audit."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def emit(value) -> None:
    print(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True))


def resolve_repo_root(value: str = "") -> Path:
    configured = str(value or os.environ.get("GALAXYSSI_SOURCE_ROOT") or "").strip()
    return (
        Path(configured).expanduser().resolve()
        if configured
        else Path(__file__).resolve().parents[3]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Control GalaxySSI Self-Evolution V2 locally")
    parser.add_argument("--repo-root", default="")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("preflight")
    sub.add_parser("health")
    research = sub.add_parser("research")
    research.add_argument("--query", default="")
    research.add_argument("--limit", type=int, default=40)
    research.add_argument("--all-sources", action="store_true")
    roadmap = sub.add_parser("roadmap")
    roadmap.add_argument(
        "--goal",
        default="Evolve GalaxySSI into a safe, interoperable, durable personal super Agent."
    )
    roadmap.add_argument("--research-run", action="append", default=[])
    sub.add_parser("scan-issues")
    sub.add_parser("audit")
    sub.add_parser("scheduler-tick")
    args = parser.parse_args()

    repo_root = resolve_repo_root(args.repo_root)
    backend = repo_root / "apps/desktop/core/galaxyssi-link/backend"
    if not backend.is_dir():
        parser.error(f"GalaxySSI backend was not found under: {repo_root}")
    sys.path.insert(0, str(backend))
    os.environ["GALAXYSSI_SOURCE_ROOT"] = str(repo_root)

    from evolution_v2.preflight import PreflightInspector
    from evolution_v2.runtime import evolution_v2_runtime

    if args.command == "preflight":
        result = PreflightInspector(repo_root).inspect()
        emit(result)
        return 0 if result["ready"] else 1

    runtime = evolution_v2_runtime()
    manager = runtime.manager
    if args.command == "health":
        emit(runtime.health())
        return 0
    if args.command == "research":
        run = manager.radar.run(
            args.query,
            trusted_only=not args.all_sources,
            limit=args.limit
        )
        proposals = manager.radar.proposals(run)
        emit({
            "run": run.public(),
            "proposals": [item.public() for item in proposals]
        })
        return 0 if run.items else 1
    if args.command == "roadmap":
        runs = [manager.v2_store.get_research(run_id) for run_id in args.research_run]
        plan = manager.roadmaps.create(
            args.goal,
            [run for run in runs if run is not None]
        )
        emit(plan.public())
        return 0
    if args.command == "scan-issues":
        signals = manager.issue_scanner.scan()
        proposals = [
            manager.issue_scanner.proposal(signal)
            for signal in signals
            if signal.status == "open"
        ]
        emit({
            "signals": [item.public() for item in signals],
            "proposals": [item.public() for item in proposals]
        })
        return 0
    if args.command == "audit":
        integrity = manager.audit.verify()
        emit({
            "integrity": integrity,
            "events": manager.audit.list(limit=100)
        })
        return 0 if integrity["valid"] else 1
    if args.command == "scheduler-tick":
        emit(runtime.scheduler.run_due(force=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
