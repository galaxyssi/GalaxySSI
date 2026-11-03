"""Read thread-scoped Codex usage estimates without starting model work."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time
import uuid

BACKEND = Path(__file__).resolve().parents[3] / "apps/desktop/core/galaxyssi-link/backend"
sys.path.insert(0, str(BACKEND))
from codex_trial_usage_audit import audit, digest, read_capture  # noqa: E402

FORMAT = "galaxyssi.codex-thread-usage-reconciliation.v1"
MAX_COUNTER = 2**53 - 1
COUNTERS = {"inputTokens": "input_tokens", "cachedInputTokens": "cached_input_tokens",
            "netNewInputTokens": "net_new_input_tokens", "outputTokens": "output_tokens", "totalTokens": "total_tokens"}
COMPARABLE = ("input_tokens", "cached_input_tokens", "output_tokens", "total_tokens")


def thread_id(value):
    if not isinstance(value, str):
        raise ValueError("Exact provider thread UUID required")
    try:
        parsed = uuid.UUID(value)
    except ValueError:
        raise ValueError("Exact provider thread UUID required") from None
    if str(parsed) != value:
        raise ValueError("Canonical provider thread UUID required")
    return value


def integer(value):
    return type(value) is int and 0 <= value <= MAX_COUNTER


def normalize(response, expected_thread_id):
    thread_id(expected_thread_id)
    result = {"status": "unavailable", "provider_thread_id": expected_thread_id,
              "source": "account/usage/read.threadUsage", "scope": "estimated_thread_lifetime_not_trial",
              "groups": [], "estimated_thread_tokens": None,
              "estimated_usage_credits_micros": None, "estimated_usage_usd_micros": None,
              "actual_served_model_attested": False, "provider_request_count": None, "billed_cost": None, "issues": []}
    if not isinstance(response, dict):
        return {**result, "status": "invalid", "issues": ["response_not_object"]}
    value = response.get("threadUsage")
    if value is None:
        return {**result, "issues": ["thread_usage_unavailable_no_account_fallback"]}
    if not isinstance(value, dict) or value.get("threadId") != expected_thread_id:
        return {**result, "status": "invalid", "issues": ["thread_usage_identity_mismatch"]}
    issues = result["issues"]
    for source, target, required in (("estimatedUsageCreditsMicros", "estimated_usage_credits_micros", True),
                                     ("estimatedUsageUsdMicros", "estimated_usage_usd_micros", False)):
        number = value.get(source)
        if integer(number):
            result[target] = number
        elif number is not None or required:
            issues.append(target + "_invalid")
    groups = value.get("groups")
    if not isinstance(groups, list):
        return {**result, "status": "invalid", "issues": issues + ["groups_not_array"]}
    seen = set()
    for index, group in enumerate(groups):
        if not isinstance(group, dict):
            issues.append(f"group_{index}:not_object")
            continue
        row = {"index": index}
        for field in ("model", "reasoningEffort", "speed"):
            label = group.get(field)
            if label is None or (isinstance(label, str) and 0 < len(label) <= 200 and not any(ord(c) < 32 for c in label)):
                row[field] = label
            else:
                row[field] = None
                issues.append(f"group_{index}:{field}_invalid")
        for source, target in COUNTERS.items():
            number = group.get(source)
            row[target] = number if integer(number) else None
            if number is not None and not integer(number):
                issues.append(f"group_{index}:{target}_invalid")
        number = group.get("estimatedUsageCreditsMicros")
        row["estimated_usage_credits_micros"] = number if integer(number) else None
        if not integer(number):
            issues.append(f"group_{index}:credits_invalid")
        identity = tuple(row[field] for field in ("model", "reasoningEffort", "speed"))
        if identity in seen:
            issues.append("duplicate_or_ambiguous_usage_group")
        seen.add(identity)
        if all(row[field] is not None for field in ("input_tokens", "output_tokens", "total_tokens")):
            if row["input_tokens"] + row["output_tokens"] != row["total_tokens"]:
                issues.append(f"group_{index}:inconsistent_token_total")
        if row["cached_input_tokens"] is not None and row["input_tokens"] is not None:
            if row["cached_input_tokens"] > row["input_tokens"]:
                issues.append(f"group_{index}:cached_exceeds_input")
        result["groups"].append(row)
    if not groups:
        issues.append("empty_groups_not_assumed_zero")
    if result["groups"] and all(row["estimated_usage_credits_micros"] is not None for row in result["groups"]):
        if sum(row["estimated_usage_credits_micros"] for row in result["groups"]) != result["estimated_usage_credits_micros"]:
            issues.append("group_credit_sum_mismatch")
    if not issues:
        counts = {field: sum(row[field] for row in result["groups"]) if all(row[field] is not None for row in result["groups"])
                  else None for field in COUNTERS.values()}
        if any(number is not None and not integer(number) for number in counts.values()):
            issues.append("token_sum_out_of_range")
        else:
            result["estimated_thread_tokens"] = counts
    result["status"] = "invalid" if issues else "available"
    return result


class RpcError(RuntimeError):
    def __init__(self, value):
        super().__init__("Read-only usage RPC failed")
        self.code = value.get("code") if isinstance(value, dict) and type(value.get("code")) is int else None
        self.digest = digest(value)


class Client:
    """An isolated connection with no model, tool-execution or mutation methods."""

    def __init__(self, executable, cwd):
        self.process = subprocess.Popen(
            [str(executable), "app-server", "--listen", "stdio://"], cwd=cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace",
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.responses = queue.Queue(maxsize=32)
        self.next_id = 0
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        try:
            for line in self.process.stdout:
                if len(line) > 16 * 1024 * 1024:
                    break
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if isinstance(value, dict) and "id" in value:
                    try:
                        self.responses.put_nowait(value)
                    except queue.Full:
                        break
        finally:
            try:
                self.responses.put_nowait(None)
            except queue.Full:
                pass

    def _write(self, value):
        self.process.stdin.write(json.dumps(value, ensure_ascii=True) + "\n")
        self.process.stdin.flush()

    def request(self, method, params, timeout=30):
        if method == "account/usage/read":
            if not isinstance(params, dict) or set(params) != {"threadId"}:
                raise ValueError("Account-wide usage is prohibited")
            thread_id(params["threadId"])
        elif method != "initialize":
            raise ValueError("Only initialization and thread-scoped usage reads allowed")
        self.next_id += 1
        request_id = self.next_id
        self._write({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Usage response deadline elapsed")
            try:
                response = self.responses.get(timeout=remaining)
            except queue.Empty:
                raise TimeoutError("Usage response deadline elapsed") from None
            if response is None:
                raise RuntimeError("Usage app-server exited")
            if "method" in response:
                raise RuntimeError("Unexpected server request; no action authorized")
            if type(response.get("id")) is not int or response["id"] != request_id:
                continue
            if "error" in response:
                raise RpcError(response["error"])
            return response.get("result")

    def initialize(self):
        self.request("initialize", {"clientInfo": {"name": "galaxyssi-thread-usage-audit", "version": "1"},
                                    "capabilities": {"experimentalApi": True}})
        self._write({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.reader.join(timeout=2)
        for stream in (self.process.stdin, self.process.stdout):
            if stream:
                stream.close()


def private_destination(value):
    path = Path(value).absolute()
    if any(part.is_symlink() or getattr(part, "is_junction", lambda: False)() for part in (path, *path.parents)):
        raise ValueError("Linked output paths are not supported")
    path = path.resolve()
    if any((part / ".git").exists() for part in (path, *path.parents)):
        raise ValueError("Live usage observations must remain outside Git")
    if path.exists():
        raise FileExistsError("Refusing to overwrite usage observations")
    return path


def reconcile(observation, rows):
    if len(rows) != 1:
        return {"status": "shared_thread_not_attributable", "deltas": None}
    endpoint = rows[0]["observed_cumulative_endpoint"]
    counts = observation.get("estimated_thread_tokens")
    if endpoint is None or counts is None or any(counts[field] is None for field in COMPARABLE):
        return {"status": "unavailable_or_incomplete", "deltas": None}
    deltas = {field: counts[field] - endpoint[field] for field in COMPARABLE}
    return {"status": "observed_counters_match" if all(number == 0 for number in deltas.values()) else "observed_counters_differ",
            "deltas": deltas}


def run(executable, capture_paths, output, *, client_factory=Client):
    captures = [read_capture(path) for path in capture_paths]
    usage_audit = audit(captures)
    bindings = {}
    for trial in usage_audit["trials"]:
        for row in trial["threads"]:
            key = thread_id(row["provider_thread_id"])
            bindings.setdefault(key, []).append({**row, "trial_id": trial["trial_id"], "trial_issues": trial["issues"]})
    if not bindings:
        raise ValueError("No provider thread observed in the validated captures")
    executable = Path(executable).resolve(strict=True)
    if not executable.is_file():
        raise ValueError("Executable file required")
    output = private_destination(output)
    output.mkdir(parents=True, exist_ok=False)
    report = {"format": FORMAT, "model_calls": 0, "phone_dispatches": 0, "requests": [],
              "source_audit_sha256": usage_audit["audit_sha256"],
              "source_trial_issues": [{"trial_id": value["trial_id"], "issues": value["issues"]}
                                      for value in usage_audit["trials"]],
              "capture_sha256s": [value["capture_sha256"] for value in captures],
              "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
              "collector_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "started_at_ms": time.time_ns() // 1_000_000,
              "status": "running", "failure_type": None, "cleanup_completed": False,
              "trial_token_total": None, "billed_cost": None, "provider_request_count": None,
              "ready_for_equal_budget_comparison": False,
              "limitations": [
                  "Thread usage is a provider estimate, not a request ledger or actual invoice.",
                  "No pre-trial baseline or terminal usage completeness is certified by this read.",
                  "Matching counters corroborate an observation; they do not establish whole-trial attribution.",
                  "Model and effort groups are provider-reported usage categories, not per-response attestation.",
                  "Account-wide summaries are discarded and never substitute for missing thread usage.",
                  "Threads shared across trials are read once but not assigned to one trial."]}
    client = None
    try:
        client = client_factory(executable, output)
        client.initialize()
        for key, rows in sorted(bindings.items()):
            receipt = {"provider_thread_id": key, "trial_ids": sorted(row["trial_id"] for row in rows),
                       "requested_at_ms": time.time_ns() // 1_000_000}
            started = time.monotonic()
            try:
                response = client.request("account/usage/read", {"threadId": key})
                receipt["response_sha256"] = digest(response)
                receipt["observation"] = normalize(response, key)
                receipt["reconciliation"] = reconcile(receipt["observation"], rows)
            except (RpcError, TimeoutError, OSError, RuntimeError, ValueError) as error:
                receipt.update(status="query_failed", failure_type=type(error).__name__)
                if isinstance(error, RpcError):
                    receipt.update(rpc_code=error.code, rpc_error_sha256=error.digest)
            receipt["elapsed_ms"] = round((time.monotonic() - started) * 1000)
            receipt["received_at_ms"] = time.time_ns() // 1_000_000
            report["requests"].append(receipt)
        report["status"] = "observed" if all(row.get("observation", {}).get("status") == "available"
                                             for row in report["requests"]) else "incomplete"
    except (OSError, RuntimeError, ValueError, TimeoutError) as error:
        report.update(status="failed", failure_type=type(error).__name__)
    finally:
        try:
            if client is not None:
                client.close()
            report["cleanup_completed"] = True
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            report.update(status="failed", failure_type="cleanup_" + type(error).__name__)
        report["finished_at_ms"] = time.time_ns() // 1_000_000
        report["report_sha256"] = digest(report)
        with (output / "report.json").open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(json.dumps(report, indent=2, ensure_ascii=True, allow_nan=False) + "\n")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", type=Path, required=True)
    parser.add_argument("--capture", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = run(args.codex, args.capture, args.output)
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.exit(1, f"Usage audit failed ({type(error).__name__}); no model or task invoked.\n")
    print(json.dumps({"status": result["status"], "threads": len(result["requests"]),
                      "model_calls": 0, "ready_for_equal_budget_comparison": False}))
    return 0 if result["status"] == "observed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
