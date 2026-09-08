"""Read-only real-publication counterexamples for local scoped semantic verification."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time


def score_case(row, catalog, requirement_id="criterion-1"):
    proof = row.get("proof", {})
    selected = proof.get("scope_contract", {}).get("scopes", {}).get(requirement_id, {}).get("field_ids", [])
    row["selected_fields"] = sorted({catalog[field]["field"] for field in selected})
    row["verdict"] = proof.get("checks", {}).get(requirement_id, {}).get("verdict")
    row["passed"] = (row["verdict"] == row["expected"] and set(row["selected_fields"]) == set(row["expected_fields"])
                     and "error_type" not in row
                     and not str(row.get("error", "")).startswith("Scoped evidence review is invalid"))
    if row["name"] == "compound-publication":
        guards = proof.get("compound", {}).get(requirement_id, {}).get("reviews", [])
        row["failure_binding_verified"] = any(
            guard.get("result", {}).get("verdict") == "fail"
            and {catalog[field]["field"] for field in guard.get("guard", {}).get("field_ids", [])} == {"commit_message"}
            for guard in guards)
        row["unexpected_guard_failures"] = [guard for guard in guards
            if guard.get("result", {}).get("verdict") != "pass"
            and {catalog[field]["field"] for field in guard.get("guard", {}).get("field_ids", [])} != {"commit_message"}]
        row["passed"] = row["passed"] and row["failure_binding_verified"] and not row["unexpected_guard_failures"]
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--recheck-report", type=Path, help="Re-score retained raw evidence without another inference")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    state = args.state.resolve()
    saved = json.loads((state / "acceptance.json").read_text(encoding="utf-8"))
    production = (Path(os.environ.get("APPDATA", Path.home())) / "GalaxySSI").resolve()
    source = Path(saved["source"]).resolve()
    if state == production or state.is_relative_to(production) or state == source or state.is_relative_to(source):
        parser.error("Use isolated acceptance state, never production state")
    os.environ["GALAXYSSI_STATE_DIR"] = str(state)
    os.environ["GALAXYSSI_CONFIG_PATH"] = str(state / "agents.json")
    sys.path.insert(0, str(root / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.campaign_planner import EvolutionCampaignPlanner
    from evolution_v2.common import atomic_write_json, read_json, sha256_text, stable_json
    from evolution_v2.evidence_scope import publication_fields
    from evolution_v2.legacy import EvolutionStore
    from evolution_v2.local_planning import infer_local_plan, local_plan_endpoint
    from evolution_v2.manager import EvolutionManager
    from evolution_v2.scoped_verification import ScopedEvidenceError, verify_scoped

    config = {"url": args.endpoint, "model": args.model}
    local_plan_endpoint(config)
    manager = EvolutionManager(source_root=source, store=EvolutionStore(state / "evolution"))
    planner = EvolutionCampaignPlanner(manager, lambda: {"enabled": False})
    records = [read_json(path) for path in (planner.root / "checkpoint-proofs").glob("*.json")]
    archived = next(item for item in records if item["campaign_id"] == saved["campaign_id"])
    graph = archived["evidence"]["graph"]
    evidence = planner.checkpoints.evidence(graph, manager.v2_store)
    node = archived["decision"]["node_ids"][0]
    catalog = publication_fields(evidence["publications"])
    if args.recheck_report:
        if args.recheck_report.resolve() == args.output.resolve():
            parser.error("Preserve the original report; write adjudication to a different file")
        raw = args.recheck_report.read_text(encoding="utf-8")
        report = json.loads(raw)
        if report["catalog"] != catalog or report["model"] != args.model:
            parser.error("The observed publication or model identity changed")
        report["source_report_hash"] = sha256_text(raw)
        report["adjudication_only"] = True
        for row in report["cases"]:
            row["previous_passed"] = row["passed"]
            score_case(row, catalog)
        report["passed"] = bool(report["cases"]) and all(row["passed"] for row in report["cases"])
        atomic_write_json(args.output, report)
        print(json.dumps({"adjudication_only": True, "passed": report["passed"], "cases": [
            {key: row[key] for key in ("name", "verdict", "previous_passed", "passed")} for row in report["cases"]]}), flush=True)
        return 0 if report["passed"] else 1
    cases = [
        ("original-commit-description", evidence["proposals"][node]["acceptance"][0], "fail", {"commit_message"}),
        ("english-commit", "The head commit message is written in English.", "pass", {"commit_message"}),
        ("main-target", "The pull request targets the main branch.", "pass", {"base_ref"}),
        ("wrong-target", "The pull request targets the develop branch.", "fail", {"base_ref"}),
        ("single-document", "The pull request changes only docs/architecture/source-preservation-contract.md.", "pass", {"files"}),
        ("missing-review", "An independent human reviewer approved this pull request.", "inconclusive", set()),
        ("chinese-english-commit", "\u63d0\u4ea4\u8bf4\u660e\u5e94\u4f7f\u7528\u82f1\u6587\u3002", "pass", {"commit_message"}),
        ("chinese-commit-description", "\u63d0\u4ea4\u8bf4\u660e\u5e94\u6e05\u695a\u8868\u8fbe\u65b0\u589e\u4e86\u8fd0\u884c\u6062\u590d\u5c0f\u8282\u3002", "fail", {"commit_message"}),
        ("compound-destination", "The pull request targets the galaxyssi/GalaxySSI repository and its main branch.",
         "pass", {"repository", "base_ref"}),
        ("compound-publication", "The PR title and description are written in English, and the head commit message clearly describes the addition of the Operational Recovery section.",
         "fail", {"title", "body", "commit_message"}),
        ("alternative-destination", "The pull request targets the develop branch OR the galaxyssi/GalaxySSI repository.",
         "pass", {"repository", "base_ref"}),
    ]
    if set(args.case) - {case[0] for case in cases}:
        parser.error("Unknown case")
    report = {"model": args.model, "campaign_id": saved["campaign_id"], "catalog": catalog,
              "catalog_hash": sha256_text(stable_json(catalog)), "cases": [], "passed": False}
    atomic_write_json(args.output, report)
    for name, requirement, expected, expected_fields in cases:
        if args.case and name not in args.case:
            continue
        row = {"name": name, "requirement": requirement, "expected": expected,
               "expected_fields": sorted(expected_fields), "calls": []}
        report["cases"].append(row)

        def infer(messages, **kwargs):
            call = {"messages": messages, **kwargs}
            row["calls"].append(call)
            atomic_write_json(args.output, report)
            started = time.monotonic()
            try:
                response = infer_local_plan(messages, config=config, **kwargs)
                call["response"] = response
                return response
            except Exception as error:
                call["error"] = str(error)
                raise
            finally:
                call["seconds"] = time.monotonic() - started
                atomic_write_json(args.output, report)

        print("Reviewing " + name, flush=True)
        started = time.monotonic()
        requirement_id = "criterion-1"
        try:
            row["proof"] = verify_scoped({requirement_id: requirement}, catalog, infer)
        except ScopedEvidenceError as error:
            row.update(proof=error.proof, error=str(error))
        except Exception as error:
            row.update(error_type=type(error).__name__, error=str(error))
        # Parse errors and accidental exceptions must never count as a correctly rejected counterexample.
        score_case(row, catalog, requirement_id)
        row["seconds"] = time.monotonic() - started
        atomic_write_json(args.output, report)
        print(json.dumps({key: row[key] for key in ("name", "verdict", "selected_fields", "passed", "seconds")}), flush=True)
    refreshed = publication_fields(planner.checkpoints.evidence(graph, manager.v2_store)["publications"])
    report["publication_unchanged"] = refreshed == catalog
    report["passed"] = (bool(report["cases"]) and report["publication_unchanged"]
                        and all(row["passed"] for row in report["cases"]))
    atomic_write_json(args.output, report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
