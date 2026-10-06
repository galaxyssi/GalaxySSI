import json
import os
from pathlib import Path
import tempfile
import tomllib
import unittest
from dataclasses import replace
from unittest.mock import Mock, patch

import codex_app_server as codex
from codex_experiment_boundary import CodexExperimentBoundary, ExperimentBoundaryError, FLAGS
from agent_execution_harness import AgentReasoningEffort, execution_policy_for


def nested(values):
    result = {}
    for key, value in values.items():
        target = result
        parts = key.split(".")
        for part in parts[:-1]:
            target = target.setdefault(part, {})
        target[parts[-1]] = value
    return result


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        environment = patch.dict(os.environ, {"GALAXYSSI_STATE_DIR": str(self.root / "state"),
            "GALAXYSSI_WORKSPACE_ROOT": str(self.root / "harness")})
        environment.start()
        self.addCleanup(environment.stop)
        thread_path = patch.object(codex, "CONVERSATION_THREADS_PATH", self.root / "ordinary-threads.json")
        thread_path.start()
        self.addCleanup(thread_path.stop)
        self.workspace, self.sealed = self.root / "workspace", self.root / "sealed"
        self.workspace.mkdir()
        self.sealed.mkdir()
        self.kw = dict(scope_id="fixture", workspace=self.workspace, protected_root=self.sealed,
            state_path=self.sealed / "state.json", model="fixture-model", effort="high", conversation_ids=["fixture-conversation"])
        self.boundary = CodexExperimentBoundary(**self.kw)
        self.server = codex.CodexAppServer("codex", {}, lambda *_: None, experiment_boundary=self.boundary)
        self.calls, self.issue = [], None
        self.server._rpc_request = self.rpc
        self.boundary.verify_runtime(self.rpc)

    def rpc(self, method, params, timeout):
        self.calls.append((method, params))
        if method == "config/read":
            config = nested(FLAGS)
            config["mcp_servers"] = {"fixture": {"enabled": False}}
            if self.issue == "flags":
                config["features"]["apps"] = True
            if self.issue == "instructions":
                config["model_instructions_file"] = "PRIVATE"
            return {"config": config}
        if method == "skills/list":
            return {"data": [{"cwd": params["cwds"][0], "errors": [],
                "skills": [{"enabled": self.issue == "skills", "name": "PRIVATE"}]}]}
        if method in {"thread/start", "thread/resume"}:
            result = {"thread": {"id": params.get("threadId", "thread-owned")},
                "activePermissionProfile": {"id": self.boundary.profile}, "approvalPolicy": "never",
                "model": "fixture-model", "reasoningEffort": "high", "cwd": str(self.workspace),
                "runtimeWorkspaceRoots": [], "instructionSources": []}
            if self.issue == "thread":
                result["activePermissionProfile"]["id"] = ":workspace"
            return result
        if method == "mcpServerStatus/list":
            return {"data": [{"runtimeStatus": "connected" if self.issue == "mcp" else "disabled",
                "tools": {}, "resources": [], "resourceTemplates": []}]}
        if method == "turn/start":
            return {"turn": {"id": "turn-owned"}}
        return {}

    def start(self):
        return self.server._start_thread(str(self.workspace), "fixture-model", "fixture-conversation")

    def turn(self, **changes):
        params = {"threadId": "thread-owned", "model": "fixture-model", "effort": "high",
                  "cwd": str(self.workspace), "input": [{"type": "text", "text": "fixture", "text_elements": []}]}
        return self.server._request("turn/start", {**params, **changes}, 1)

    def test_real_adapter_rewrites_start_before_rpc_and_verifies_before_turn(self):
        self.assertEqual("thread-owned", self.start())
        params = next(p for m, p in self.calls if m == "thread/start")
        self.assertNotIn("sandbox", params)
        self.assertEqual(self.boundary.profile, params["permissions"])
        self.assertEqual([], params["dynamicTools"])
        self.assertEqual([], params["environments"])
        self.assertFalse(params["allowProviderModelFallback"])
        self.assertEqual([], self.server._dynamic_tools)
        self.assertEqual({"turn": {"id": "turn-owned"}}, self.turn())
        self.assertEqual("turn/start", self.calls[-1][0])
        self.assertTrue(self.boundary.state_path.is_file())

    def test_no_boundary_preserves_ordinary_request_and_tools(self):
        server = codex.CodexAppServer("codex", {}, lambda *_: None)
        server._rpc_request = Mock(return_value={"thread": {"id": "ordinary"}})
        self.assertTrue(server._dynamic_tools)
        params = {"cwd": "ordinary", "sandbox": "workspace-write", "dynamicTools": ["fixture"]}
        server._request("thread/start", params, 1)
        server._rpc_request.assert_called_once_with("thread/start", params, 1)

    def test_read_and_resume_reject_unowned_threads_before_rpc(self):
        before = len(self.calls)
        for method in ("thread/read", "thread/resume", "turn/interrupt", "thread/unsubscribe"):
            with self.assertRaisesRegex(ExperimentBoundaryError, "thread_not_owned"):
                self.server._request(method, {"threadId": "ordinary-thread"}, 1)
        self.assertEqual(before, len(self.calls))

    def test_closed_rpc_set_rejects_alternate_tools_and_thread_forks(self):
        for method in ("thread/fork", "command/exec", "fs/readFile", "mcpServer/tool/call", "config/value/write"):
            with self.assertRaisesRegex(ExperimentBoundaryError, "rpc_not_allowed"):
                self.server._request(method, {}, 1)

    def test_resume_cannot_inject_history_paths_or_alternate_instructions(self):
        self.start()
        for field in ("path", "history", "baseInstructions", "permissions", "dynamicTools"):
            with self.assertRaisesRegex(ExperimentBoundaryError, "rpc_fields_not_allowed"):
                self.server._request("thread/resume", {"threadId": "thread-owned", field: "PRIVATE"}, 1)

    def test_read_only_request_is_not_widened_to_writable_experiment_profile(self):
        with self.assertRaisesRegex(ExperimentBoundaryError, "read_only_profile_not_verified"):
            self.server._start_thread(str(self.workspace), "fixture-model", "fixture-conversation", sandbox="read-only")
        self.assertFalse(any(method == "thread/start" for method, _ in self.calls))

    def test_admission_rejects_scope_model_effort_and_images_before_start(self):
        policy = replace(execution_policy_for("fixture"), reasoning_effort=AgentReasoningEffort.HIGH)
        base = {"conversation_id": "fixture-conversation", "model": "fixture-model", "execution_policy": policy}
        with patch.object(self.server, "_ensure_started") as start:
            for changes in ({"conversation_id": "other"}, {"model": "other"}, {"image_paths": [str(self.sealed / "private.png")]},
                    {"execution_policy": replace(policy, reasoning_effort=AgentReasoningEffort.LOW)}):
                with self.assertRaises(ExperimentBoundaryError):
                    self.server.start_task("task", "fixture", str(self.workspace), **{**base, **changes})
            start.assert_not_called()

    def test_turn_input_variants_and_model_changes_are_rejected(self):
        self.start()
        for changes in ({"input": [{"type": "localImage", "path": "PRIVATE"}]}, {"input": []},
                        {"input": [{"type": "text", "text": "fixture", "file": "PRIVATE"}]},
                        {"cwd": str(self.sealed)}, {"model": "other"}, {"effort": "low"}):
            with self.assertRaises(ExperimentBoundaryError):
                self.turn(**changes)
        self.assertFalse(any(m == "turn/start" for m, _ in self.calls))

    def test_process_restart_requires_revalidation_and_owned_resume(self):
        self.start()
        boundary = CodexExperimentBoundary(**self.kw)
        server = codex.CodexAppServer("codex", {}, lambda *_: None, experiment_boundary=boundary)
        server._rpc_request = self.rpc
        self.assertEqual(self.server._conversation_threads, server._conversation_threads)
        with self.assertRaisesRegex(ExperimentBoundaryError, "runtime_not_verified"):
            server._request("thread/resume", {"threadId": "thread-owned"}, 1)
        boundary.verify_runtime(self.rpc)
        with self.assertRaisesRegex(ExperimentBoundaryError, "thread_not_verified"):
            server._request("turn/steer", {"threadId": "thread-owned", "input": [{"type": "text", "text": "fixture"}]}, 1)
        server._resume_thread("thread-owned")
        params = next(p for m, p in reversed(self.calls) if m == "thread/resume")
        self.assertNotIn("sandbox", params)
        self.assertNotIn("dynamicTools", params)
        self.assertNotIn("environments", params)
        self.assertEqual(boundary.profile, params["permissions"])
        self.assertIn("thread-owned", boundary._verified_threads)

    def test_runtime_inventory_drift_blocks_model_dispatch(self):
        for issue in ("flags", "instructions", "skills", "mcp"):
            self.issue = None
            self.boundary.verify_runtime(self.rpc)
            self.start()
            self.issue = issue
            with patch.object(self.server, "_close_process", wraps=self.server._close_process) as close:
                with self.assertRaises(ExperimentBoundaryError):
                    self.turn()
                close.assert_called_once()
        self.assertFalse(any(m == "turn/start" for m, _ in self.calls))

    def test_wrong_thread_policy_closes_process_without_persisting_ownership(self):
        self.issue = "thread"
        with self.assertRaisesRegex(ExperimentBoundaryError, "thread_policy"):
            self.start()
        self.assertFalse(self.boundary.state_path.exists())
        self.assertFalse(self.boundary.runtime_verified)

    def test_dynamic_tool_and_unknown_server_requests_never_execute(self):
        with patch.object(self.server, "_write") as write, patch.object(self.server, "_handle_dynamic_tool_call") as tool:
            self.server._handle_event({"id": 1, "method": "item/tool/call", "params": {"tool": "galaxyssi_office_preview"}})
            self.assertFalse(write.call_args[0][0]["result"]["success"])
            self.server._handle_event({"id": 2, "method": "future/unknown", "params": {}})
            self.assertEqual(-32601, write.call_args[0][0]["error"]["code"])
            tool.assert_not_called()

    def test_permission_request_is_denied_even_in_execution_mode(self):
        with patch.object(self.server, "_write") as write:
            self.server._handle_event({"id": 1, "method": "item/permissions/requestApproval",
                "params": {"permissions": {"network": {"enabled": True}}}})
            self.assertEqual({}, write.call_args[0][0]["result"]["permissions"])

    def test_start_timeout_is_not_automatically_retried(self):
        with patch.object(self.server, "_start_thread", side_effect=codex.CodexAppServerRequestTimeout("thread/start", 1)) as start:
            with self.assertRaises(codex.CodexAppServerRequestTimeout):
                self.server._start_thread_with_retry(str(self.workspace), "fixture-model", "fixture-conversation")
            self.assertEqual(1, start.call_count)

    def test_missing_checkpoint_cannot_silently_create_a_replacement_thread(self):
        policy = replace(execution_policy_for("fixture"), reasoning_effort=AgentReasoningEffort.HIGH)
        with self.assertRaisesRegex(ExperimentBoundaryError, "checkpoint_not_reusable"):
            self.server.recover_task("task", "", "", "fixture", conversation_id="fixture-conversation",
                cwd=str(self.workspace), model="fixture-model", execution_policy=policy)

    def test_provider_missing_owned_thread_does_not_fall_back_to_fresh_start(self):
        self.start()
        self.server._loaded_thread_ids.clear()
        policy = replace(execution_policy_for("fixture"), reasoning_effort=AgentReasoningEffort.HIGH)
        with patch.object(self.server, "_ensure_started"), \
                patch.object(self.server, "_resume_thread", side_effect=RuntimeError("thread not found")), \
                patch.object(self.server, "_start_thread_with_retry") as fresh, \
                patch.object(self.server, "_begin_host_config_guard", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "thread not found"):
                self.server.start_task("task", "fixture", str(self.workspace), conversation_id="fixture-conversation",
                    model="fixture-model", execution_policy=policy)
            fresh.assert_not_called()
        self.assertIn("thread-owned", self.boundary.conversations().values())

    def test_wrong_runtime_resume_does_not_import_global_conversations(self):
        self.start()
        with patch.object(codex, "CONVERSATION_THREADS_PATH", self.root / "ordinary.json"):
            codex.CONVERSATION_THREADS_PATH.write_text(json.dumps({"unrelated": "ordinary-thread"}), encoding="utf-8")
            server = codex.CodexAppServer("codex", {}, lambda *_: None,
                experiment_boundary=CodexExperimentBoundary(**self.kw))
            self.assertNotIn("ordinary-thread", server._conversation_threads.values())
            self.assertEqual({"unrelated": "ordinary-thread"}, json.loads(codex.CONVERSATION_THREADS_PATH.read_text()))

    def test_overlapping_paths_unprotected_ledger_and_scope_changes_fail(self):
        for changes in ({"workspace": self.sealed}, {"state_path": self.workspace / "state.json"}, {"conversation_ids": []}):
            with self.assertRaises(ExperimentBoundaryError):
                CodexExperimentBoundary(**{**self.kw, **changes})
        self.start()
        with self.assertRaisesRegex(ExperimentBoundaryError, "state_mismatch"):
            CodexExperimentBoundary(**{**self.kw, "model": "other"})

    def test_corrupted_ledger_is_not_replaced_by_empty_state(self):
        self.boundary.state_path.write_text("not json", encoding="utf-8")
        with self.assertRaisesRegex(ExperimentBoundaryError, "state_invalid"):
            CodexExperimentBoundary(**self.kw)
        self.assertEqual("not json", self.boundary.state_path.read_text(encoding="utf-8"))

    def test_profile_overrides_are_valid_toml_with_literal_paths(self):
        config = {}
        for value in self.boundary.process_overrides():
            config.update(tomllib.loads(value))
        profile = config["permissions"][self.boundary.profile]
        self.assertEqual("deny", profile["filesystem"][str(self.sealed)])
        self.assertEqual("write", profile["filesystem"][str(self.workspace)])
        self.assertFalse(profile["network"]["enabled"])
        self.assertEqual("read", profile["filesystem"][":root"])


if __name__ == "__main__":
    unittest.main()
