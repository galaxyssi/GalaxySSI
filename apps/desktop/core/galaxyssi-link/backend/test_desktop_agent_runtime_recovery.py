import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from desktop_agent_adapters import AgentAdapterRequest, AgentAdapterResult, AgentDeliveryMode
from desktop_agent_runtime_server import DesktopAgentRuntimeStore


class DesktopRuntimeCrashRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "runtime.json"

    def tearDown(self):
        self.temporary.cleanup()

    def request(self, run_id="run-1"):
        return AgentAdapterRequest(
            agent_id="codex", prompt="Inspect the repository", run_id=run_id,
            idempotency_key=f"request:{run_id}", conversation_id="conversation-1",
            checkpoint={"client_route_id": "phone-s26u", "task_id": f"task:{run_id}",
                        "goal_id": "goal-1", "turn_id": f"turn:{run_id}"},
        ).normalized()

    def result(self, run_id="run-1"):
        return AgentAdapterResult(
            run_id=run_id, agent_id="codex", delivery_mode=AgentDeliveryMode.RESPOND,
            state="completed", reply="Verified result", checkpoint={"resume": "cursor-7"},
            artifacts=({"artifact_id": "artifact-1", "sha256": "abc"},),
        )

    def test_projection_write_loss_at_every_lifecycle_boundary(self):
        for operation in ("claim", "start", "finish", "fail", "cancel", "interrupt"):
            with self.subTest(operation=operation):
                path = self.path.with_name(f"{operation}.json")
                store = DesktopAgentRuntimeStore(path)
                request = self.request(operation)
                if operation != "claim":
                    store.claim(request)
                actions = {
                    "claim": lambda: store.claim(request),
                    "start": lambda: store.transition_running(operation),
                    "finish": lambda: store.finish(operation, self.result(operation)),
                    "fail": lambda: store.fail(operation, "provider disconnected"),
                    "cancel": lambda: store.cancel(operation),
                    "interrupt": lambda: store.interrupt_active("process shutdown"),
                }
                with patch.object(store, "_save_locked", side_effect=OSError("disk interrupted")):
                    with self.assertRaises(OSError):
                        actions[operation]()
                restored = DesktopAgentRuntimeStore(path)
                expected = {"finish": "completed", "fail": "failed", "cancel": "cancelled"}
                snapshot = restored.status(operation)
                self.assertEqual(expected.get(operation, "interrupted"), snapshot["state"])
                self.assertEqual("phone-s26u", snapshot["client_route_id"])
                self.assertEqual(f"turn:{operation}", snapshot["turn_id"])
                if operation == "finish":
                    result = restored.adapter_result(operation)
                    self.assertEqual("Verified result", result.reply)
                    self.assertEqual({"resume": "cursor-7"}, result.checkpoint)
                    self.assertEqual("artifact-1", result.artifacts[0]["artifact_id"])
                if operation == "fail":
                    self.assertEqual("provider disconnected", snapshot["error"])
                if operation == "interrupt":
                    self.assertEqual("process shutdown", snapshot["error"])
                session = restored.session(snapshot["session_id"])
                self.assertEqual("idle", session["state"])
                self.assertEqual(snapshot["state"], session["last_state"])
                events = restored.kernel_events(operation)
                again = DesktopAgentRuntimeStore(path)
                self.assertEqual(events, again.kernel_events(operation))
                self.assertEqual(snapshot, again.status(operation))

    def test_process_exit_after_commit_preserves_result_without_projection_save(self):
        script = """
import os, sys
from pathlib import Path
from desktop_agent_adapters import AgentAdapterRequest, AgentAdapterResult, AgentDeliveryMode
from desktop_agent_runtime_server import DesktopAgentRuntimeStore
store = DesktopAgentRuntimeStore(Path(sys.argv[1]))
request = AgentAdapterRequest(agent_id='codex', prompt='test', run_id='crash-run',
    idempotency_key='crash-request', conversation_id='conversation-1',
    checkpoint={'client_route_id':'phone-s26u','task_id':'crash-task','turn_id':'turn-1'}).normalized()
store.claim(request)
store.transition_running('crash-run')
store._save_locked = lambda: os._exit(73)
store.finish('crash-run', AgentAdapterResult(run_id='crash-run', agent_id='codex',
    delivery_mode=AgentDeliveryMode.RESPOND, state='completed', reply='durable before exit'))
"""
        result = subprocess.run(
            [sys.executable, "-c", script, str(self.path)],
            cwd=Path(__file__).parent, capture_output=True, text=True, timeout=30,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )
        self.assertEqual(73, result.returncode, result.stderr)
        self.assertEqual("running", json.loads(self.path.read_text())["runs"]["crash-run"]["state"])
        restored = DesktopAgentRuntimeStore(self.path)
        self.assertEqual("durable before exit", restored.adapter_result("crash-run").reply)
        self.assertEqual("completed", restored.status("crash-run")["state"])

    def test_missing_json_restores_recent_and_older_live_runs_not_entire_history(self):
        with patch("desktop_agent_runtime_server.MAX_RUNTIME_RUNS", 2):
            store = DesktopAgentRuntimeStore(self.path)
            store.claim(self.request("old-live"))
            for index in range(5):
                run_id = f"finished-{index}"
                store.claim(self.request(run_id))
                store.finish(run_id, self.result(run_id))
            self.path.unlink()
            restored = DesktopAgentRuntimeStore(self.path)
            self.assertEqual(
                {"old-live", "finished-3", "finished-4"},
                {row["run_id"] for row in restored.runs()},
            )
            self.assertEqual("interrupted", restored.status("old-live")["state"])
            self.assertEqual("Verified result", restored.adapter_result("finished-4").reply)
            self.assertEqual(2, len(restored.kernel_events("finished-0")))

    def test_same_cursor_corrupt_projection_cannot_change_conversation_or_result(self):
        store = DesktopAgentRuntimeStore(self.path)
        store.claim(self.request())
        store.finish("run-1", self.result())
        document = json.loads(self.path.read_text())
        row = document["runs"]["run-1"]
        row["client_route_id"] = "wrong-phone"
        row["conversation_id"] = "wrong-conversation"
        row["adapter_result"]["reply"] = "wrong reply"
        self.path.write_text(json.dumps(document), encoding="utf-8")
        restored = DesktopAgentRuntimeStore(self.path)
        self.assertEqual("phone-s26u", restored.status("run-1")["client_route_id"])
        self.assertEqual("conversation-1", restored.status("run-1")["conversation_id"])
        self.assertEqual("Verified result", restored.adapter_result("run-1").reply)

    def test_restore_and_idempotent_request_do_not_execute_a_completed_run_again(self):
        store = DesktopAgentRuntimeStore(self.path)
        request = self.request()
        store.claim(request)
        store.finish(request.run_id, self.result())
        self.path.unlink()
        restored = DesktopAgentRuntimeStore(self.path)
        replay, created = restored.claim(request)
        self.assertFalse(created)
        self.assertTrue(replay["replayed"])
        self.assertEqual("completed", replay["state"])
        self.assertEqual(2, len(restored.kernel_events(request.run_id)))


if __name__ == "__main__":
    unittest.main()
