import tempfile
import threading
import time
import unittest
from pathlib import Path

from desktop_agent_adapters import (
    AgentAdapterDescriptor,
    AgentAdapterRequest,
    DesktopAgentProvider,
    DesktopAgentStateStore,
)
from desktop_agent_runtime_server import (
    DesktopAgentRuntimeConflict,
    DesktopAgentRuntimeServer,
    DesktopAgentRuntimeStore,
    RUNTIME_PROTOCOL,
)


def descriptor(agent_id: str = "codex") -> AgentAdapterDescriptor:
    return AgentAdapterDescriptor(
        agent_id=agent_id,
        name=agent_id.title(),
        kind="local-cli",
        adapter_type="test",
        timeout_seconds=2,
        capabilities=("conversation", "tasks"),
    )


class DesktopAgentRuntimeServerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.calls: list[tuple[str, str]] = []
        self.servers: list[DesktopAgentRuntimeServer] = []

    def tearDown(self):
        for server in self.servers:
            server.shutdown(wait=True)
        self.temporary.cleanup()

    def server(self, execute=None, max_workers: int = 2) -> DesktopAgentRuntimeServer:
        def default_execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            return f"reply:{request.prompt}"

        provider = DesktopAgentProvider(
            descriptors=(descriptor(),),
            store=DesktopAgentStateStore(self.root / "adapter-state.json"),
            executor=execute or default_execute,
        )
        server = DesktopAgentRuntimeServer(
            provider=provider,
            store=DesktopAgentRuntimeStore(self.root / "runtime-state.json"),
            max_workers=max_workers,
        )
        self.servers.append(server)
        return server

    @staticmethod
    def request(
        prompt: str,
        *,
        run_id: str,
        idempotency_key: str = "",
        conversation_id: str = "conversation-1",
        route_id: str = "phone-1",
        turn_id: str = "",
    ) -> AgentAdapterRequest:
        return AgentAdapterRequest(
            agent_id="codex",
            prompt=prompt,
            run_id=run_id,
            idempotency_key=idempotency_key or run_id,
            conversation_id=conversation_id,
            checkpoint={
                "client_route_id": route_id,
                "task_id": run_id,
                "turn_id": turn_id or f"turn-{run_id}",
            },
        )

    def test_submit_runs_asynchronously_and_execute_waits_for_result(self):
        started = threading.Event()
        release = threading.Event()

        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            started.set()
            release.wait(timeout=2)
            return "done"

        server = self.server(execute)
        request = self.request("build", run_id="run-1")

        submitted = server.submit(request)
        self.assertIn(submitted["state"], {"queued", "running"})
        self.assertTrue(started.wait(timeout=1))
        waiter = threading.Thread(target=lambda: server.execute(request))
        waiter.start()
        release.set()
        waiter.join(timeout=2)

        self.assertEqual("completed", server.status("run-1")["state"])
        self.assertEqual([("codex", "build")], self.calls)
        self.assertEqual(
            ["run_queued", "run_started", "run_completed"],
            [item["type"] for item in server.events("run-1")],
        )

    def test_session_is_reused_for_same_agent_route_and_conversation(self):
        server = self.server()

        first = server.execute(self.request("one", run_id="run-1"))
        second = server.execute(self.request("two", run_id="run-2"))
        sessions = server.sessions()

        self.assertEqual("completed", first.state)
        self.assertEqual("completed", second.state)
        self.assertEqual(1, len(sessions))
        self.assertEqual(2, sessions[0]["run_count"])
        self.assertEqual("run-2", sessions[0]["last_run_id"])

    def test_routes_or_conversations_get_distinct_sessions(self):
        server = self.server()

        server.execute(self.request("one", run_id="run-1"))
        server.execute(self.request(
            "two",
            run_id="run-2",
            conversation_id="conversation-2",
        ))
        server.execute(self.request(
            "three",
            run_id="run-3",
            route_id="phone-2",
        ))

        self.assertEqual(3, len(server.sessions()))

    def test_idempotent_duplicate_executes_once_and_conflict_is_rejected(self):
        server = self.server()
        request = self.request("one", run_id="run-1", idempotency_key="stable")

        first = server.execute(request)
        replay = server.execute(request)

        self.assertEqual("completed", first.state)
        self.assertEqual("completed", replay.state)
        self.assertTrue(replay.replayed)
        self.assertEqual([("codex", "one")], self.calls)
        with self.assertRaises(DesktopAgentRuntimeConflict):
            server.submit(self.request(
                "different",
                run_id="run-2",
                idempotency_key="stable",
            ))

    def test_global_concurrency_is_bounded(self):
        release = threading.Event()
        two_started = threading.Event()
        lock = threading.Lock()
        active = 0
        peak = 0

        def execute(agent_id, request):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
                if active == 2:
                    two_started.set()
            release.wait(timeout=2)
            with lock:
                active -= 1
            return request.prompt

        server = self.server(execute, max_workers=2)
        requests = [self.request(str(index), run_id=f"run-{index}") for index in range(3)]
        for request in requests:
            server.submit(request)

        self.assertTrue(two_started.wait(timeout=1))
        self.assertEqual(2, peak)
        self.assertEqual(2, server.health()["active_runs"])
        self.assertEqual(1, server.health()["queued_runs"])
        self.assertEqual(3, server.health()["pending_futures"])
        release.set()
        for request in requests:
            server.execute(request)
        self.assertEqual(2, peak)

    def test_queued_run_can_be_cancelled_without_agent_execution(self):
        started = threading.Event()
        release = threading.Event()

        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            if request.run_id == "run-1":
                started.set()
                release.wait(timeout=2)
            return request.prompt

        server = self.server(execute, max_workers=1)
        first = self.request("first", run_id="run-1")
        second = self.request("second", run_id="run-2")
        server.submit(first)
        self.assertTrue(started.wait(timeout=1))
        server.submit(second)

        cancelled = server.cancel("run-2")
        release.set()
        server.execute(first)
        time.sleep(0.05)

        self.assertEqual("cancelled", cancelled["state"])
        self.assertEqual("cancelled", server.status("run-2")["state"])
        self.assertNotIn(("codex", "second"), self.calls)

    def test_restart_marks_queued_and_running_runs_recoverable(self):
        store = DesktopAgentRuntimeStore(self.root / "runtime-state.json")
        queued = self.request("queued", run_id="queued-run").normalized()
        running = self.request("running", run_id="running-run").normalized()
        store.claim(queued)
        store.claim(running)
        store.transition_running("running-run")

        recovered = DesktopAgentRuntimeStore(self.root / "runtime-state.json")

        self.assertEqual("interrupted", recovered.status("queued-run")["state"])
        self.assertEqual("interrupted", recovered.status("running-run")["state"])
        self.assertEqual(
            "run_interrupted",
            recovered.events("running-run")[-1]["type"],
        )

    def test_health_exposes_protocol_capacity_and_durable_counts(self):
        server = self.server(max_workers=3)
        server.execute(self.request("hello", run_id="run-1"))

        health = server.health()

        self.assertEqual(RUNTIME_PROTOCOL, health["protocol"])
        self.assertEqual("ready", health["status"])
        self.assertEqual(3, health["max_concurrency"])
        self.assertEqual(1, health["runs"])
        self.assertEqual(1, health["sessions"])
        self.assertIn("durable_run_registry", health["features"])


if __name__ == "__main__":
    unittest.main()
