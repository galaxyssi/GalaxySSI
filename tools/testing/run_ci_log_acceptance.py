"""Read real head-bound CI evidence, optionally through the local Agent loop."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--endpoint")
    parser.add_argument("--model")
    parser.add_argument("--prompt", default="Inspect the actual failed CI job logs and summarize the diagnosis. Do not edit files.")
    args = parser.parse_args()
    if bool(args.endpoint) != bool(args.model):
        parser.error("Supply both --endpoint and --model for an optional local inference run")
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.ci_log_tools import CiLogTools
    from evolution_v2.common import atomic_write_json
    from evolution_v2.github_client import GitHubClient
    from evolution_v2.local_action_contract import action_schema
    from evolution_v2.local_implementation import implement_locally, implementation_observer
    from evolution_v2.local_planning import infer_local_plan, local_plan_endpoint
    client = GitHubClient(root)
    current = client.pull_request_head(args.pr)
    tools = CiLogTools(client, {"url": args.pr, "head_sha": current["head_sha"], "head_ref": current["head_ref"]},
                       read_only_snapshot=current)
    report = {"pr": args.pr, "head_sha": current["head_sha"], "read_only": True, "events": [], "calls": []}
    def event(name, **data):
        report["events"].append({"event": name, **data})
        atomic_write_json(args.output, report)
        print(name + ": " + data.get("operation", ""), flush=True)
    if args.endpoint:
        config = {"url": args.endpoint, "model": args.model}
        local_plan_endpoint(config)
        def infer(messages):
            start = time.monotonic()
            response = infer_local_plan(messages, config=config, response_schema=action_schema(ci_logs=True))
            report["calls"].append({"seconds": time.monotonic() - start, "response": response})
            atomic_write_json(args.output, report)
            print(response, flush=True)
            return response
        with implementation_observer(threading.Event(), event):
            report["summary"] = implement_locally(args.prompt, root, scope=(), infer=infer, ci_logs=tools)
        report["log_observed"] = any(row.get("operation") == "ci_log" and row.get("ok")
                                     for row in report["events"])
    else:
        checks = tools.execute({"operation": "ci_checks"})
        report["checks"] = checks
        reports = []
        for check in checks["checks"]:
            if check["kind"] != "check_run":
                continue
            try:
                reports.append(tools.execute({"operation": "ci_log", "check_id": check["id"]}))
            except ValueError as exc:
                reports.append({"check_id": check["id"], "error": str(exc)})
        report["logs"] = reports
        report["log_observed"] = bool(reports) and all("error" not in row for row in reports)
    atomic_write_json(args.output, report)
    print("Read-only CI evidence written to " + str(args.output), flush=True)
    return 0 if report["log_observed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
