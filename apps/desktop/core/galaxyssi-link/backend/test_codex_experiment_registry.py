import copy
import json
import os
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest.mock import Mock, patch

import codex_experiment_registry as experiments
from codex_experiment_boundary import CodexExperimentBoundary, ExperimentBoundaryError


class RegistryFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.private = self.root / "private"
        self.private.mkdir()
        self.path = self.private / "registry.json"
        self.row = dict(scope_id="fixture-arm-a", client_route_id="client-1",
            client_conversation_id="conversation-1", task_ids=["task-follow-up", "task-recovered"],
            workspace=str(self.root / "arm-a"), protected_root=str(self.private),
            state_path=str(self.private / "arm-a-state.json"), model="gpt-6-astra", effort="high",
            conversation_ids=["client-1:conversation-1"], mcp_names=[], skill_paths=[], read_only=True,
            task_conversations={t: "client-1:conversation-1" for t in ["task-follow-up", "task-recovered"]})
        Path(self.row["workspace"]).mkdir()
        self.write([self.row])
        self.enterContext(patch.object(experiments, "_registry", None))
        self.enterContext(patch.dict(os.environ, {experiments.ENV: str(self.path),
            "GALAXYSSI_WORKSPACE_ROOT": str(self.root / "ordinary"),
            "GALAXYSSI_STATE_DIR": str(self.root / "state")}))
        self.addCleanup(experiments.close)

    def write(self, rows):
        self.path.write_text(json.dumps({"format": experiments.FORMAT, "scopes": rows}), encoding="utf-8")

    def args(self, **changes):
        return dict(route="client-1", conversation="conversation-1", backend_conversation="client-1:conversation-1",
            task_id="task-follow-up", model="gpt-6-astra", effort="high", agent_id="codex",
            attachments=[], snapshot=None, read_only=True, full_executor=True, **changes)

    def admit(self, **changes):
        return experiments.admit(**{**self.args(), **changes})


