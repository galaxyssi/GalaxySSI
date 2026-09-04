import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_file_access_ledger import (
    PROTOCOL,
    AgentFileAccessError,
    AgentFileAccessLedger,
    AgentWorkspaceCapture,
    FileAccessScope,
    FileObservation,
    capture_workspace,
    repository_identity,
)
from desktop_native_tools import (
    FILE_READ_TEXT,
    FILE_WRITE_TEXT,
    DesktopNativeToolRegistry,
    _digest,
)
from agent_gateway import AgentSpec, _execute_agent_adapter_request
from desktop_agent_adapters import AgentAdapterRequest


def observation(path: str, content: bytes, *, exists: bool = True) -> FileObservation:
    return FileObservation.create(
        path,
        sha256=hashlib.sha256(content).hexdigest() if exists else "",
        exists=exists,
        size_bytes=len(content) if exists else 0,
    )


class AgentFileAccessLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.notices = []
        self.ledger = AgentFileAccessLedger(
            self.root / "ledger.json",
            notifier=lambda conflict, channels: self.notices.append(
                (conflict, channels)
            ),
        )
        self.scope = FileAccessScope.create(
            client_route_id="phone-1",
            conversation_id="conversation-1",
            task_id="task-1",
            repository_id="repo-1",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_other_agent_write_after_read_creates_conflict_and_notice(self):
        original = observation("src/app.py", b"old")
        updated = observation("src/app.py", b"new")
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=original,
        )

        result = self.ledger.record_write(
            self.scope,
            agent_id="claude-code",
            observation=updated,
            collaboration_channel_ids=("channel-1",),
        )

        self.assertEqual(1, len(result["conflicts_created"]))
        conflict = result["conflicts_created"][0]
        self.assertEqual("codex", conflict["reader_agent_id"])
        self.assertEqual("claude-code", conflict["writer_agent_id"])
        self.assertEqual("src/app.py", conflict["path"])
        self.assertEqual((conflict, ("channel-1",)), self.notices[0])

    def test_default_notifier_publishes_to_scoped_collaboration_channel(self):
        with patch.dict(
            os.environ,
            {"GALAXYSSI_STATE_DIR": str(self.root / "collaboration-state")},
        ):
            from agent_collaboration_channels import (
                CollaborationScope,
                agent_collaboration_bus,
            )

            bus = agent_collaboration_bus()
            channel = bus.create_channel(
                kind="repository",
                creator_agent_id="codex",
                participant_agent_ids=("codex", "hermes"),
                scope=CollaborationScope.create(
                    client_route_id="phone-1",
                    conversation_id="conversation-1",
                    task_id="task-1",
                    repository_id="repo-1",
                ),
            )
            ledger = AgentFileAccessLedger(
                self.root / "collaboration-ledger.json"
            )
            ledger.record_read(
                self.scope,
                agent_id="codex",
                observation=observation("src/app.py", b"old"),
            )
            ledger.record_write(
                self.scope,
                agent_id="hermes",
                observation=observation("src/app.py", b"new"),
                collaboration_channel_ids=(channel["channel_id"],),
            )
            messages = bus.messages(
                channel["channel_id"],
                requester_agent_id="codex",
            )

        self.assertEqual(1, len(messages))
        self.assertEqual("file_conflict", messages[0]["metadata"]["kind"])
        self.assertEqual("src/app.py", messages[0]["metadata"]["path"])

    def test_agent_does_not_conflict_with_its_own_read(self):
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=observation("main.py", b"one"),
        )

        result = self.ledger.record_write(
            self.scope,
            agent_id="codex",
            observation=observation("main.py", b"two"),
        )

        self.assertEqual([], result["conflicts_created"])
        self.assertEqual([], self.ledger.conflicts(self.scope))

    def test_scope_isolates_route_task_and_repository(self):
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=observation("main.py", b"one"),
        )
        isolated = FileAccessScope.create(
            client_route_id="phone-2",
            conversation_id="conversation-1",
            task_id="task-1",
            repository_id="repo-1",
        )
        self.ledger.record_write(
            isolated,
            agent_id="claude-code",
            observation=observation("main.py", b"two"),
        )

        self.assertEqual([], self.ledger.conflicts(self.scope))
        self.assertEqual([], self.ledger.conflicts(isolated))

    def test_refreshing_current_file_resolves_conflict(self):
        original = observation("main.py", b"one")
        updated = observation("main.py", b"two")
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=original,
        )
        self.ledger.record_write(
            self.scope,
            agent_id="hermes",
            observation=updated,
        )
        self.assertEqual(1, len(self.ledger.conflicts(self.scope)))

        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=updated,
        )

        self.assertEqual([], self.ledger.conflicts(self.scope))
        resolved = self.ledger.conflicts(self.scope, status="resolved")
        self.assertEqual("refreshed", resolved[0]["resolution"])

    def test_state_and_open_conflicts_survive_restart(self):
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=observation("main.py", b"one"),
        )
        self.ledger.record_write(
            self.scope,
            agent_id="hermes",
            observation=observation("main.py", b"two"),
        )

        restored = AgentFileAccessLedger(
            self.root / "ledger.json",
            notifier=lambda _conflict, _channels: None,
        )

        self.assertEqual(1, len(restored.conflicts(self.scope)))
        self.assertEqual(PROTOCOL, restored.health()["protocol"])
        self.assertEqual(1, restored.health()["open_conflicts"])

    def test_event_replay_does_not_duplicate_conflict(self):
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=observation("main.py", b"one"),
        )
        first = self.ledger.record_write(
            self.scope,
            agent_id="hermes",
            observation=observation("main.py", b"two"),
            event_id="event-1",
        )
        replay = self.ledger.record_write(
            self.scope,
            agent_id="hermes",
            observation=observation("main.py", b"two"),
            event_id="event-1",
        )

        self.assertEqual(1, len(first["conflicts_created"]))
        self.assertTrue(replay["replayed"])
        self.assertEqual(1, len(self.ledger.conflicts(self.scope)))

    def test_context_is_bounded_and_marks_conflicts_as_untrusted(self):
        self.ledger.record_read(
            self.scope,
            agent_id="codex",
            observation=observation("src/main.py", b"one"),
        )
        self.ledger.record_write(
            self.scope,
            agent_id="hermes",
            observation=observation("src/main.py", b"two"),
        )

        context = self.ledger.compile_context(
            self.scope,
            requester_agent_id="codex",
            max_chars=800,
        )

        self.assertIn("untrusted state evidence", context)
        self.assertIn("src/main.py", context)
        self.assertIn("re-read", context.lower())
        self.assertLessEqual(len(context), 800)

    def test_absolute_paths_are_rejected_and_not_persisted(self):
        with self.assertRaises(AgentFileAccessError):
            FileObservation.create(str(self.root / "private.txt"))

        self.assertFalse((self.root / "ledger.json").exists())

    def test_workspace_capture_detects_create_modify_delete_and_ignores_cache(self):
        workspace = self.root / "repository"
        workspace.mkdir()
        (workspace / "read.txt").write_text("before", encoding="utf-8")
        (workspace / "deleted.txt").write_text("delete", encoding="utf-8")
        (workspace / "node_modules").mkdir()
        (workspace / "node_modules" / "ignored.js").write_text(
            "ignored",
            encoding="utf-8",
        )
        capture = AgentWorkspaceCapture.begin(
            workspace,
            scope=self.scope,
            agent_id="codex",
            ledger=self.ledger,
            capture_id="capture-1",
        )
        (workspace / "read.txt").write_text("after", encoding="utf-8")
        (workspace / "deleted.txt").unlink()
        (workspace / "created.txt").write_text("created", encoding="utf-8")

        result = capture.finish()

        self.assertEqual(3, result["writes_recorded"])
        self.assertNotIn(
            "node_modules/ignored.js",
            capture_workspace(workspace),
        )

    def test_repository_identity_does_not_expose_absolute_path(self):
        identity = repository_identity(self.root / "private-project")

        self.assertTrue(identity.startswith("repo-"))
        self.assertNotIn(str(self.root), identity)

    def test_legacy_conflict_is_not_injected_into_agent_execution(self):
        with patch.dict(
            os.environ,
            {"GALAXYSSI_STATE_DIR": str(self.root / "shared-state")},
        ):
            from agent_file_access_ledger import agent_file_access_ledger

            scope = FileAccessScope.create(
                client_route_id="phone-1",
                conversation_id="conversation-1",
                task_id="task-1",
                workspace_id="agent-task-run-1",
            )
            shared = agent_file_access_ledger()
            shared.record_read(
                scope,
                agent_id="hermes",
                observation=observation("src/app.py", b"one"),
            )
            shared.record_write(
                scope,
                agent_id="codex",
                observation=observation("src/app.py", b"two"),
            )
            prompts = []
            spec = AgentSpec(
                id="hermes",
                name="Hermes Agent",
                kind="cloud-model",
                command=["hermes"],
                timeout=10,
            )

            def answer(_agent_id, prompt, *_args, **_kwargs):
                prompts.append(prompt)
                return "I re-read src/app.py and used its current content."

            with patch(
                "agent_gateway.all_agent_specs",
                return_value={"hermes": spec},
            ), patch(
                "agent_gateway._ask_agent_sync_inner",
                side_effect=answer,
            ):
                reply = _execute_agent_adapter_request(
                    "hermes",
                    AgentAdapterRequest(
                        agent_id="hermes",
                        prompt="Continue the implementation.",
                        run_id="run-1",
                        conversation_id="conversation-1",
                        checkpoint={
                            "execution_prompt": "Continue the implementation.",
                            "client_route_id": "phone-1",
                            "task_id": "task-1",
                            "collaboration_task_id": "task-1",
                            "collaboration_actor_id": "hermes",
                        },
                    ),
                )

        self.assertIn("current content", reply)
        self.assertNotIn("file conflict evidence", prompts[0])
        self.assertNotIn("src/app.py", prompts[0])


class NativeToolFileAccessIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.workspace_root = self.root / "workspaces"
        self.registry = DesktopNativeToolRegistry(
            state_root=self.root / "native-state",
            workspace_root=self.workspace_root,
            known_roots={"workspace": self.workspace_root},
        )
        self.workspace = self.workspace_root / "shared"
        self.workspace.mkdir(parents=True)

    def tearDown(self):
        self.temporary.cleanup()

    def invoke(
        self,
        tool_id: str,
        arguments: dict,
        *,
        agent_id: str,
        invocation_id: str,
        confirmed: bool = False,
    ) -> dict:
        confirmation = None
        if confirmed:
            confirmation = {
                "decision": "approved",
                "tool_id": tool_id,
                "tool_version": "1.0.0",
                "arguments_sha256": _digest(arguments),
                "expires_at": int(__import__("time").time() * 1000) + 60_000,
            }
        return self.registry.invoke(
            tool_id,
            arguments,
            {
                "invocation_id": invocation_id,
                "idempotency_key": invocation_id,
                "confirmation": confirmation,
                "agent_id": agent_id,
                "client_route_id": "phone-1",
                "conversation_id": "conversation-1",
                "task_id": "task-1",
            },
        )

    def test_native_file_tools_do_not_write_the_legacy_file_ledger(self):
        source = self.workspace / "shared.txt"
        source.write_text("before", encoding="utf-8")
        with patch.dict(
            os.environ,
            {"GALAXYSSI_STATE_DIR": str(self.root / "ledger-state")},
        ):
            read = self.invoke(
                FILE_READ_TEXT,
                {"workspace_id": "shared", "path": "shared.txt"},
                agent_id="codex",
                invocation_id="read-1",
            )
            written = self.invoke(
                FILE_WRITE_TEXT,
                {
                    "workspace_id": "shared",
                    "path": "shared.txt",
                    "content": "after",
                    "mode": "overwrite",
                },
                agent_id="hermes",
                invocation_id="write-1",
                confirmed=True,
            )
            from agent_file_access_ledger import agent_file_access_ledger

            scope = FileAccessScope.create(
                client_route_id="phone-1",
                conversation_id="conversation-1",
                task_id="task-1",
                workspace_id="shared",
            )
            conflicts = agent_file_access_ledger().conflicts(scope)

        self.assertEqual("succeeded", read["status"])
        self.assertEqual("succeeded", written["status"])
        self.assertEqual([], conflicts)

    def test_file_access_api_is_token_protected(self):
        source = (
            Path(__file__).with_name("main.py").read_text(encoding="utf-8")
        )

        self.assertIn('"/api/agent-runtime/file-access"', source)
        self.assertIn('"/api/agent-runtime/file-conflicts"', source)
        route_section = source[source.index(
            '"/api/agent-runtime/file-access"'
        ):source.index('"/api/desktop-tools"')]
        self.assertGreaterEqual(
            route_section.count("require_desktop_api_token(request)"),
            3,
        )


if __name__ == "__main__":
    unittest.main()
