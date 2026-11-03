"""Explicit reported CI success, separate from GitHub's merge-friendly green state.

This is a necessary integration gate, not proof of test coverage or scientific truth.
Recompute from the retained observations, never trust an aggregate passed flag alone.
"""
from __future__ import annotations

import re

from .common import sha256_text, stable_json


def fingerprint(sha, rows):
    return sha256_text(stable_json({"head": sha, "checks": sorted(
        ({key: row.get(key) for key in ("kind", "id", "name", "head_sha", "status", "outcome", "conclusion")}
         for row in rows), key=lambda row: (row["kind"], row["id"]))}))


def verification_issue(snapshot, *, repository=None, sha=None):
    """Empty means every reported check explicitly succeeded on the bound commit."""
    if not isinstance(snapshot, dict):
        return "CI observations are unavailable"
    observed_sha, observed_repo = snapshot.get("head_sha"), snapshot.get("repository")
    if (not isinstance(observed_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", observed_sha)
            or not isinstance(observed_repo, str)
            or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", observed_repo)
            or (sha is not None and observed_sha != sha)
            or (repository is not None and observed_repo != repository)):
        return "CI observations do not match the required repository and commit"
    if (snapshot.get("passed") is not True or snapshot.get("status") not in ("passed", "merged")
            or any(type(snapshot.get(key)) is not int or snapshot[key] != 0 for key in ("failed", "pending"))):
        return "CI observations are failed, pending or incomplete"
    rows = snapshot.get("checks")
    if not isinstance(rows, list) or not rows:
        return "No CI checks were observed"
    identities, contexts = set(), set()
    for row in rows:
        if not isinstance(row, dict):
            return "CI check evidence is malformed"
        kind, number, name = row.get("kind"), row.get("id"), row.get("name")
        if (kind not in ("check_run", "commit_status") or type(number) is not int or number <= 0
                or not isinstance(name, str) or not name.strip() or row.get("head_sha") != observed_sha):
            return "CI check identity or commit evidence is incomplete"
        if (kind, number) in identities or (kind == "commit_status" and name in contexts):
            return "CI check evidence is duplicated"
        identities.add((kind, number))
        if kind == "commit_status":
            contexts.add(name)
        expected_status = "completed" if kind == "check_run" else "success"
        if (row.get("outcome") != "passed" or row.get("conclusion") != "success"
                or row.get("status") != expected_status):
            return "Every reported CI check must explicitly succeed; skipped/neutral is not verification"
    if snapshot.get("fingerprint") != fingerprint(observed_sha, rows):
        return "CI observation fingerprint does not match the retained checks"
    return ""
