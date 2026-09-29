"""Aggregate observed device evidence without treating missing runs as passes."""
from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path
from phase_timing import summarize_phases


def reply_visibly_verified(turn: dict) -> bool:
    return bool(turn.get("driver_schema", 0) >= 3 and turn.get("visual_entry_id")
                and turn.get("rendered") and turn.get("visual_window_focused")
                and turn.get("visual_capture_stable"))


def timer_visibly_verified(turn: dict) -> bool:
    return bool(turn.get("driver_schema", 0) >= 3 and turn.get("timer_observed")
                and turn.get("timer_stopped"))


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
            if not reply_visibly_verified(turn):
                reasons.append("current_reply_visibility_unverified")
            if not timer_visibly_verified(turn):
                reasons.append("timer_stop_not_observed")
            if not turn.get("within_latency_target"):
                reasons.append("latency_target")
            if turn.get("visual_capture_stable") is False:
                reasons.append("visual_capture_unstable")
        if reasons:
            failed.append({"case_id": case_id, "turn": turn["index"], "reasons": reasons})
    planned_turns = sum(len(case["turns"]) for case in planned.values())
    artifact_turns = [(c, t) for c, t in complete
                      if "artifact_expectations" in planned[c]["turns"][t["index"]]]
    def content_correct(case_id, turn):
        assessment = turn.get("assessment", {})
        if "artifact_expectations" in planned[case_id]["turns"][turn["index"]]:
            return bool(assessment.get("correct") and assessment.get("content_verified"))
        return bool(assessment.get("correct"))
    return {
        "suite": plan["suite"], "catalog_sha256": plan["catalog_sha256"],
        "planned_cases": len(planned), "observed_cases": len(seen),
        "planned_turns": planned_turns, "observed_turns": len(observed), "completed_turns": len(complete),
        "unobserved_turns": planned_turns - len(observed),
        "correct_turns": sum(content_correct(c, t) for c, t in complete),
        "artifact_delivery_checks_passed": sum(bool(t.get("assessment", {}).get("correct")) for _, t in artifact_turns),
        "artifact_content_unverified": sum(not t.get("assessment", {}).get("content_verified") for _, t in artifact_turns),
        "rendered_turns": sum(reply_visibly_verified(t) for _, t in complete),
        "timer_stopped_turns": sum(timer_visibly_verified(t) for _, t in complete),
        "legacy_visual_evidence_unverified": sum(t.get("driver_schema", 0) < 3 for _, t in complete),
        "stable_capture_turns": sum(t.get("visual_capture_stable") is True for _, t in complete),
        "capture_stability_unobserved": sum("visual_capture_stable" not in t for _, t in complete),
        "human_review_pending": sum(bool(t.get("assessment", {}).get("requires_human_review")) for _, t in complete),
        "latency": {"samples": len(durations), "p50_ms": statistics.median(durations) if durations else None,
                    "p95_ms": durations[math.ceil(len(durations) * .95) - 1] if len(durations) >= 30 else None,
                    "maximum_ms": max(durations) if durations else None},
        "latency_scope": "reply_terminal_before_artifact_audit_and_ui_checks",
        "phase_latency": summarize_phases([turn for _, turn in complete]),
        "failures": failed,
        "overall_status": "needs_review" if len(complete) == planned_turns else "incomplete",
        "limitations": [
            "Numeric oracle does not prove every prose statement or real-world business recommendation.",
            "USB charging temperature/level is not an energy-consumption measurement.",
            "This suite does not replace browser, audio/video, device-control, or adversarial security evals.",
            "Different data records are workload variants, not different intelligence capabilities.",
            "Stable screenshots still need human review; view-model rendering alone is not pixel verification.",
            "Driver schemas before 3 did not bind captures to the current reply and cannot prove its visibility or timer state.",
            "Artifact container, delivery and save checks do not prove content accuracy, preview fidelity or UI open/save.",
            "Phase times are observations with test overhead, not isolated network latency; pre-schema-4 phases are unmeasured.",
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    reports = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(args.reports.glob("[AB][0-9][0-9][0-9].json"))]
    output = summarize(plan, reports)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: output[k] for k in ("observed_cases", "completed_turns", "correct_turns", "latency", "overall_status")}))


if __name__ == "__main__":
    main()
