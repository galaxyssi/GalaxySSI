"""Head-bound GitHub CI observations; unknown or incomplete evidence is never green."""
from __future__ import annotations

import re
from typing import Any

from .common import redact, sha256_text, stable_json


_PR_URL = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)/?$")
_SHA = re.compile(r"[0-9a-f]{40}$")


class CiObservationError(ValueError):
    pass


def target(url: str) -> tuple[str, int]:
    match = _PR_URL.fullmatch(str(url))
    if match is None:
        raise CiObservationError("A canonical GitHub pull request URL is required")
    return match.group(1), int(match.group(2))


def pull_request(client, url: str) -> dict:
    repository, number = target(url)
    raw = client._api((f"repos/{repository}/pulls/{number}",))
    if not isinstance(raw, dict) or raw.get("number") != number:
        raise CiObservationError("Pull request response identity mismatch")
    head, base = raw.get("head"), raw.get("base")
    if not isinstance(head, dict) or not isinstance(base, dict):
        raise CiObservationError("Pull request branch metadata is missing")
    sha = head.get("sha")
    branch = head.get("ref")
    if not isinstance(sha, str) or not _SHA.fullmatch(sha):
        raise CiObservationError("Pull request head SHA is invalid")
    if (not isinstance(branch, str) or not branch or branch.startswith(("-", "/"))
            or any(ord(c) <= 32 or ord(c) == 127 or c in "~^:?*[\\" for c in branch)
            or ".." in branch or "@{" in branch or branch.endswith(("/", ".", ".lock")) or "//" in branch):
        raise CiObservationError("Pull request head branch is invalid")
    if raw.get("state") not in {"open", "closed"} or type(raw.get("merged")) is not bool:
        raise CiObservationError("Pull request lifecycle is invalid")
    merge_sha = raw.get("merge_commit_sha") if raw["merged"] else ""
    if raw["merged"] and (raw["state"] != "closed" or not isinstance(merge_sha, str) or not _SHA.fullmatch(merge_sha)):
        raise CiObservationError("Merged pull request commit is missing or invalid")
    head_repo, base_repo = head.get("repo"), base.get("repo")
    if not isinstance(head_repo, dict) or not isinstance(base_repo, dict) or not isinstance(base.get("ref"), str):
        raise CiObservationError("Pull request repository metadata is missing")
    return {"url": url, "repository": repository, "number": number, "head_sha": sha, "head_ref": branch,
            "head_repository": head_repo.get("full_name", ""),
            "base_ref": base["ref"], "base_repository": base_repo.get("full_name", ""),
            "state": raw["state"], "merged": raw["merged"], "merge_commit_sha": merge_sha}


def observe(client, url: str) -> dict:
    before = pull_request(client, url)
    if before["state"] != "open" and not before["merged"]:
        return {**before, "status": "closed", "checks": [], "passed": False}
    prefix = f"repos/{before['repository']}/commits/{before['head_sha']}"
    runs = client._api(("--paginate", "--slurp", f"{prefix}/check-runs?filter=latest&per_page=100"))
    statuses = client._api(("--paginate", "--slurp", f"{prefix}/statuses?per_page=100"))
    rows: list[dict] = []
    if not isinstance(runs, list) or not runs or not isinstance(statuses, list) or not statuses:
        raise CiObservationError("CI pagination response is incomplete")
    run_ids = set()
    counts = set()
    for page in runs:
        if not isinstance(page, dict) or not isinstance(page.get("check_runs"), list):
            raise CiObservationError("Invalid check-run page")
        if type(page.get("total_count")) is not int or page["total_count"] < 0:
            raise CiObservationError("Check-run count is missing")
        counts.add(page["total_count"])
        for item in page["check_runs"]:
            if not isinstance(item, dict) or item.get("head_sha") != before["head_sha"]:
                raise CiObservationError("CI check does not match the observed head")
            state, conclusion = item.get("status"), item.get("conclusion")
            if state in {"queued", "in_progress", "waiting", "requested", "pending"}:
                outcome = "pending"
            elif state == "completed" and conclusion in {"success", "neutral", "skipped"}:
                outcome = "passed"
            elif state == "completed" and conclusion in {"failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"}:
                outcome = "failed"
            else:
                outcome = "unknown"
            if type(item.get("id")) is not int or not isinstance(item.get("name"), str):
                raise CiObservationError("Check identity is invalid")
            if item["id"] in run_ids:
                raise CiObservationError("Duplicate check across CI pages; retry a fresh snapshot")
            run_ids.add(item["id"])
            output = item.get("output") or {}
            if not isinstance(output, dict):
                raise CiObservationError("Invalid check output")
            rows.append({"kind": "check_run", "id": item["id"], "name": item["name"], "outcome": outcome,
                         "conclusion": conclusion, "url": item.get("details_url", ""),
                         "summary": output.get("summary", "")})
    if counts != {len(run_ids)}:
        raise CiObservationError("Check pagination changed or is incomplete")
    latest: dict[str, dict] = {}
    for page in statuses:
        if not isinstance(page, list):
            raise CiObservationError("Invalid commit-status page")
        for item in page:
            if not isinstance(item, dict) or not isinstance(item.get("context"), str) or type(item.get("id")) is not int:
                raise CiObservationError("Commit-status identity is invalid")
            context = item["context"]
            if context not in latest or latest[context]["id"] < item["id"]:
                latest[context] = item
    for item in latest.values():
        outcome = {"success": "passed", "pending": "pending", "failure": "failed", "error": "failed"}.get(item.get("state"), "unknown")
        rows.append({"kind": "commit_status", "id": item["id"], "name": item["context"], "outcome": outcome,
                     "conclusion": item.get("state"), "url": item.get("target_url", ""), "summary": item.get("description", "")})
    after = pull_request(client, url)
    if before != after:
        raise CiObservationError("Pull request changed during CI observation; retry a fresh snapshot")
    rows = redact(rows, maximum_text=8000)
    failed = sum(row["outcome"] == "failed" for row in rows)
    pending = sum(row["outcome"] in {"pending", "unknown"} for row in rows)
    status = "pending" if pending or not rows else "failed" if failed else "passed"
    fingerprint = sha256_text(stable_json({"head": before["head_sha"], "checks": sorted(
        ({key: row[key] for key in ("kind", "id", "outcome", "conclusion")} for row in rows),
        key=lambda row: (row["kind"], row["id"]))}))
    return {**before, "status": "merged" if before["merged"] else status,
            "passed": status == "passed", "failed": failed, "pending": pending,
            "checks": rows, "fingerprint": fingerprint}