class RegistryTests(RegistryFixture):
    def test_opt_out_has_no_file_io_or_model_call(self):
        with patch.dict(os.environ, {experiments.ENV: ""}), patch.object(Path, "read_bytes") as read:
            self.assertIsNone(self.admit())
            self.assertIsNone(experiments.registered_workspace("ordinary"))
            read.assert_not_called()

    def test_exact_admission_reuses_one_owned_server_only(self):
        scope = self.admit()
        factory = Mock(return_value=Mock(executable="codex"))
        first = scope.get_server("codex", {}, Mock(), factory)
        self.assertIs(first, scope.get_server("codex", {}, Mock(), factory))
        self.assertEqual(1, factory.call_count)
        self.assertIs(factory.call_args.kwargs["experiment_boundary"], scope.boundary)
        with self.assertRaisesRegex(ExperimentBoundaryError, "executable_changed"):
            scope.get_server("different", {}, Mock(), factory)

    def test_remote_identity_and_model_cannot_widen_admission(self):
        for change in ({"route": "other"}, {"conversation": "other"},
                       {"backend_conversation": "other"}, {"model": "other"}, {"effort": "medium"},
                       {"agent_id": "deepseek"}, {"full_executor": False}, {"attachments": ["image"]},
                       {"snapshot": {}}, {"snapshot": {experiments.MARKER: "other"}}, {"scope_hint": "other"}):
            with self.subTest(change=change), self.assertRaises(ExperimentBoundaryError):
                self.admit(**change)

    def test_only_host_persisted_marker_restores_admission(self):
        scope = self.admit()
        self.assertIs(scope, self.admit(snapshot={experiments.MARKER: scope.marker}))
        with patch.object(experiments, "_registry", None), patch.dict(os.environ, {experiments.ENV: ""}):
            with self.assertRaisesRegex(ExperimentBoundaryError, "registry_required"):
                self.admit(snapshot={experiments.MARKER: scope.marker})
            with self.assertRaisesRegex(ExperimentBoundaryError, "registry_required"):
                self.admit(scope_hint=scope.marker)

    def test_unlisted_task_in_registered_conversation_is_not_ordinary(self):
        with self.assertRaisesRegex(ExperimentBoundaryError, "unregistered_task"):
            self.admit(task_id="extra-task")
        self.assertIsNone(self.admit(task_id="ordinary", conversation="ordinary"))

    def test_task_cannot_move_to_another_member_in_same_scope(self):
        self.row["conversation_ids"].append("client-1:second-member")
        self.write([self.row])
        with self.assertRaisesRegex(ExperimentBoundaryError, "admission_identity"):
            self.admit(backend_conversation="client-1:second-member")

    def test_restart_keeps_admission_and_directory_without_shared_singleton(self):
        first = self.admit()
        marker, directory = first.marker, first.workspace("task-follow-up")
        experiments.close()
        restored = self.admit(snapshot={experiments.MARKER: marker})
        self.assertIsNot(first, restored)
        self.assertEqual(directory, restored.workspace("task-follow-up"))
        self.assertIsNone(restored.server)

    def test_loaded_registry_cannot_be_removed_changed_or_redirected(self):
        self.admit()
        with patch.dict(os.environ, {experiments.ENV: ""}):
            with self.assertRaisesRegex(ExperimentBoundaryError, "configuration_changed"):
                self.admit()
        original = self.path.read_bytes()
        self.path.write_bytes(original + b" ")
        with self.assertRaisesRegex(ExperimentBoundaryError, "registry_changed"):
            self.admit()
        self.path.unlink()
        with self.assertRaisesRegex(ExperimentBoundaryError, "registry_missing"):
            experiments._registry.check_unchanged()

    def test_independent_arms_have_distinct_servers_and_workspaces(self):
        second = {**self.row, "scope_id": "arm-b", "client_conversation_id": "conversation-2",
            "conversation_ids": ["client-1:conversation-2"], "task_ids": ["task-b"],
            "task_conversations": {"task-b": "client-1:conversation-2"},
            "workspace": str(self.root / "arm-b"), "state_path": str(self.private / "arm-b-state.json")}
        Path(second["workspace"]).mkdir()
        self.write([self.row, second])
        a = self.admit()
        b = self.admit(conversation="conversation-2", backend_conversation="client-1:conversation-2", task_id="task-b")
        factory = Mock(side_effect=lambda *args, **kw: Mock(executable="codex"))
        self.assertIsNot(a.get_server("codex", {}, Mock(), factory), b.get_server("codex", {}, Mock(), factory))
        self.assertNotEqual(a.workspace("task-follow-up"), b.workspace("task-b"))
        self.assertEqual((str(b.boundary.workspace),), a.boundary.denied_roots)
        self.assertEqual((str(a.boundary.workspace),), b.boundary.denied_roots)

    def test_invalid_registry_and_overlapping_grants_fail_before_dispatch(self):
        for changed, code in (({"task_ids": ["x", "x"]}, "registry_tasks"),
                              ({"extra": "field"}, "registry_fields")):
            self.write([{**self.row, **changed}])
            with self.subTest(code=code), self.assertRaisesRegex(ExperimentBoundaryError, code):
                experiments.CodexExperimentRegistry(self.path)
        self.write([self.row, copy.deepcopy(self.row)])
        with self.assertRaises(ExperimentBoundaryError):
            experiments.CodexExperimentRegistry(self.path)

    def test_read_only_profile_never_grants_workspace_writes(self):
        scope = self.admit()
        boundary = scope.boundary
        permissions = tomllib.loads("\n".join(boundary.process_overrides()))["permissions"][boundary.profile]
        self.assertEqual(":read-only", permissions["extends"])
        self.assertEqual("read", permissions["filesystem"][str(boundary.workspace)])
        boundary.runtime_verified = True
        prepared = boundary.prepare("thread/start", {"cwd": str(boundary.workspace), "sandbox": "read-only"})
        self.assertEqual(boundary.profile, prepared["permissions"])
        self.assertNotIn("sandbox", prepared)

    def test_writable_registration_cannot_accept_read_only_request(self):
        self.write([{**self.row, "read_only": False}])
        with self.assertRaisesRegex(ExperimentBoundaryError, "read_only_profile_not_verified"):
            self.admit()

    def test_artifact_resolution_and_retention_use_registered_directory(self):
        from task_workspace import task_workspace, task_artifacts, task_artifact_path, cleanup_task_workspace, cleanup_task_temporary_files
        scope = self.admit()
        directory = task_workspace("task-follow-up", "codex")
        self.assertEqual(scope.workspace("task-follow-up"), directory)
        output = directory / "outputs" / "fixture.txt"
        output.write_text("synthetic", encoding="utf-8")
        self.assertEqual(output, task_artifact_path("task-follow-up", "outputs/fixture.txt"))
        self.assertEqual("fixture.txt", task_artifacts("task-follow-up")[0]["name"])
        self.assertFalse(cleanup_task_workspace("task-follow-up"))
        self.assertEqual([], cleanup_task_temporary_files(["task-follow-up"]))
        self.assertTrue(output.exists())
        self.assertNotEqual(directory, task_workspace("ordinary", "codex"))

    def test_registry_must_itself_be_in_protected_subtree(self):
        outside = self.root / "outside.json"
        outside.write_bytes(self.path.read_bytes())
        with self.assertRaisesRegex(ExperimentBoundaryError, "unprotected_registry"):
            experiments.CodexExperimentRegistry(outside)

    def test_snapshot_roundtrip_retains_marker_but_remote_options_cannot_restore_it(self):
        from agent_request_snapshot import build_request_snapshot, snapshot_copy, restore_request_options
        scope = self.admit()
        payload = {experiments.MARKER: scope.marker}
        snapshot = build_request_snapshot(payload, model_id="gpt-6-astra", reasoning_effort="high", policy={})
        self.assertNotIn(experiments.MARKER, snapshot)
        snapshot[experiments.MARKER] = scope.marker
        self.assertEqual(scope.marker, snapshot_copy(snapshot)[experiments.MARKER])
        self.assertNotIn(experiments.MARKER, restore_request_options(snapshot))
