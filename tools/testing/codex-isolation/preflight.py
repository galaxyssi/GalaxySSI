"""Model-free, synthetic-only checks of Codex command sandbox read boundaries."""
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


FORMAT = "galaxyssi.codex-command-isolation-preflight.v2"
BOUNDARIES = ("workspace-only", "denied-subtree")
PROGRAM = """import json, pathlib, sys
operation, name, expected = sys.argv[1:]
try:
    path = pathlib.Path(name)
    if operation == 'read':
        matched = path.read_text(encoding='utf-8') == expected
    elif operation == 'write':
        with path.open('x', encoding='utf-8') as stream:
            stream.write(expected)
        matched = path.read_text(encoding='utf-8') == expected
    else:
        raise ValueError('unknown operation')
    result = {'outcome': 'allowed', 'content_matched': matched}
except PermissionError:
    result = {'outcome': 'denied'}
except Exception as error:
    result = {'outcome': 'inconclusive', 'error_type': type(error).__name__}
print(json.dumps(result, sort_keys=True))
"""


class RpcError(RuntimeError):
    def __init__(self, code, message=""):
        super().__init__("Codex command RPC failed")
        self.code = code if type(code) is int else None
        self.message_sha256 = hashlib.sha256(str(message).encode("utf-8")).hexdigest()
        self.diagnostic = rpc_diagnostic(message)


def rpc_diagnostic(message):
    if not isinstance(message, str):
        return "unclassified_rpc_error"
    if "elevated Windows sandbox requires effective `:root` read access" in message:
        return "windows_runtime_requires_root_read"
    if "readOnlyAccess is no longer supported" in message:
        return "legacy_restricted_read_parameter_removed"
    if message.startswith("invalid permission profile:"):
        return "permission_profile_invalid"
    return "unclassified_rpc_error"


