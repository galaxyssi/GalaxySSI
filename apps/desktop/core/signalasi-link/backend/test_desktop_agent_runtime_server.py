import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

from desktop_agent_adapters import (
    AgentAdapterDescriptor,
    AgentAdapterExecutionError,
    AgentAdapterRequest,
    AgentInvocationMode,
    AgentRunPriority,
    DesktopAgentProvider,
    DesktopAgentStateStore,
)
from desktop_agent_runtime_server import (
    AgentCapacityController,
    AgentFaultDomainRegistry,
    DesktopAgentCapacityExhausted,
    DesktopAgentFaultIsolated,
    DesktopAgentRuntimeConflict,
    DesktopAgentRuntimeError,
    DesktopAgentRuntimeServer,
    DesktopAgentRuntimeStore,
    RUNTIME_PROTOCOL,
)
from agent_memory_telemetry import (
    DEFAULT_SESSION_MEMORY_TARGET_BYTES,
    process_memory_reading,
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

    def server(
        self,
        execute=None,
        max_workers: int = 2,
        max_queued_runs: int = 64,
        descriptors=None,
        fault_domains: AgentFaultDomainRegistry | None = None,
        capacity: AgentCapacityController | None = None,
        session_memory_reader=None,
        session_memory_observer=None,
    ) -> DesktopAgentRuntimeServer:
        def default_execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            return f"reply:{request.prompt}"

        provider = DesktopAgentProvider(
            descriptors=descriptors or (descriptor(),),
            store=DesktopAgentStateStore(self.root / "adapter-state.json"),
            executor=execute or default_execute,
        )
        server = DesktopAgentRuntimeServer(
            provider=provider,
            store=DesktopAgentRuntimeStore(self.root / "runtime-state.json"),
            max_workers=max_workers,
            max_queued_runs=max_queued_runs,
            fault_domains=fault_domains,
            capacity=capacity,
            session_memory_reader=session_memory_reader,
            session_memory_observer=session_memory_observer,
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
        agent_id: str = "codex",
        priority: AgentRunPriority = AgentRunPriority.FOREGROUND,
    ) -> AgentAdapterRequest:
        return AgentAdapterRequest(
            agent_id=agent_id,
            prompt=prompt,
            run_id=run_id,
            idempotency_key=idempotency_key or run_id,
            conversation_id=conversation_id,
            priority=priority,
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

    def test_new_session_memory_is_measured_once_before_agent_execution(self):
        readings = iter([
            (100 * 1_048_576, "windows_working_set"),
            (109 * 1_048_576, "windows_working_set"),
            (109 * 1_048_576, "windows_working_set"),
        ])
        observed = []
        server = self.server(
            session_memory_reader=lambda: next(readings),
            session_memory_observer=observed.append,
        )

        server.execute(self.request("one", run_id="run-memory-1"))
        server.execute(self.request("two", run_id="run-memory-2"))

        self.assertEqual(1, len(observed))
        self.assertEqual(100 * 1_048_576, observed[0]["before_bytes"])
        self.assertEqual(109 * 1_048_576, observed[0]["after_bytes"])
        self.assertEqual("conversation-1", observed[0]["conversation_id"])
        self.assertTrue(server.status("run-memory-1")["session_created"])
        self.assertFalse(server.status("run-memory-2")["session_created"])

    def test_runtime_registry_stays_well_below_twenty_mib_per_session(self):
        store = DesktopAgentRuntimeStore(self.root / "session-budget-state.json")
        before = process_memory_reading(os.getpid()).resident_bytes
        session_count = 200

        for index in range(session_count):
            store.claim(self.request(
                "measure lightweight session shell",
                run_id=f"run-budget-{index}",
                conversation_id=f"conversation-budget-{index}",
            ))

        after = process_memory_reading(os.getpid()).resident_bytes
        average_increment = max(0, after - before) // session_count

        self.assertLess(average_increment, DEFAULT_SESSION_MEMORY_TARGET_BYTES)
        self.assertEqual(session_count, store.counts()["sessions"])

    def test_parent_child_agent_runs_are_persisted_and_queryable(self):
        server = self.server(descriptors=(descriptor("codex"), descriptor("hermes")))
        result = server.execute(AgentAdapterRequest(
            agent_id="hermes",
            prompt="Verify the implementation",
            run_id="child-run",
            idempotency_key="child-run",
            invocation_mode=AgentInvocationMode.TOOL,
            caller_agent_id="codex",
            parent_run_id="parent-run",
            handoff_chain=("coordinator", "codex"),
            conversation_id="conversation-1",
            checkpoint={
                "client_route_id": "phone-1",
                "task_id": "parent-run",
                "turn_id": "turn-child",
            },
        ))

        child = server.status("child-run")
        children = server.runs(parent_run_id="parent-run")

        self.assertEqual("completed", result.state)
        self.assertEqual("tool", child["invocation_mode"])
        self.assertEqual("codex", child["caller_agent_id"])
        self.assertEqual("parent-run", child["parent_run_id"])
        self.assertEqual(["coordinator", "codex"], child["handoff_chain"])
        self.assertEqual("codex", child["response_owner_agent_id"])
        self.assertEqual(["child-run"], [item["run_id"] for item in children])
        self.assertEqual(
            ["child-run"],
            [item["run_id"] for item in server.runs(invocation_mode="tool")],
        )

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

    def test_session_registry_tracks_active_run_and_terminal_summary(self):
        started = threading.Event()
        release = threading.Event()

        def execute(agent_id, request):
            started.set()
            release.wait(timeout=2)
            return "done"

        server = self.server(execute)
        request = self.request(
            "build",
            run_id="run-active",
            turn_id="turn-active",
        )
        server.submit(request)
        self.assertTrue(started.wait(timeout=1))

        active = server.sessions(state="active")
        self.assertEqual(1, len(active))
        self.assertEqual(1, active[0]["active_run_count"])
        self.assertEqual("run-active", active[0]["last_task_id"])
        self.assertEqual("turn-active", active[0]["last_turn_id"])
        self.assertEqual("running", active[0]["last_state"])
        self.assertEqual(active[0], server.session(active[0]["session_id"]))

        release.set()
        server.execute(request)
        idle = server.sessions(state="idle")
        self.assertEqual(1, len(idle))
        self.assertEqual(0, idle[0]["active_run_count"])
        self.assertEqual(1, idle[0]["completed_run_count"])
        self.assertEqual("completed", idle[0]["last_state"])

    def test_session_registry_filters_by_route_conversation_and_state(self):
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

        phone_one = server.sessions(client_route_id="phone-1")
        conversation_two = server.sessions(conversation_id="conversation-2")

        self.assertEqual(2, len(phone_one))
        self.assertEqual(
            {"conversation-1", "conversation-2"},
            {item["conversation_id"] for item in phone_one},
        )
        self.assertEqual(1, len(conversation_two))
        self.assertEqual("phone-1", conversation_two[0]["client_route_id"])
        with self.assertRaises(DesktopAgentRuntimeError):
            server.sessions(state="missing")

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

    def test_background_run_does_not_block_foreground_chat(self):
        background_started = threading.Event()
        release_background = threading.Event()
        foreground_completed = threading.Event()

        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            if request.priority == AgentRunPriority.BACKGROUND:
                background_started.set()
                release_background.wait(timeout=3)
                return "background-done"
            foreground_completed.set()
            return "foreground-done"

        server = self.server(execute, max_workers=1)
        background = self.request(
            "scheduled maintenance",
            run_id="background-run",
            priority=AgentRunPriority.BACKGROUND,
        )
        foreground = self.request(
            "hello",
            run_id="foreground-run",
            priority=AgentRunPriority.FOREGROUND,
        )

        server.submit(background)
        self.assertTrue(background_started.wait(timeout=1))
        result = server.execute(foreground, timeout_seconds=1)

        self.assertTrue(foreground_completed.is_set())
        self.assertEqual("foreground-done", result.reply)
        self.assertEqual("running", server.status(background.run_id)["state"])
        health = server.health()
        self.assertEqual(1, health["capacity"]["background_active_runs"])
        self.assertEqual(0, health["capacity"]["foreground_active_runs"])

        release_background.set()
        self.assertEqual("completed", server.execute(background).state)

    def test_background_runs_remain_serialized(self):
        first_started = threading.Event()
        second_started = threading.Event()
        release_first = threading.Event()

        def execute(_agent_id, request):
            if request.run_id == "background-one":
                first_started.set()
                release_first.wait(timeout=3)
            else:
                second_started.set()
            return request.prompt

        server = self.server(execute, max_workers=2)
        first = self.request(
            "one",
            run_id="background-one",
            priority=AgentRunPriority.BACKGROUND,
        )
        second = self.request(
            "two",
            run_id="background-two",
            priority=AgentRunPriority.BACKGROUND,
        )

        server.submit(first)
        self.assertTrue(first_started.wait(timeout=1))
        server.submit(second)
        time.sleep(0.05)
        self.assertFalse(second_started.is_set())

        release_first.set()
        self.assertEqual("completed", server.execute(first).state)
        self.assertEqual("completed", server.execute(second).state)
        self.assertTrue(second_started.is_set())

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

    def test_bounded_global_queue_rejects_excess_and_recovers_capacity(self):
        started = threading.Event()
        release = threading.Event()

        def execute(agent_id, request):
            self.calls.append((agent_id, request.prompt))
            if request.run_id == "run-1":
                started.set()
                release.wait(timeout=2)
            return request.prompt

        server = self.server(
            execute,
            max_workers=1,
            max_queued_runs=1,
        )
        first = self.request("first", run_id="run-1")
        second = self.request("second", run_id="run-2")
        server.submit(first)
        self.assertTrue(started.wait(timeout=1))
        server.submit(second)

        with self.assertRaises(DesktopAgentCapacityExhausted):
            server.submit(self.request("excess", run_id="run-3"))
        capacity = server.health()["capacity"]
        self.assertEqual(1, capacity["active_runs"])
        self.assertEqual(1, capacity["queued_runs"])
        self.assertEqual(1, capacity["rejected_runs"])
        self.assertEqual(
            [{"agent_id": "codex", "active_runs": 1, "queued_runs": 1}],
            capacity["by_agent"],
        )

        release.set()
        server.execute(first)
        server.execute(second)
        retry = server.execute(self.request("retry", run_id="run-4"))

        self.assertEqual("completed", retry.state)
        self.assertEqual(0, server.health()["capacity"]["active_runs"])
        self.assertEqual(0, server.health()["capacity"]["queued_runs"])

    def test_cancelling_queued_run_releases_queue_slot(self):
        started = threading.Event()
        release = threading.Event()

        def execute(agent_id, request):
            if request.run_id == "run-1":
                started.set()
                release.wait(timeout=2)
            return request.prompt

        server = self.server(
            execute,
            max_workers=1,
            max_queued_runs=1,
        )
        first = self.request("first", run_id="run-1")
        second = self.request("second", run_id="run-2")
        server.submit(first)
        self.assertTrue(started.wait(timeout=1))
        server.submit(second)
        server.cancel(second.run_id)
        third = self.request("third", run_id="run-3")
        server.submit(third)

        self.assertEqual(1, server.health()["capacity"]["queued_runs"])
        release.set()
        server.execute(first)
        self.assertEqual("completed", server.execute(third).state)

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
        sessions = recovered.sessions()
        self.assertEqual({"idle"}, {item["state"] for item in sessions})
        self.assertEqual(2, sum(item["failed_run_count"] for item in sessions))

    def test_health_exposes_protocol_capacity_and_durable_counts(self):
        server = self.server(max_workers=3)
        server.execute(self.request("hello", run_id="run-1"))

        health = server.health()

        self.assertEqual(RUNTIME_PROTOCOL, health["protocol"])
        self.assertEqual("ready", health["status"])
        self.assertEqual(3, health["max_concurrency"])
        self.assertEqual(1, health["runs"])
        self.assertEqual(1, health["sessions"])
        self.assertEqual(0, health["active_sessions"])
        self.assertIn("durable_run_registry", health["features"])

    def test_failed_agent_is_isolated_without_blocking_other_agents(self):
        calls: list[str] = []

        def execute(agent_id, request):
            calls.append(agent_id)
            if agent_id == "codex":
                raise RuntimeError("codex worker crashed")
            return f"{agent_id}:ok"

        fault_domains = AgentFaultDomainRegistry(
            failure_threshold=1,
            cooldown_seconds=60,
        )
        server = self.server(
            execute,
            descriptors=(descriptor("codex"), descriptor("hermes")),
            fault_domains=fault_domains,
        )

        with self.assertRaises(AgentAdapterExecutionError):
            server.execute(self.request("fail", run_id="codex-1"))
        with self.assertRaises(DesktopAgentFaultIsolated):
            server.execute(self.request("retry", run_id="codex-2"))
        hermes = server.execute(self.request(
            "continue",
            run_id="hermes-1",
            agent_id="hermes",
        ))

        self.assertEqual("completed", hermes.state)
        self.assertEqual(["codex", "hermes"], calls)
        domains = {
            item["agent_id"]: item
            for item in server.health()["fault_domains"]
        }
        self.assertEqual("isolated", domains["codex"]["status"])
        self.assertEqual(1, domains["codex"]["failed_runs"])
        self.assertEqual("healthy", domains["hermes"]["status"])
        self.assertEqual(1, domains["hermes"]["successful_runs"])

    def test_isolated_agent_recovers_with_single_probe_after_cooldown(self):
        clock = [100.0]
        domains = AgentFaultDomainRegistry(
            failure_threshold=1,
            cooldown_seconds=10,
            now=lambda: clock[0],
        )

        domains.acquire("codex")
        domains.fail("codex", "failed")
        with self.assertRaises(DesktopAgentFaultIsolated):
            domains.acquire("codex")

        clock[0] = 111.0
        domains.acquire("codex")
        with self.assertRaises(DesktopAgentFaultIsolated):
            domains.acquire("codex")
        self.assertEqual("recovering", domains.snapshots()[0]["status"])
        domains.succeed("codex")

        snapshot = domains.snapshots()[0]
        self.assertEqual("healthy", snapshot["status"])
        self.assertEqual(0, snapshot["consecutive_failures"])


if __name__ == "__main__":
    unittest.main()
