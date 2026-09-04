import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_file_access_ledger import (
    AgentFileAccessLedger,
    AgentWorkspaceCapture,
    FileAccessScope,
)
from host_execution_config_guard import (
    HostExecutionConfigGuard,
    HostExecutionConfigViolation,
    assert_host_execution_path_writable,
    classify_host_execution_path,
)


class HostExecutionConfigGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.environment = patch.dict(
            os.environ,
            {"GALAXYSSI_STATE_DIR": str(self.root / "state")},
        )
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def test_policy_protects_host_execution_surfaces_without_blocking_source(self):
        protected = (
            ".galaxyssi-task.json",
            ".galaxyssi/execution-checkpoint.json",
            ".git/hooks/pre-commit",
            ".git/config",
            ".git/modules/sdk/config",
            ".github/workflows/release.yml",
            ".openai/hosting.json",
            ".codex/config.toml",
            ".claude/settings.json",
            ".vscode/tasks.json",
            ".idea/runConfigurations/App.xml",
            ".env.production",
            ".venv/lib/site-packages/bootstrap.pth",
        )
        allowed = (
            "src/main.py",
            "package.json",
            "pyproject.toml",
            "README.md",
            ".env.example",
            "Dockerfile",
        )

        for path in protected:
            with self.subTest(path=path):
                self.assertIsNotNone(classify_host_execution_path(path))
        for path in allowed:
            with self.subTest(path=path):
                self.assertIsNone(classify_host_execution_path(path))

    def test_guard_restores_modified_host_state_and_removes_new_workflow(self):
        metadata = self.workspace / ".galaxyssi-task.json"
        metadata.write_text('{"task_id":"trusted"}', encoding="utf-8")
        guard = HostExecutionConfigGuard.begin(
            self.workspace,
            agent_id="codex",
            capture_id="capture-security",
        )

        metadata.write_text('{"task_id":"attacker"}', encoding="utf-8")
        workflow = self.workspace / ".github" / "workflows" / "pwn.yml"
        workflow.parent.mkdir(parents=True)
        workflow.write_text("runs-on: self-hosted", encoding="utf-8")
        violations = guard.finish()

        self.assertEqual('{"task_id":"trusted"}', metadata.read_text(encoding="utf-8"))
        self.assertFalse(workflow.exists())
        self.assertEqual(
            {".galaxyssi-task.json", ".github/workflows", ".github/workflows/pwn.yml"},
            {item["path"] for item in violations},
        )
        audit_path = (
            self.root
            / "state"
            / "security"
            / "host-config-write-audit.jsonl"
        )
        audit = json.loads(audit_path.read_text(encoding="utf-8").splitlines()[0])
        self.assertEqual("galaxyssi.host-execution-config-guard/1.0", audit["protocol"])
        self.assertEqual("codex", audit["agent_id"])
        self.assertNotIn(str(self.workspace), audit_path.read_text(encoding="utf-8"))

    def test_direct_write_is_rejected_before_a_protected_file_is_created(self):
        target = self.workspace / ".env.local"

        with self.assertRaises(HostExecutionConfigViolation):
            assert_host_execution_path_writable(
                self.workspace,
                target,
                agent_id="native-tool",
                capture_id="write-1",
            )

        self.assertFalse(target.exists())

    def test_workspace_capture_records_attempt_and_raises_after_rollback(self):
        ledger = AgentFileAccessLedger(self.root / "ledger.json")
        scope = FileAccessScope.create(
            client_route_id="phone-1",
            conversation_id="conversation-1",
            task_id="task-1",
            workspace_id="workspace-1",
        )
        capture = AgentWorkspaceCapture.begin(
            self.workspace,
            scope=scope,
            agent_id="hermes",
            ledger=ledger,
            capture_id="capture-1",
        )
        hook = self.workspace / ".git" / "hooks" / "post-checkout"
        hook.parent.mkdir(parents=True)
        hook.write_text("malicious", encoding="utf-8")

        with self.assertRaises(HostExecutionConfigViolation):
            capture.finish()

        self.assertFalse(hook.exists())
        state = json.loads(
            (self.root / "ledger.json").read_text(encoding="utf-8")
        )
        recorded_paths = {
            file_row["path"]
            for scope_row in state["scopes"].values()
            for file_row in scope_row["files"].values()
        }
        self.assertIn(".git/hooks/post-checkout", recorded_paths)


if __name__ == "__main__":
    unittest.main()
