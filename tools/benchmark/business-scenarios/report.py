"""Aggregate observed device evidence without treating missing runs as passes."""
from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path


def summarize(plan: dict, reports: list[dict]) -> dict:
    planned = {case["id"]: case for case in plan["cases"]}
    seen = set()
    observed, complete = [], []
    for report in reports:
        case_id = report["case_id"]
        if case_id not in planned or case_id in seen:
            raise ValueError(f"Unknown or duplicate case: {case_id}")
        if report["catalog_sha256"] != plan["catalog_sha256"]:
            raise ValueError("Do not combine results from different catalogs")
        seen.add(case_id)
        seen_turns = set()
        for turn in report["turns"]:
            if not 0 <= turn["index"] < len(planned[case_id]["turns"]):
                raise ValueError(f"Invalid turn index: {case_id}")
            if turn["index"] in seen_turns:
                raise ValueError(f"Duplicate turn: {case_id}/{turn['index']}")
            seen_turns.add(turn["index"])
            observed.append((case_id, turn))
            if turn["state"] == "completed":
                complete.append((case_id, turn))
    durations = sorted(turn["elapsed_ms"] for _, turn in complete)
    failed = []
    for case_id, turn in observed:
        reasons = []
        if turn["state"] != "completed":
            reasons.append(turn["state"])
        else:
            if not turn.get("assessment", {}).get("correct"):
                reasons.append("answer_or_format")
            if not turn.get("rendered"):
                reasons.append("transcript_not_rendered")
            if not turn.get("timer_stopped"):
                reasons.append("timer_stop_not_observed")
            if not turn.get("within_latency_target"):
                reasons.append("latency_target")
        if reasons:
            failed.append({"case_id": case_id, "turn": turn["index"], "reasons": reasons})
    planned_turns = sum(len(case["turns"]) for case in planned.values())
    return {
        "suite": plan["suite"], "catalog_sha256": plan["catalog_sha256"],
        "planned_cases": len(planned), "observed_cases": len(seen),
        "planned_turns": planned_turns, "observed_turns": len(observed), "completed_turns": len(complete),
        "unobserved_turns": planned_turns - len(observed),
        "correct_turns": sum(bool(t.get("assessment", {}).get("correct")) for _, t in complete),
        "rendered_turns": sum(bool(t.get("rendered")) for _, t in complete),
        "timer_stopped_turns": sum(bool(t.get("timer_stopped")) for _, t in complete),
        "human_review_pending": sum(bool(t.get("assessment", {}).get("requires_human_review")) for _, t in complete),
        "latency": {"samples": len(durations), "p50_ms": statistics.median(durations) if durations else None,
                    "p95_ms": durations[math.ceil(len(durations) * .95) - 1] if len(durations) >= 30 else None,
                    "maximum_ms": max(durations) if durations else None},
        "failures": failed,
        "overall_status": "needs_review" if len(complete) == planned_turns else "incomplete",
        "limitations": [
            "Numeric oracle does not prove every prose statement or real-world business recommendation.",
            "USB charging temperature/level is not an energy-consumption measurement.",
            "This suite does not replace browser, audio/video, device-control, or adversarial security evals.",
            "Different data records are workload variants, not different intelligence capabilities.",
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    reports = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(args.reports.glob("B[0-9][0-9][0-9].json"))]
    output = summarize(plan, reports)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: output[k] for k in ("observed_cases", "completed_turns", "correct_turns", "latency", "overall_status")}))


if __name__ == "__main__":
    main()
