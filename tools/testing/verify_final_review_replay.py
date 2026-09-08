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
    args = parser.parse_args()
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
    report = {"scope": "historical-evidence live-model replay, not autonomous publication",
              "proof_id": args.proof.stem, "model": args.model, "cases": [], "publication_unchanged": False}
    for name, source, expected in cases:
        result = {"name": name, "expected": sorted(expected), "evidence": source}
        report["cases"].append(result)
        started = time.monotonic()
        print("Starting " + name, flush=True)
        try:
            def observed(response):
                result["response"] = response
                atomic_write_json(args.output, report)
            result.update(review_final_evidence(source,
                lambda messages, **kwargs: infer_local_plan(messages, config=config, **kwargs), observed=observed))
            result["passed"] = result["assessment"]["verdict"] in expected
        except Exception as error:
            result.update(passed=False, error_type=type(error).__name__, error=str(error))
        result["seconds"] = round(time.monotonic() - started, 3)
        atomic_write_json(args.output, report)
        print(json.dumps({key: value for key, value in result.items() if key not in {"evidence", "response"}}, ensure_ascii=True), flush=True)
    verify_publications()
    report["publication_unchanged"] = True
    report["passed"] = all(row["passed"] for row in report["cases"])
    atomic_write_json(args.output, report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
