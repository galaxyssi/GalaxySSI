import io
import json
from pathlib import Path
import sys
import queue
import tempfile
import tomllib
import unittest
from unittest.mock import Mock

import thread_preflight as probe
import preflight


def config_for(values):
    result = {}
    for key, value in values.items():
        target = result
        parts = key.split(".")
        for part in parts[:-1]:
            target = target.setdefault(part, {})
        target[parts[-1]] = value
    return result


class FakeClient:
    instances = []
    issue = None

    def __init__(self, executable, cwd, overrides):
        self.cwd, self.overrides = Path(cwd), overrides
        self.calls, self.closed = [], False
        self.instances.append(self)

    def write(self, value):
        self.calls.append(value)

    def close(self):
        self.closed = True
        if self.issue == "close":
            raise OSError("PRIVATE-CLEANUP")

    def request(self, method, params):
        self.calls.append({"method": method, "params": params})
        if method == "initialize":
            return {}
        if method == "config/read":
            value = config_for(probe.CONFIG)
            disabled = any(item.startswith("mcp_servers=") for item in self.overrides)
            value["mcp_servers"] = {"fixture.with.dot": {"enabled": not disabled, "command": "PRIVATE-COMMAND"}}
            if self.issue == "flags":
                value["features"]["apps"] = True
            return {"config": value, "layers": ["PRIVATE-LAYER"]}
        if method == "thread/start":
            result = {"thread": {"id": "ephemeral-fixture"}, "activePermissionProfile": {"id": params["permissions"]},
                      "approvalPolicy": "never", "model": params["model"], "reasoningEffort": "high",
                      "cwd": str(self.cwd), "runtimeWorkspaceRoots": [], "instructionSources": []}
            if self.issue == "profile":
                result["activePermissionProfile"]["id"] = ":workspace"
            if self.issue == "instructions":
                result["instructionSources"] = ["PRIVATE-SOURCE"]
            return result
        if method == "skills/list":
            disabled = any(item.startswith("skills.config=") for item in self.overrides)
            skills = [{"enabled": not disabled or self.issue == "skills", "name": "PRIVATE-SKILL",
                       "path": str(self.cwd / "PRIVATE-SKILL" / "SKILL.md")}]
            return {"data": [{"cwd": str(self.cwd), "errors": [], "skills": skills}]}
        if method == "mcpServerStatus/list":
            return {"data": [{"name": "PRIVATE-MCP", "runtimeStatus": "connected" if self.issue == "mcp" else "disabled",
                               "tools": {}, "resources": [], "resourceTemplates": []}], "nextCursor": None}
        if method == "command/exec":
            if self.issue == "command":
                raise preflight.RpcError(-1, "PRIVATE-RPC")
            parent = Path(params["command"][-2]).parent.name
            denied = parent == "sealed" or (parent == "unprotected" and params["command"][-3] == "write")
            result = {"outcome": "denied"} if denied else {"outcome": "allowed", "content_matched": True}
            return {"exitCode": 0, "stdout": json.dumps(result)}
        if method == "thread/unsubscribe":
            if self.issue == "unsubscribe":
                raise RuntimeError("PRIVATE-UNSUBSCRIBE")
            return {}
        raise AssertionError("Unexpected method")


class ThreadPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        FakeClient.instances.clear()
        FakeClient.issue = None

    def run_fake(self):
        return probe.run(sys.executable, self.root / "probe", sys.executable, "fixture-model", "high", client_factory=FakeClient)

    def test_ephemeral_thread_reports_requested_policy_and_no_enabled_capabilities(self):
        result = self.run_fake()
        self.assertEqual("preflight_passed_not_model_verified", result["status"])
        self.assertEqual(0, result["model_calls"])
        self.assertFalse(result["production_turn_isolation_verified"])
        self.assertFalse(result["ready_for_blind_efficacy_study"])
        self.assertTrue(result["cleanup_completed"])
        self.assertTrue(result["unsubscribed"])
        self.assertTrue(result["command_checks_passed"])
        self.assertEqual(2, len(FakeClient.instances))
        self.assertTrue(all(client.closed for client in FakeClient.instances))
        calls = [call for client in FakeClient.instances for call in client.calls]
        methods = {call["method"] for call in calls}
        self.assertNotIn("turn/start", methods)
        self.assertNotIn("thread/resume", methods)
        start = next(call["params"] for call in calls if call["method"] == "thread/start")
        self.assertTrue(start["ephemeral"])
        self.assertFalse(start["allowProviderModelFallback"])
        self.assertNotIn("sandbox", start)
        self.assertEqual([], start["dynamicTools"])
        self.assertEqual([], start["environments"])
        self.assertEqual([], start["runtimeWorkspaceRoots"])
        self.assertEqual(1, result["discovered_skill_path_count"])
        self.assertEqual(0, result["skills"]["enabled_skill_count"])
        self.assertEqual(1, result["mcp"]["disabled_server_count"])
        self.assertNotIn("PRIVATE", json.dumps(result))

    def test_disabled_mcp_names_are_toml_literal_keys(self):
        override, count = probe.disabled_servers({"config": {"mcp_servers": {"fixture.with.dot": {"token": "PRIVATE"}}}})
        self.assertEqual(1, count)
        self.assertEqual({"fixture.with.dot": {"enabled": False}}, tomllib.loads(override)["mcp_servers"])
        self.assertNotIn("PRIVATE", override)

    def test_invalid_config_or_server_names_do_not_become_empty_success(self):
        for value in (None, {}, {"config": {}}, {"config": {"mcp_servers": []}}, {"config": {"mcp_servers": {"\n": {}}}}):
            if value == {"config": {}}:
                self.assertEqual(("mcp_servers={}", 0), probe.disabled_servers(value))
            else:
                with self.assertRaises(ValueError):
                    probe.disabled_servers(value)

    def test_effective_flags_not_just_requested_flags_are_checked(self):
        FakeClient.issue = "flags"
        result = self.run_fake()
        self.assertEqual("failed", result["status"])
        self.assertEqual("effective_capability_flags_not_verified", result["failure_code"])
        self.assertFalse(any(call["method"] == "thread/start" for client in FakeClient.instances for call in client.calls))

    def test_profile_or_instruction_mismatch_stops_before_canary_tools(self):
        for issue in ("profile", "instructions"):
            FakeClient.issue = issue
            with tempfile.TemporaryDirectory() as directory:
                result = probe.run(sys.executable, Path(directory) / "probe", sys.executable, "fixture-model", "high", client_factory=FakeClient)
            self.assertEqual("thread_policy_not_verified", result["failure_code"])
            self.assertEqual([], result["cases"])
            self.assertTrue(result["unsubscribed"])
            self.assertNotIn("PRIVATE", json.dumps(result))

    def test_enabled_skills_or_mcp_inventory_is_incomplete(self):
        for issue in ("skills", "mcp"):
            FakeClient.issue = issue
            with tempfile.TemporaryDirectory() as directory:
                result = probe.run(sys.executable, Path(directory) / "probe", sys.executable, "fixture-model", "high", client_factory=FakeClient)
            self.assertEqual("incomplete", result["status"])
            self.assertFalse(result["no_enabled_capabilities_reported"])
            self.assertNotIn("PRIVATE", json.dumps(result))

    def test_command_errors_are_not_counted_as_denied(self):
        FakeClient.issue = "command"
        result = self.run_fake()
        self.assertEqual("incomplete", result["status"])
        self.assertTrue(all(row["observation"]["outcome"] == "inconclusive" for row in result["cases"]))
        self.assertFalse(result["command_checks_passed"])

    def test_cleanup_failure_never_reports_pass(self):
        FakeClient.issue = "unsubscribe"
        result = self.run_fake()
        self.assertEqual("cleanup_incomplete", result["status"])
        self.assertFalse(result["unsubscribed"])
        self.assertTrue(result["cleanup_completed"])

    def test_unknown_inventory_schema_or_pagination_is_not_empty(self):
        for value in (None, {}, {"data": []}, {"data": [{"skills": [{"enabled": "false"}]}]}):
            result = probe.skill_summary(value, self.root)
            self.assertIsNone(result["enabled_skill_count"])
        self.assertEqual("incomplete", probe.mcp_summary({"data": [], "nextCursor": "more"})["status"])
        self.assertEqual("incomplete", probe.mcp_summary({})["status"])

    def test_skill_inventory_requires_correct_workspace_and_no_scan_errors(self):
        row = {"cwd": str(self.root), "skills": [], "errors": []}
        self.assertEqual(0, probe.skill_summary({"data": [row]}, self.root)["enabled_skill_count"])
        for patch in ({"cwd": "elsewhere"}, {"errors": ["PRIVATE"]}, {"errors": None}, {"skills": None}):
            self.assertEqual("unavailable", probe.skill_summary({"data": [{**row, **patch}]}, self.root)["status"])

    def test_skill_disable_override_uses_exact_reported_paths_and_deduplicates(self):
        path = str(self.root / 'skill.with.dot' / 'SKILL.md')
        skills = [{"path": path, "enabled": True}, {"path": path, "enabled": False}]
        override, count = probe.disabled_skills({"data": [{"cwd": str(self.root), "errors": [], "skills": skills}]}, self.root)
        self.assertEqual(1, count)
        self.assertEqual([{"path": path, "enabled": False}], tomllib.loads(override)["skills"]["config"])

    def test_invalid_skill_paths_cannot_become_disabled_inventory_success(self):
        for path in (None, "", "relative/SKILL.md", str(self.root) + "\n"):
            value = {"data": [{"cwd": str(self.root), "errors": [], "skills": [{"path": path, "enabled": True}]}]}
            with self.assertRaisesRegex(ValueError, "skill_path_invalid"):
                probe.disabled_skills(value, self.root)

    def test_mcp_requires_disabled_status_and_empty_capability_catalog(self):
        row = {"runtimeStatus": "disabled", "tools": {}, "resources": [], "resourceTemplates": []}
        self.assertTrue(probe.mcp_summary({"data": [row]})["no_enabled_capabilities_reported"])
        for patch in ({"runtimeStatus": None}, {"runtimeStatus": "connected"}, {"runtimeStatus": "failed"},
                      {"runtimeStatus": "future-state"}, {"tools": {"PRIVATE": {}}}, {"toolsError": "PRIVATE"},
                      {"resources": ["PRIVATE"]}, {"resourceTemplates": ["PRIVATE"]}):
            result = probe.mcp_summary({"data": [{**row, **patch}]})
            self.assertFalse(result["no_enabled_capabilities_reported"])
            self.assertNotIn("PRIVATE", json.dumps(result))

    def test_ephemeral_start_and_method_allowlist_prevent_model_calls(self):
        client = object.__new__(probe.ThreadClient)
        client.write = Mock()
        for method in ("turn/start", "turn/steer", "thread/resume", "thread/fork", "config/value/write", "account/usage/read"):
            with self.assertRaises(ValueError):
                client.request(method, {})
        for value in ({}, {"ephemeral": False}, {"ephemeral": True, "input": "secret"}):
            with self.assertRaises(ValueError):
                client.request("thread/start", value)
        client.write.assert_not_called()

    def test_report_hash_and_no_overwrite(self):
        result = self.run_fake()
        self.assertEqual(result["report_sha256"], probe.digest({key: value for key, value in result.items() if key != "report_sha256"}))
        with self.assertRaises(FileExistsError):
            self.run_fake()

    def test_invalid_effort_rejected_before_output_creation(self):
        with self.assertRaises(ValueError):
            probe.run(sys.executable, self.root / "bad", sys.executable, "fixture-model", "invalid", client_factory=FakeClient)
        self.assertFalse((self.root / "bad").exists())

    def test_oversized_response_stops_reader_instead_of_silent_timeout(self):
        client = object.__new__(preflight.Client)
        client.responses = queue.Queue()
        client.process = Mock(stdout=io.StringIO("PRIVATE" * 160000 + "\n"))
        client.reader_failure = None
        client._read()
        self.assertEqual("response_too_large", client.reader_failure)
        self.assertIsNone(client.responses.get_nowait())

    def test_thread_config_response_over_one_megabyte_is_accepted_with_bounded_limit(self):
        client = object.__new__(probe.ThreadClient)
        client.responses = queue.Queue()
        payload = {"id": 2, "result": {"config": "x" * (1024 * 1024)}}
        client.process = Mock(stdout=io.StringIO(json.dumps(payload) + "\n"))
        client.reader_failure = None
        client._read()
        self.assertEqual(payload, client.responses.get_nowait())
        self.assertIsNone(client.reader_failure)


if __name__ == "__main__":
    unittest.main()
