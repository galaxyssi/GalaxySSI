"""Read-only live verifier controls derived from a hash-bound historical publication proof.

This replays evidence, not a new autonomous implementation or publication. It never
changes campaign state, source files or GitHub publication metadata.
"""
from copy import deepcopy
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--review-mode", choices=("legacy", "source-parts"), default="legacy")
    parser.add_argument("--case", action="append", dest="selected_cases",
                        help="Run named controls only; the report is explicitly partial")
    parser.add_argument("--prepare-only", action="store_true",
                        help="Inspect source partition and scope compilation only; never grants an acceptance verdict")
    parser.add_argument("--audit-preparation", type=Path,
                        help="Audit previously observed preparation against the same immutable replay evidence")
    args = parser.parse_args()
    if args.prepare_only and args.review_mode != "source-parts":
        parser.error("--prepare-only requires --review-mode source-parts")
    if args.audit_preparation and not args.prepare_only:
        parser.error("--audit-preparation requires --prepare-only")
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / "apps/desktop/core/galaxyssi-link/backend"))
    from evolution_v2.common import atomic_write_json, sha256_text, stable_json
    from evolution_v2.ci_snapshot import target
    from evolution_v2.final_campaign_review import review_final_evidence
    from evolution_v2.local_planning import infer_local_plan, local_plan_endpoint
    config = {"url": args.endpoint, "model": args.model}
    local_plan_endpoint(config)
    proof = json.loads(args.proof.read_text(encoding="utf-8"))
    if sha256_text(stable_json(proof)) != args.proof.stem:
        raise ValueError("Historical proof content hash does not match")
    evidence = proof["evidence"]
    saved = json.loads(args.audit_preparation.read_text(encoding="utf-8")) if args.audit_preparation else None
    if saved and saved.get("proof_id") != args.proof.stem:
        raise ValueError("Saved preparation belongs to another historical proof")
    def command(argv):
        return subprocess.run(argv, check=True, capture_output=True, text=True, encoding="utf-8", timeout=120).stdout
    def verify_publications():
        for item in evidence["publications"].values():
            repository, number = target(item["url"])
            current = json.loads(command(["gh", "api", f"repos/{repository}/pulls/{number}"]))
            if (current["head"]["sha"] != item["head_sha"] or current["title"] != item["title"]
                    or (current["body"] or "") != item["body"] or not current["merged"]
                    or current["merge_commit_sha"] != item["merge_commit_sha"]):
                raise ValueError("Publication changed since the immutable replay evidence")
    verify_publications()
    for candidate in evidence["candidates"].values():
        for name, contents in candidate["files"].items():
            for field, commit in (("before", "base_commit"), ("after", "candidate_commit")):
                actual = command(["git", "-C", str(args.source), "show", f"{candidate[commit]}:{name}"])
                if actual != contents[field]:
                    raise ValueError("Immutable Git content does not match the historical proof")
    missing_content = deepcopy(evidence)
    for candidate in missing_content["candidates"].values():
        candidate["diff"] = ""
        for contents in candidate["files"].values():
            contents["after"] = contents["before"]
            contents["after_line_count"] = contents["before_line_count"]
    wrong_language = deepcopy(evidence)
    for item in wrong_language["publications"].values():
        item.update(title="\u6dfb\u52a0\u8fd0\u8425\u6062\u590d\u8bf4\u660e", body="\u5df2\u8ffd\u52a0\u8fd0\u8425\u6062\u590d\u5c0f\u8282\uff0c\u4fdd\u7559\u539f\u5185\u5bb9\u3002")
    missing_publication = deepcopy(evidence)
    missing_publication["publications"] = {}
    cases = [("original-chinese-goal", evidence, {"pass"}),
             ("missing-requested-content", missing_content, {"fail"}),
             ("publication-language-mismatch", wrong_language, {"fail"}),
             ("missing-publication-evidence", missing_publication, {"fail", "inconclusive"})]
    if args.review_mode == "source-parts":
        alternative = {"graph": {"objective": "PR \u6807\u9898\u5305\u542b Recovery\uff0c\u6216\u8005 PR \u6b63\u6587\u5305\u542b Recovery\uff1b\u76ee\u6807\u5206\u652f\u662f main\u3002"},
            "publications": {"n": {"title": "Maintenance update", "body": "Recovery notes", "base_ref": "main"}},
            "candidates": {}, "current_integrations": {}}
        no_alternative = deepcopy(alternative)
        no_alternative["publications"]["n"]["body"] = "Maintenance notes"
        cases.extend([("controlled-or-one-true", alternative, {"pass"}),
                      ("controlled-or-both-false", no_alternative, {"fail"})])
    if args.selected_cases:
        unknown = set(args.selected_cases) - {name for name, _, _ in cases}
        if unknown:
            parser.error("Unknown replay controls: " + ", ".join(sorted(unknown)))
        cases = [case for case in cases if case[0] in args.selected_cases]
    report = {"scope": "historical-evidence live-model replay, not autonomous publication",
              "proof_id": args.proof.stem, "model": args.model, "review_mode": args.review_mode,
              "partial": bool(args.selected_cases), "prepare_only": args.prepare_only,
              "audit_preparation": bool(args.audit_preparation),
              "cases": [], "publication_unchanged": False}
    previous_review = None
    for name, source, expected in cases:
        result = {"name": name, "expected": sorted(expected), "evidence": source}
        report["cases"].append(result)
        started = time.monotonic()
        print("Starting " + name, flush=True)
        try:
            def observed(response):
                result["response"] = response
                atomic_write_json(args.output, report)
            infer = lambda messages, **kwargs: infer_local_plan(messages, config=config, **kwargs)
            if args.prepare_only:
                from evolution_v2.original_goal_evidence import original_goal_catalog
                from evolution_v2.original_goal_requirements import compile_requirements
                def prepared(record):
                    result["preparation"] = record
                    atomic_write_json(args.output, report)
                    print(json.dumps({"case": name, "observations": [key for key in record if key.endswith("response")]}), flush=True)
                if args.audit_preparation:
                    from evolution_v2.evidence_scope import strict_json, validate_scopes
                    from evolution_v2.original_goal_partition import parse_partition
                    from evolution_v2.original_goal_scope_audit import audit_scopes
                    matches = [case for case in saved["cases"] if case["name"] == name]
                    if len(matches) != 1 or stable_json(matches[0]["evidence"]) != stable_json(source):
                        raise ValueError("Saved control evidence is not identical to the current immutable replay")
                    preparation = deepcopy(matches[0]["preparation"])
                    clauses = parse_partition(preparation["partition_response"], source["graph"]["objective"])
                    requirements = {"part-" + str(index + 1): clause for index, clause in enumerate(clauses)}
                    catalog = original_goal_catalog(source)
                    scopes = validate_scopes(strict_json(preparation["scope_response"]), requirements, catalog)
                    def audited(response):
                        preparation["audit_response"] = response
                        prepared(preparation)
                    preparation["audit"] = audit_scopes(source["graph"]["objective"], requirements, scopes,
                                                       catalog, infer, audited)
                    result["preparation"] = preparation
                else:
                    result["preparation"] = compile_requirements(source["graph"]["objective"], original_goal_catalog(source),
                                                                 infer, observed=prepared)
                result["sufficient"] = all(row["sufficient"] for row in result["preparation"]["audit"].values())
                result["prepared"] = True
            elif args.review_mode == "source-parts":
                from evolution_v2.original_goal_review import review_original_goal
                progress = None
                def checkpoint(proof):
                    nonlocal previous_review, progress
                    previous_review = proof
                    result["requirement_review"] = proof
                    atomic_write_json(args.output, report)
                    state = [(key, row.get("status")) for key, row in proof["checks"].items()]
                    if state != progress:
                        progress = state
                        print(json.dumps({"case": name, "parts": len(proof.get("requirements", {}).get("parts", [])),
                                          "checks": state}), flush=True)
                checked = review_original_goal(source, infer, reviewer_id=sha256_text(stable_json(config)),
                                               previous=previous_review, checkpoint=checkpoint)
                result["assessment"] = {"verdict": checked["verdict"], "parts": len(checked["checks"])}
            else:
                result.update(review_final_evidence(source, infer, observed=observed))
            if not args.prepare_only:
                result["passed"] = result["assessment"]["verdict"] in expected
        except Exception as error:
            result.update(passed=False, error_type=type(error).__name__, error=str(error))
        result["seconds"] = round(time.monotonic() - started, 3)
        atomic_write_json(args.output, report)
        print(json.dumps({key: value for key, value in result.items() if key not in {"evidence", "response", "requirement_review", "preparation"}}, ensure_ascii=True), flush=True)
    verify_publications()
    report["publication_unchanged"] = True
    result_key = "prepared" if args.prepare_only else "passed"
    report[result_key] = all(row.get(result_key, False) for row in report["cases"])
    atomic_write_json(args.output, report)
    return 0 if report[result_key] else 1


if __name__ == "__main__":
    raise SystemExit(main())
