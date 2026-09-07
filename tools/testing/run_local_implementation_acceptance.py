"""Run real local model edits against a disposable Git worktree, not a fake reply."""
from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--allow-inference", action="store_true")
    args = parser.parse_args()
    if not args.allow_inference or args.state.exists():
        parser.error("Require --allow-inference and a new isolated state directory")
    state = args.state.resolve()
    state.mkdir(parents=True)
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    sys.path.insert(0, str(args.source.resolve() / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.common import atomic_write_json
    from evolution_v2.local_implementation import implement_locally, implementation_observer
    from evolution_v2.local_planning import infer_local_plan
    source, candidate = state / "fixture", state / "candidate"
    source.mkdir()
    def git(*argv):
        subprocess.run(["git", "-C", str(source), *argv], check=True, capture_output=True)
    git("init")
    (source / "version.py").write_text('VERSION = "0.1.0"\n', encoding="utf-8")
    git("add", "version.py")
    git("-c", "user.name=Acceptance", "-c", "user.email=acceptance@example.invalid", "commit", "-m", "Seed isolated fixture")
    git("worktree", "add", "-b", "acceptance-candidate", str(candidate))
    records, observations = [], []
    def infer(messages):
        began = time.monotonic()
        record = {"step": len(records) + 1}
        records.append(record)
        try:
            record["response"] = infer_local_plan(messages, config={"url": args.endpoint, "model": args.model})
            return record["response"]
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - began, 3)
            atomic_write_json(state / "inference.json", records)
            print(json.dumps(record, ensure_ascii=True), flush=True)
    summary, error = "", None
    try:
        with implementation_observer(threading.Event(), lambda event, **data: observations.append({"event": event, **data})):
            summary = implement_locally(args.prompt, candidate, scope=["version.py"], infer=infer)
    except Exception as exc:
        error = {"type": type(exc).__name__, "detail": str(exc)}
    original = (source / "version.py").read_text()
    modified = (candidate / "version.py").read_text()
    try:
        module = ast.parse(modified)
        assignment = module.body[0] if len(module.body) == 1 else None
        valid = (isinstance(assignment, ast.Assign) and len(assignment.targets) == 1
                 and isinstance(assignment.targets[0], ast.Name) and assignment.targets[0].id == "VERSION"
                 and ast.literal_eval(assignment.value) == "0.1.1")
    except Exception:
        valid = False
    changed = subprocess.run(["git", "-C", str(candidate), "diff", "--name-only"], check=True, capture_output=True, text=True).stdout.splitlines()
    evidence = {"component_only": True, "model": args.model, "prompt": args.prompt, "steps": len(records), "observations": observations,
                "summary": summary, "error": error, "original": original, "modified": modified, "changed": changed,
                "passed": error is None and valid and original.strip() == 'VERSION = "0.1.0"' and changed == ["version.py"]}
    atomic_write_json(state / "acceptance.json", evidence)
    print(json.dumps(evidence, ensure_ascii=True, indent=2))
    return 0 if evidence["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
