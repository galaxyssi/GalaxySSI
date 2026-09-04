"""CLI entry points used by immutable V2 quality gates."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Permit direct execution from the backend package path.
if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from evolution_v2.gates import StaticEvolutionGuard
    from evolution_v2.policy import EvolutionPolicy
    from evolution_v2.runtime_smoke import run as runtime_smoke
    from evolution_v2.snapshots import AndroidCandidateTester
else:
    from .gates import StaticEvolutionGuard
    from .policy import EvolutionPolicy
    from .runtime_smoke import run as runtime_smoke
    from .snapshots import AndroidCandidateTester


def main() -> int:
    parser = argparse.ArgumentParser(description="GalaxySSI Self-Evolution V2 gates")
    subparsers = parser.add_subparsers(dest="command", required=True)

    guard = subparsers.add_parser("guard")
    guard.add_argument("--repo-root", default=".")
    guard.add_argument("--config", default="config/evolution-policy.json")

    desktop = subparsers.add_parser("desktop-runtime")
    desktop.add_argument("--backend-dir", default="apps/desktop/core/galaxyssi-link/backend")
    desktop.add_argument("--timeout", type=int, default=60)
    desktop.add_argument("--reload-cycles", type=int, default=2)

    android = subparsers.add_parser("android-device")
    android.add_argument("--candidate", default="apps/android/app/build/outputs/apk/debug/app-debug.apk")
    android.add_argument("--snapshot-root", required=True)
    android.add_argument("--package", default="com.galaxyssi.chat")
    android.add_argument("--serial", default="")
    android.add_argument("--wait", type=int, default=8)

    args = parser.parse_args()
    try:
        if args.command == "guard":
            root = Path(args.repo_root).resolve()
            policy = EvolutionPolicy(root, root / args.config)
            result = StaticEvolutionGuard(root, policy).inspect().public()
            print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
            return 0 if result["passed"] else 1
        if args.command == "desktop-runtime":
            result = runtime_smoke(
                Path(args.backend_dir),
                args.timeout,
                reload_cycles=args.reload_cycles,
            )
            print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
            return 0
        if args.command == "android-device":
            tester = AndroidCandidateTester(
                Path(args.snapshot_root),
                package_name=args.package,
                serial=args.serial,
            )
            result = tester.run(Path(args.candidate), launch_wait_seconds=args.wait)
            print(json.dumps(result, ensure_ascii=True, indent=2, sort_keys=True))
            return 0 if result.get("passed") else 1
        raise RuntimeError(f"Unknown command: {args.command}")
    except Exception as exc:
        print(json.dumps({"passed": False, "error": str(exc)[:8_000]}, ensure_ascii=True, indent=2, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
