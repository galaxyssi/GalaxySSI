import json
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import tomllib
import unittest

import preflight


def command_result(outcome="allowed"):
    value = {"outcome": outcome}
    if outcome == "allowed":
        value["content_matched"] = True
    return {"exitCode": 0, "stdout": json.dumps(value)}


class FakeClient:
    instances = []
    error_case = None

    def __init__(self, executable, cwd, config):
        self.cwd = Path(cwd)
        self.config = config
        self.calls = []
        self.closed = False
        self.instances.append(self)

    def write(self, value):
        self.calls.append(value)

    def request(self, method, params):
        self.calls.append({"method": method, "params": params})
        if method == "initialize":
            return {}
        if self.error_case:
            raise self.error_case
        target = Path(params["command"][-2])
        outside = target.parent != self.cwd
        restricted = "permissionProfile" in params
        operation = params["command"][-3]
        sealed = target.parent.name == "sealed"
        denied = outside and ((restricted and sealed) or operation == "write")
        return command_result("denied" if denied else "allowed")

    def close(self):
        self.closed = True


class PreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        FakeClient.instances.clear()
        FakeClient.error_case = None

    def run_fake(self, boundary="workspace-only"):
        return preflight.run(sys.executable, self.root / "probe", sys.executable,
                             boundary=boundary, client_factory=FakeClient)

    def test_exact_success_and_denial(self):
        self.assertEqual("allowed", preflight.classify(command_result())["outcome"])
        self.assertEqual("denied", preflight.classify(command_result("denied"))["outcome"])

    def test_launch_failure_is_not_denial(self):
        for value in (None, {}, {"exitCode": True}, {"exitCode": 1, "stdout": '{"outcome":"denied"}'},
                      {"exitCode": 0, "stdout": "permission denied"}):
            self.assertEqual("inconclusive", preflight.classify(value)["outcome"])

    def test_marker_mismatch_extra_fields_and_unknown_are_inconclusive(self):
        for value in ({"outcome": "allowed", "content_matched": False},
                      {"outcome": "denied", "other": True},
                      {"outcome": "inconclusive", "error_type": "FileNotFoundError"}):
            self.assertEqual("inconclusive", preflight.classify({"exitCode": 0, "stdout": json.dumps(value)})["outcome"])

    def test_restricted_policy_preserves_runtime_and_closes_network_and_temp(self):
        policy = preflight.sandbox(self.root / "workspace")
        self.assertFalse(policy["networkAccess"])
        self.assertTrue(policy["excludeTmpdirEnvVar"])
        self.assertTrue(policy["excludeSlashTmp"])
        config = preflight.profile_config("test", Path(sys.executable), self.root / "sealed")
        parsed = tomllib.loads(config[0])["permissions"]["test"]
        self.assertEqual("deny", parsed["filesystem"][":root"])
        self.assertEqual("read", parsed["filesystem"][":minimal"])
        self.assertFalse(parsed["network"]["enabled"])
        self.assertEqual(":workspace", parsed["extends"])
        self.assertEqual("read", parsed["filesystem"][str(Path(sys.executable).parent)])

    def test_all_cases_and_no_model_methods(self):
        report = self.run_fake()
        client = FakeClient.instances[0]
        self.assertTrue(client.closed)
        self.assertEqual(8, len(report["cases"]))
        self.assertEqual(0, report["model_calls"])
        self.assertTrue(report["summary"]["restricted_command_boundary_passed"])
        self.assertFalse(report["summary"]["ready_for_blind_efficacy_study"])
        self.assertFalse(report["summary"]["production_turn_isolation_verified"])
        self.assertEqual({"initialize", "initialized", "command/exec"}, {row["method"] for row in client.calls})
        self.assertEqual(report, json.loads((self.root / "probe/report.json").read_text()))

    def test_subtree_mode_is_explicit_and_does_not_claim_workspace_isolation(self):
        report = self.run_fake("denied-subtree")
        self.assertEqual(12, len(report["cases"]))
        summary = report["summary"]
        self.assertEqual("denied-subtree", report["boundary"])
        self.assertTrue(summary["restricted_command_boundary_passed"])
        self.assertTrue(summary["denied_subtree_command_boundary_passed"])
        self.assertTrue(summary["unprotected_sibling_read_observed"])
        self.assertFalse(summary["workspace_only_command_boundary_passed"])
        self.assertFalse(summary["production_turn_isolation_verified"])
        self.assertFalse(summary["ready_for_blind_efficacy_study"])
        config = FakeClient.instances[0].config[0]
        profile = next(iter(tomllib.loads(config)["permissions"].values()))
        self.assertEqual("read", profile["filesystem"][":root"])
        self.assertEqual("deny", profile["filesystem"][str(self.root / "probe/sealed")])
        self.assertFalse(profile["network"]["enabled"])

    def test_subtree_scope_control_failures_do_not_pass(self):
        report = self.run_fake("denied-subtree")
        for case in ("unprotected_read", "unprotected_write", "outside_read", "outside_write"):
            rows = json.loads(json.dumps(report["cases"]))
            row = next(row for row in rows if row["profile"] == "restricted" and row["case"] == case)
            row["observation"] = {"outcome": "inconclusive"}
            self.assertFalse(preflight.summarize(rows, "denied-subtree")["restricted_command_boundary_passed"])
        self.assertFalse(preflight.summarize(report["cases"], "workspace-only")["restricted_command_boundary_passed"])

    def test_subtree_rpc_failure_is_not_retried_or_counted_as_denial(self):
        FakeClient.error_case = preflight.RpcError(-32603, "unknown runtime error")
        report = self.run_fake("denied-subtree")
        self.assertEqual(1, len(FakeClient.instances))
        self.assertEqual(12, len(report["cases"]))
        self.assertFalse(report["summary"]["denied_subtree_command_boundary_passed"])

    def test_unknown_boundary_fails_before_output_creation(self):
        with self.assertRaises(ValueError):
            self.run_fake("auto")
        self.assertFalse((self.root / "probe").exists())
        self.assertEqual([], FakeClient.instances)
        with self.assertRaises(ValueError):
            preflight.summarize([], "auto")
        with self.assertRaises(ValueError):
            preflight.profile_config("probe", Path(sys.executable), self.root / "sealed", "auto")

    def test_subtree_cleanup_failure_revokes_all_pass_flags(self):
        class BadCleanup(FakeClient):
            def close(self):
                raise RuntimeError("cleanup failed")
        report = preflight.run(sys.executable, self.root / "failed", sys.executable,
                               boundary="denied-subtree", client_factory=BadCleanup)
        for key in ("restricted_command_boundary_passed", "workspace_only_command_boundary_passed",
                    "denied_subtree_command_boundary_passed"):
            self.assertFalse(report["summary"][key])

    def test_errors_are_retained_without_raw_paths_or_stderr(self):
        FakeClient.error_case = preflight.RpcError(-32602)
        report = self.run_fake()
        self.assertEqual(8, len(report["cases"]))
        self.assertTrue(all(row["observation"]["outcome"] == "inconclusive" for row in report["cases"]))
        self.assertFalse(report["summary"]["restricted_command_boundary_passed"])
        self.assertTrue(FakeClient.instances[0].closed)

    def test_safe_rpc_diagnostic_names_actual_incompatibility(self):
        message = "exec failed: windows sandbox: elevated Windows sandbox requires effective `:root` read access"
        error = preflight.RpcError(-32603, message)
        self.assertEqual("windows_runtime_requires_root_read", error.diagnostic)
        self.assertNotIn(message, str(error))
        self.assertEqual("permission_profile_invalid", preflight.rpc_diagnostic("invalid permission profile: private path"))
        self.assertEqual("legacy_restricted_read_parameter_removed", preflight.rpc_diagnostic("readOnlyAccess is no longer supported"))
        self.assertEqual("unclassified_rpc_error", preflight.rpc_diagnostic(None))

    def test_cleanup_failure_keeps_report_but_cannot_pass(self):
        class BadCleanup(FakeClient):
            def close(self):
                raise RuntimeError("private message")
        report = preflight.run(sys.executable, self.root / "failed", sys.executable, client_factory=BadCleanup)
        self.assertEqual("failed", report["status"])
        self.assertEqual("cleanup_RuntimeError", report["failure_type"])
        self.assertFalse(report["summary"]["restricted_command_boundary_passed"])
        self.assertTrue((self.root / "failed/report.json").exists())

    def test_timeouts_do_not_trigger_an_unsandboxed_retry(self):
        FakeClient.error_case = queue.Empty()
        report = self.run_fake()
        commands = [row for row in FakeClient.instances[0].calls if row["method"] == "command/exec"]
        self.assertEqual(8, len(commands))
        self.assertTrue(all(("sandboxPolicy" in row["params"]) != ("permissionProfile" in row["params"]) for row in commands))
        self.assertFalse(report["summary"]["positive_controls_passed"])

    def test_failed_initialization_still_records_report(self):
        class Failed(FakeClient):
            def request(self, method, params):
                raise RuntimeError("sensitive provider text")
        report = preflight.run(sys.executable, self.root / "failed", sys.executable, client_factory=Failed)
        self.assertEqual("failed", report["status"])
        self.assertEqual("RuntimeError", report["failure_type"])
        self.assertNotIn("sensitive", json.dumps(report))
        self.assertTrue(Failed.instances[0].closed)

    def test_existing_directory_is_not_overwritten(self):
        self.run_fake()
        before = (self.root / "probe/report.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.run_fake()
        self.assertEqual(before, (self.root / "probe/report.json").read_bytes())

    def test_git_output_is_rejected(self):
        (self.root / ".git").write_text("gitdir: elsewhere")
        with self.assertRaises(ValueError):
            preflight.private_destination(self.root / "nested/probe")

    def test_duplicate_missing_and_failed_controls_cannot_pass(self):
        rows = self.run_fake()["cases"]
        for changed in (rows[:-1], rows + [rows[0]], []):
            self.assertFalse(preflight.summarize(changed)["restricted_command_boundary_passed"])
        rows[0]["observation"] = {"outcome": "denied"}
        self.assertFalse(preflight.summarize(rows)["restricted_command_boundary_passed"])

    def test_rpc_guard_refuses_model_work_before_process_access(self):
        client = object.__new__(preflight.Client)
        for method in ("turn/start", "thread/start", "thread/resume", "config/value/write"):
            with self.assertRaises(ValueError):
                client.request(method, {})

    def test_probe_program_uses_only_synthetic_paths(self):
        path = self.root / "canary.txt"
        path.write_text("marker", encoding="utf-8")
        for operation, target in (("read", path), ("write", self.root / "new.txt")):
            result = subprocess.run([sys.executable, "-I", "-B", "-c", preflight.PROGRAM,
                                     operation, str(target), "marker"], capture_output=True, text=True, check=True)
            self.assertEqual({"outcome": "allowed", "content_matched": True}, json.loads(result.stdout))
        result = subprocess.run([sys.executable, "-I", "-B", "-c", preflight.PROGRAM,
                                 "read", str(self.root / "missing.txt"), "marker"], capture_output=True, text=True, check=True)
        self.assertEqual("inconclusive", json.loads(result.stdout)["outcome"])


if __name__ == "__main__":
    unittest.main()