class Client:
    """Own one short-lived app-server process; never start or resume a model turn."""

    def __init__(self, executable, cwd, config):
        overrides = [item for value in config for item in ("-c", value)]
        self.process = subprocess.Popen(
            [str(executable), *overrides, "app-server", "--listen", "stdio://"],
            cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace",
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        self.responses = queue.Queue(maxsize=64)
        self.next_id = 0
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        try:
            for line in self.process.stdout:
                if len(line) > 1024 * 1024:
                    continue
                try:
                    message = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if isinstance(message, dict) and "id" in message:
                    try:
                        self.responses.put_nowait(message)
                    except queue.Full:
                        return
        finally:
            try:
                self.responses.put_nowait(None)
            except queue.Full:
                pass

    def write(self, value):
        self.process.stdin.write(json.dumps(value, ensure_ascii=True) + "\n")
        self.process.stdin.flush()

    def request(self, method, params, timeout=45):
        if method not in {"initialize", "command/exec"}:
            raise ValueError("Model calls and thread operations are prohibited")
        self.next_id += 1
        request_id = self.next_id
        self.write({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while True:
            response = self.responses.get(timeout=max(0.001, deadline - time.monotonic()))
            if response is None:
                raise RuntimeError("Codex app-server exited")
            if response.get("id") != request_id:
                if "method" in response:
                    raise RuntimeError("Unexpected server request; no approval granted")
                if time.monotonic() >= deadline:
                    raise TimeoutError("Codex response deadline elapsed")
                continue
            if "error" in response:
                error = response.get("error") or {}
                raise RpcError(error.get("code"), error.get("message"))
            return response.get("result")

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        for stream in (self.process.stdin, self.process.stdout):
            if stream:
                stream.close()
        self.reader.join(timeout=1)


def private_destination(value):
    path = Path(value).absolute()
    if any(part.is_symlink() or getattr(part, "is_junction", lambda: False)() for part in (path, *path.parents)):
        raise ValueError("Symlink and junction output paths are not supported")
    path = path.resolve()
    if any((part / ".git").exists() for part in (path, *path.parents)):
        raise ValueError("Keep live preflight output outside Git repositories")
    if path.exists():
        raise FileExistsError("Refusing to overwrite a preflight directory")
    return path


def sandbox(workspace):
    return {
        "type": "workspaceWrite", "writableRoots": [str(workspace)],
        "networkAccess": False, "excludeTmpdirEnvVar": True, "excludeSlashTmp": True,
    }


def profile_config(name, python, sealed, boundary="workspace-only"):
    if boundary not in BOUNDARIES:
        raise ValueError("Unknown command boundary")
    # Current runtimes reject legacy readOnlyAccess; use a child-only named profile.
    rules = {":root": "deny" if boundary == "workspace-only" else "read",
             ":minimal": "read", ":tmpdir": "deny", ":slash_tmp": "deny",
             str(python.parent): "read", str(sealed): "deny"}
    filesystem = ", ".join(f"{json.dumps(path)}={json.dumps(access)}" for path, access in rules.items())
    # CLI override paths are not TOML quoted keys. Keep path keys inside a parsed table value.
    return ["permissions." + name + '={extends=":workspace", network={enabled=false}, filesystem={' + filesystem + "}}"]


def classify(result):
    if not isinstance(result, dict) or type(result.get("exitCode")) is not int:
        return {"outcome": "inconclusive", "reason": "invalid_command_result"}
    if result["exitCode"] != 0:
        return {"outcome": "inconclusive", "reason": "command_failed", "exit_code": result["exitCode"]}
    try:
        value = json.loads(result.get("stdout", ""))
    except (ValueError, TypeError):
        value = None
    if value == {"outcome": "allowed", "content_matched": True}:
        return value
    if value == {"outcome": "denied"}:
        return value
    return {"outcome": "inconclusive", "reason": "probe_did_not_confirm_read_or_permission_denial"}


def summarize(rows, boundary="workspace-only"):
    if boundary not in BOUNDARIES:
        raise ValueError("Unknown command boundary")
    observed = {(row["profile"], row["case"]): row["observation"]["outcome"] for row in rows}
    locations = ("inside", "outside", "unprotected") if boundary == "denied-subtree" else ("inside", "outside")
    expected = {(profile, case) for profile in ("legacy", "restricted")
                for case in (f"{location}_{operation}" for location in locations for operation in ("read", "write"))}
    complete = len(rows) == len(expected) and set(observed) == expected
    controls = complete and all(observed[(profile, case)] == "allowed"
                               for profile in ("legacy", "restricted")
                               for case in ("inside_read", "inside_write"))
    outside_denied = controls and all(observed[("restricted", case)] == "denied"
                                     for case in ("outside_read", "outside_write"))
    # A subtree-only policy deliberately preserves broad reads. Verify this control
    # rather than silently upgrading the narrower result to workspace-only isolation.
    scope_control = boundary == "workspace-only" or (complete and all(
        observed[(profile, "unprotected_read")] == "allowed" and
        observed[(profile, "unprotected_write")] == "denied"
        for profile in ("legacy", "restricted")))
    restricted = outside_denied and scope_control
    return {
        "tested_boundary": boundary,
        "all_cases_observed": complete,
        "positive_controls_passed": controls,
        "legacy_external_read_observed": observed.get(("legacy", "outside_read")) == "allowed",
        "restricted_command_boundary_passed": restricted,
        "workspace_only_command_boundary_passed": restricted and boundary == "workspace-only",
        "denied_subtree_command_boundary_passed": restricted and boundary == "denied-subtree",
        "unprotected_sibling_read_observed": observed.get(("restricted", "unprotected_read")) == "allowed",
        "production_turn_isolation_verified": False,
        "ready_for_blind_efficacy_study": False,
    }


def run(executable, directory, python, *, boundary="workspace-only", client_factory=Client):
    if boundary not in BOUNDARIES:
        raise ValueError("Unknown command boundary")
    executable, python = Path(executable).resolve(strict=True), Path(python).resolve(strict=True)
    if not executable.is_file() or not python.is_file():
        raise ValueError("Executable files required")
    directory = private_destination(directory)
    directory.mkdir(parents=True, exist_ok=False)
    workspace, sealed = directory / "workspace", directory / "sealed"
    workspace.mkdir()
    sealed.mkdir()
    marker = uuid.uuid4().hex
    profile_id = "galaxyssi-eval-probe-" + marker
    config = profile_config(profile_id, python, sealed, boundary)
    locations = [("inside", workspace), ("outside", sealed)]
    if boundary == "denied-subtree":
        unprotected = directory / "unprotected"
        unprotected.mkdir()
        locations.append(("unprotected", unprotected))
    for _, parent in locations:
        (parent / "canary.txt").write_text(marker, encoding="utf-8")
    report = {"format": FORMAT, "evidence_kind": "local_synthetic_command_probe", "boundary": boundary,
              "model_calls": 0, "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
              "python_sha256": hashlib.sha256(python.read_bytes()).hexdigest(),
              "probe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "child_config_overrides": config,
              "cases": [], "status": "running", "failure_type": None}
    client = None
    try:
        client = client_factory(executable, workspace, config)
        client.request("initialize", {
            "clientInfo": {"name": "galaxyssi-isolation-preflight", "version": "1"},
            "capabilities": {"experimentalApi": True},
        })
        client.write({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        for restricted in (False, True):
            profile = "restricted" if restricted else "legacy"
            policy = {"permissionProfile": profile_id} if restricted else {"sandboxPolicy": sandbox(workspace)}
            for location, root in locations:
                for operation in ("read", "write"):
                    target = root / ("canary.txt" if operation == "read" else f"{profile}-write.txt")
                    row = {"profile": profile, "case": f"{location}_{operation}", "command_policy": policy}
                    started = time.monotonic()
                    try:
                        result = client.request("command/exec", {
                            "command": [str(python), "-I", "-B", "-c", PROGRAM, operation, str(target), marker],
                            "cwd": str(workspace), **policy, "timeoutMs": 15000,
                        })
                        row["observation"] = classify(result)
                    except Exception as error:
                        row["observation"] = {"outcome": "inconclusive", "error_type": type(error).__name__}
                        if isinstance(error, RpcError):
                            row["observation"]["rpc_code"] = error.code
                            row["observation"]["rpc_message_sha256"] = error.message_sha256
                            row["observation"]["diagnostic"] = error.diagnostic
                    row["elapsed_ms"] = round((time.monotonic() - started) * 1000)
                    report["cases"].append(row)
        report["status"] = "completed"
    except Exception as error:
        report["status"], report["failure_type"] = "failed", type(error).__name__
    finally:
        if client:
            try:
                client.close()
            except Exception as error:
                report["status"], report["failure_type"] = "failed", "cleanup_" + type(error).__name__
        report["summary"] = summarize(report["cases"], boundary)
        if report["status"] != "completed":
            for key in ("restricted_command_boundary_passed", "workspace_only_command_boundary_passed",
                        "denied_subtree_command_boundary_passed"):
                report["summary"][key] = False
        report["limits"] = [
            "Synthetic canaries only; no private evaluator content was read.",
            "No model turns, phone operations, global configuration edits or production restart.",
            "Command probes do not cover image reads, MCP, plugins, network, child agents or model input assembly.",
            "Restricted policy is not yet applied to production or evaluation model turns.",
            "A command launch failure is inconclusive, never proof that protected data was denied.",
            "Denied-subtree mode allows other root reads and does not prove workspace-only isolation.",
            "Select each boundary explicitly in a fresh directory; a failed profile is never retried with broader access.",
        ]
        with (directory / "report.json").open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=True, allow_nan=False)
            stream.write("\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--python", type=Path, default=Path(sys.executable))
    parser.add_argument("--boundary", choices=BOUNDARIES, default="workspace-only")
    args = parser.parse_args()
    report = run(args.executable, args.directory, args.python, boundary=args.boundary)
    print(json.dumps({"status": report["status"], **report["summary"]}, sort_keys=True))
    return 0 if report["summary"]["restricted_command_boundary_passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
