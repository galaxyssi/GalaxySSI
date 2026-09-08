"""Read-only, head-bound CI observations for the local repair Agent."""
from __future__ import annotations

import re

from .ci_snapshot import target
from .common import redact_text, sha256_text
from .local_tool_observations import WorkspaceToolError


PAGE = 4096
LOG_LIMIT = 2 * 1024 * 1024


class CiLogTools:
    def __init__(self, client, repair, *, read_only_snapshot=None):
        self.client = client
        self.repair = dict(repair)
        self.repository, _ = target(repair["url"])
        self.lifecycle = {"state": "open", "merged": False}
        if read_only_snapshot is not None:
            self.lifecycle = {key: read_only_snapshot[key] for key in ("state", "merged", "merge_commit_sha")}
        self.cache = None

    def _head(self):
        current = self.client.pull_request_head(self.repair["url"])
        expected = {"repository": self.repository, "head_repository": self.repository,
                    "head_sha": self.repair["head_sha"], "head_ref": self.repair["head_ref"],
                    **self.lifecycle}
        if any(current.get(key) != value for key, value in expected.items()):
            self.cache = None
            raise WorkspaceToolError("ci_target_changed", "The PR identity changed; request a fresh repair task.")

    def _checks(self):
        self._head()
        snapshot = self.client.pull_request_ci_snapshot(self.repair["url"])
        if snapshot.get("head_sha") != self.repair["head_sha"]:
            raise WorkspaceToolError("ci_target_changed", "CI belongs to a different commit.")
        return sorted((row for row in snapshot["checks"] if row["outcome"] == "failed"),
                      key=lambda row: (row["kind"], row["id"]))

    def execute(self, action):
        operation = action.get("operation")
        fields = {"operation", "offset"} if operation == "ci_checks" else {"operation", "check_id", "offset"}
        if operation not in {"ci_checks", "ci_log"} or set(action) - fields:
            raise WorkspaceToolError("invalid_ci_action", "Use ci_checks or ci_log with the declared arguments.")
        offset = action.get("offset", 0 if operation == "ci_checks" else None)
        if offset is not None and (type(offset) is not int or offset < 0):
            raise WorkspaceToolError("invalid_ci_offset", "offset must be a nonnegative integer.")
        if "offset" in action and offset is None:
            raise WorkspaceToolError("invalid_ci_offset", "Omit offset to read the log tail; do not send null.")
        try:
            return self._execute(operation, action, offset)
        except WorkspaceToolError:
            raise
        except Exception as exc:
            # Auth errors and command output can contain secrets. Keep their details out of the run ledger.
            raise WorkspaceToolError("ci_observation_unavailable",
                                    "CI could not be read (" + type(exc).__name__ + "). Retry the observation.") from exc

    def _execute(self, operation, action, offset):
        checks = self._checks()
        if operation == "ci_checks":
            if offset > len(checks):
                raise WorkspaceToolError("invalid_ci_offset", "Offset exceeds the current failed-check list.")
            rows = [{"kind": row["kind"], "id": row["id"], "conclusion": row.get("conclusion"),
                     "name": redact_text(row.get("name"), maximum=200),
                     "summary": redact_text(row.get("summary"), maximum=500),
                     "summary_truncated": len(row.get("summary") or "") > 500}
                    for row in checks[offset:offset + 20]]
            self._head()
            return {"head_sha": self.repair["head_sha"], "checks": rows,
                    "next_offset": offset + len(rows) if offset + len(rows) < len(checks) else None}
        check_id = action.get("check_id")
        if type(check_id) is not int or check_id <= 0:
            raise WorkspaceToolError("invalid_ci_check", "check_id must be a positive integer from ci_checks.")
        matches = [row for row in checks if row["id"] == check_id and row["kind"] == "check_run"]
        if len(matches) != 1:
            raise WorkspaceToolError("ci_check_not_failed", "That check is not a current failed check run.")
        url = matches[0].get("url") or ""
        match = re.fullmatch(r"https://github\.com/" + re.escape(self.repository)
                             + r"/actions/runs/([1-9][0-9]*)/job/([1-9][0-9]*)", url)
        if match is None:
            raise WorkspaceToolError("ci_log_provider_unavailable", "This check has no GitHub Actions job log. Use its summary.")
        run_id, job_id = map(int, match.groups())
        endpoint = f"repos/{self.repository}/actions/jobs/{job_id}"
        job = self.client._api((endpoint,))
        expected = {"id": job_id, "run_id": run_id, "head_sha": self.repair["head_sha"],
                    "check_run_url": f"https://api.github.com/repos/{self.repository}/check-runs/{check_id}",
                    "status": "completed", "conclusion": matches[0]["conclusion"]}
        if not isinstance(job, dict) or any(job.get(key) != value for key, value in expected.items()):
            raise WorkspaceToolError("ci_job_identity_mismatch", "Job metadata does not match the failed check and commit.")
        key = (check_id, job_id, job.get("completed_at"))
        if self.cache is None or self.cache[0] != key:
            result, truncated = self.client.runner.run_bounded(
                ("gh", "api", endpoint + "/logs"), self.client.source_root,
                maximum_bytes=LOG_LIMIT, timeout_seconds=120)
            if not result.ok:
                raise WorkspaceToolError("ci_log_unavailable", "The failed job log is unavailable; retry or inspect another failed check.")
            text = redact_text(result.stdout, maximum=LOG_LIMIT)
            self.cache = (key, text, truncated)
        self._head()
        _, text, truncated = self.cache
        offset = max(0, len(text) - PAGE) if offset is None else offset
        if offset > len(text):
            raise WorkspaceToolError("invalid_ci_offset", "Offset exceeds the available redacted log.")
        end = min(len(text), offset + PAGE)
        return {"check_id": check_id, "job_id": job_id, "head_sha": self.repair["head_sha"],
                "text": text[offset:end], "offset": offset,
                "previous_offset": max(0, offset - PAGE) if offset else None,
                "next_offset": end if end < len(text) else None,
                "available_characters": len(text), "truncated": truncated,
                "log_sha256": sha256_text(text), "untrusted": True}
