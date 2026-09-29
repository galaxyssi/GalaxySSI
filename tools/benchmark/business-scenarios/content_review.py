"""Bind explicit evaluator reviews to immutable observed turns, never model prose."""
from __future__ import annotations

import hashlib
import json
import re


def source_digest(report: dict, turn: dict) -> str:
    identity = {key: report.get(key) for key in
                ("catalog_sha256", "case_id", "device", "window_key", "conversation")}
    identity["turn"] = turn
    encoded = json.dumps(identity, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_reviews(plan: dict, reports: list[dict], reviews: list[dict]) -> dict:
    if not isinstance(reviews, list):
        raise ValueError("Content reviews must be an explicit JSON list")
    sources = {(r["case_id"], t["index"]): (r, t) for r in reports for t in r["turns"]}
    planned = {case["id"]: case for case in plan["cases"]}
    accepted = {}
    for review in reviews:
        if not isinstance(review, dict) or type(review.get("schema")) is not int or review["schema"] != 1:
            raise ValueError("Unsupported content review schema")
        case_id, index = review.get("case_id"), review.get("turn_index")
        if not isinstance(case_id, str) or type(index) is not int:
            raise ValueError("Content review requires an exact case and turn")
        key = (case_id, index)
        if key in accepted or key not in sources:
            raise ValueError("Duplicate or unobserved content review")
        report, turn = sources[key]
        if (case_id not in planned or not 0 <= index < len(planned[case_id]["turns"])
                or report.get("catalog_sha256") != plan["catalog_sha256"]
                or "artifact_expectations" not in planned[case_id]["turns"][index]
                or turn.get("state") != "completed"):
            raise ValueError("Review must target an observed completed artifact turn")
        identity = [report.get(k) for k in ("device", "window_key", "conversation")]
        identity += [turn.get(k) for k in ("turn_id", "task_id")]
        if not all(isinstance(value, str) and value for value in identity):
            raise ValueError("Review source lacks durable run and task identity")
        if review.get("source_sha256") != source_digest(report, turn):
            raise ValueError("Review does not match the exact original evidence")
        if review.get("verdict") not in ("pass", "fail"):
            raise ValueError("Content review requires an explicit pass or fail")
        for field in ("reviewer", "notes"):
            if not isinstance(review.get(field), str) or not review[field].strip():
                raise ValueError("Content review needs attribution and substantive notes")
        declared = {}
        for item in turn.get("assessment", {}).get("artifacts", []):
            name, digest = item.get("evidence_file"), item.get("sha256")
            if item.get("received") is True:
                if (not isinstance(name, str) or not name or name in declared
                        or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)):
                    raise ValueError("Ambiguous or unhashed received artifact")
                declared[name] = digest
        checked = review.get("checked_artifacts")
        if not isinstance(checked, list):
            raise ValueError("Content review needs explicit checked artifacts")
        covered = {}
        for item in checked:
            if not isinstance(item, dict):
                raise ValueError("Malformed checked artifact")
            name, digest = item.get("evidence_file"), item.get("sha256")
            if (not isinstance(name, str) or name in covered or name not in declared
                    or digest != declared[name]):
                raise ValueError("Checked artifact identity or hash does not match")
            covered[name] = digest
        text_only = planned[case_id]["turns"][index]["artifact_expectations"].get("text_only")
        if not text_only and not covered:
            raise ValueError("File content review must inspect at least one received file")
        if review["verdict"] == "pass" and covered != declared:
            raise ValueError("A content pass must cover every received artifact")
        accepted[key] = review
    return accepted
