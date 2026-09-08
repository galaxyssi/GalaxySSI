"""Opt-in real local compiler matrix; never edits candidates or grants acceptance."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time


CASES = [
    ("heading", 'Append a Markdown section named "Restart checklist" to docs/a.md. Preserve existing content.',
     ["docs/a.md"], [("markdown_heading", "docs/a.md", "Restart checklist")]),
    ("semantic", "Explain how to diagnose stale workers in docs/a.md. Choose appropriate wording and organization.",
     ["docs/a.md"], []),
    ("remove", 'Remove the literal text "legacy-token" from docs/a.md.',
     ["docs/a.md"], [("absent", "docs/a.md", "legacy-token")]),
    ("include", 'Add the exact message "Ready to resume" to docs/a.md.',
     ["docs/a.md"], [("contains", "docs/a.md", "Ready to resume")]),
    ("paths", "Read docs/Status.md and improve its explanation of recovery. Open a PR after validation.",
     ["docs/Status.md"], []),
    ("multi_file", 'Add a section named "Startup" to docs/a.md and a section named "Shutdown" to docs/b.md.',
     ["docs/a.md", "docs/b.md"], [("markdown_heading", "docs/a.md", "Startup"),
                                ("markdown_heading", "docs/b.md", "Shutdown")]),
    ("punctuation", 'Append the Markdown heading "Recovery: what next?" to docs/a.md and explain the next steps.',
     ["docs/a.md"], [("markdown_heading", "docs/a.md", "Recovery: what next?")]),
    ("no_fixed_title", "Append a new section about recovery to docs/a.md. You may choose its title. Keep the original text.",
     ["docs/a.md"], []),
    ("mixed", 'In docs/a.md, remove the literal "Old status" and include the literal "New status".',
     ["docs/a.md"], [("absent", "docs/a.md", "Old status"), ("contains", "docs/a.md", "New status")]),
    ("chinese_heading", "\u5728 docs/a.md \u672b\u5c3e\u8ffd\u52a0\u540d\u4e3a\u201c\u91cd\u542f\u6062\u590d\u201d\u7684 Markdown \u5c0f\u8282\uff0c\u4fdd\u7559\u539f\u6587\u3002",
     ["docs/a.md"], [("markdown_heading", "docs/a.md", "\u91cd\u542f\u6062\u590d")]),
    ("chinese_semantic", "\u8bf7\u6539\u8fdb docs/a.md \u91cc\u7684\u6545\u969c\u6392\u67e5\u8bf4\u660e\uff0c\u5185\u5bb9\u548c\u6807\u9898\u7531\u4f60\u51b3\u5b9a\u3002",
     ["docs/a.md"], []),
    ("unicode_heading", 'Add a Markdown section titled "\u00c9tat de reprise" to docs/a.md.',
     ["docs/a.md"], [("markdown_heading", "docs/a.md", "\u00c9tat de reprise")]),
    ("mixed_language_semantics", "\u8bf7\u5728 docs/a.md \u672b\u5c3e\u8ffd\u52a0\u4e00\u4e2a\u82f1\u6587\u7684 Operational recovery \u5c0f\u8282\uff1a\u8bf4\u660e\u672c\u5730\u6a21\u578b\u6682\u65f6\u4e0d\u53ef\u7528\u65f6\u4fdd\u7559\u7ea6\u675f\uff0c\u6062\u590d\u540e\u91cd\u65b0\u9a8c\u8bc1\u3002\u4fdd\u7559\u539f\u6587\u4e0d\u53d8\uff0c\u521b\u5efa\u82f1\u6587 PR\u3002",
     ["docs/a.md"], [("markdown_heading", "docs/a.md", "Operational recovery")]),
    ("live_campaign_reproduction", "\u8bf7\u6539\u8fdb docs/architecture/source-preservation-contract.md\uff0c\u5728\u6587\u4ef6\u672b\u5c3e\u8ffd\u52a0\u4e00\u4e2a\u82f1\u6587\u7684 Operational recovery \u5c0f\u8282\uff1a\u8bf4\u660e\u672c\u5730\u9a8c\u6536\u6a21\u578b\u4e34\u65f6\u4e0d\u53ef\u7528\u65f6\u4fdd\u7559\u5df2\u6301\u4e45\u5316\u7684\u6e90\u7ea6\u675f\uff0c\u6062\u590d\u540e\u91cd\u65b0\u6821\u9a8c\u6765\u6e90\u8eab\u4efd\u5e76\u91cd\u65b0\u6267\u884c\u5019\u9009\u9a8c\u6536\uff1b\u660e\u786e\u65e7\u7684\u901a\u8fc7\u7ed3\u679c\u4e0d\u80fd\u66ff\u4ee3\u5f53\u524d\u9a8c\u6536\u3002\u4fdd\u7559\u73b0\u6709\u5185\u5bb9\u4e0d\u53d8\uff0c\u4e0d\u4fee\u6539\u5176\u4ed6\u6587\u4ef6\u3002\u7531\u6846\u67b6\u5b8c\u6210\u72ec\u7acb\u9a8c\u8bc1\u5e76\u521b\u5efa\u82f1\u6587\u6807\u9898\u548c\u8bf4\u660e\u7684 self-evolution PR\uff0c\u4e0d\u8981\u58f0\u79f0\u5c1a\u672a\u6267\u884c\u7684\u9a8c\u8bc1\u5df2\u7ecf\u901a\u8fc7\u3002",
     ["docs/architecture/source-preservation-contract.md"],
     [("markdown_heading", "docs/architecture/source-preservation-contract.md", "Operational recovery")],
     "The document lacks a section describing how source constraints are preserved and re-validated during operational recovery when the local acceptance model is temporarily unavailable."),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", choices=[case[0] for case in CASES])
    parser.add_argument("--repeat", type=int, default=1)
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error("--repeat must be positive")
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.common import atomic_write_json
    from evolution_v2.goal_text_contract import COMPILER_VERSION, compile_contract
    from evolution_v2.local_planning import infer_local_plan, local_plan_endpoint
    config = {"url": args.endpoint, "model": args.model}
    local_plan_endpoint(config)
    rows = []
    selected = [case for case in CASES if args.case is None or case[0] == args.case]
    for repetition, (name, goal, paths, expected, *child) in (
            (run + 1, case) for run in range(args.repeat) for case in selected):
        evidence = {"requirements": [{"id": "parent-intent", "text": goal}, {"id": "task", "text": child[0] if child else goal}],
                    "scope": paths, "files": {path: {} for path in paths}}
        calls = []
        def infer(messages, **kwargs):
            started = time.perf_counter()
            response = infer_local_plan(messages, config=config, **kwargs)
            calls.append({"seconds": time.perf_counter() - started, "response": response})
            return response
        print(json.dumps({"case": name, "stage": "running"}), flush=True)
        row = {"name": name, "repetition": repetition, "expected": expected, "passed": False}
        try:
            contract = compile_contract(evidence, infer)
            actual = [(check["kind"], check["path"], check["text"]) for check in contract["checks"]]
            row.update(contract=contract, passed=not contract["issues"] and sorted(actual) == sorted(expected))
        except Exception as error:
            row["error"] = str(error)
        row["calls"] = calls
        rows.append(row)
        atomic_write_json(args.output, {"model": args.model, "compiler_version": COMPILER_VERSION,
            "read_only": True, "full_goal_complete": False, "cases": rows})
        print(json.dumps({"case": name, "passed": row["passed"],
                          "seconds": sum(call["seconds"] for call in calls)}), flush=True)
    print(json.dumps({"passed": sum(row["passed"] for row in rows), "total": len(rows)}), flush=True)
    return 0 if all(row["passed"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
