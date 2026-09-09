"""Controller retries and scope isolation over the real worker RPC router."""
from concurrent.futures import Future
from copy import deepcopy
import os
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from agent_worker_client_store import WorkerClientStore
from agent_worker_controller import WorkerController
from agent_worker_execution import WorkerProcessExecutor
from agent_worker_local import WorkerExecutionFenced, WorkerExecutionJournal
from agent_worker_mqtt import route_worker_payload
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_registry import _binding
from agent_worker_rpc import AgentWorkerRpcClient
from test_agent_worker_local import png_attachment
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture


class FixtureExecutor:
    def __init__(self, journal, *, hold=False, fail=False):
        self.journal, self.hold, self.fail = journal, hold, fail
        self.calls, self.guards, self.futures = [], [], []

    def submit(self, binding, owner, job, guard):
        identifier = self.journal.admit(binding, owner, job)
        if not self.journal.begin(identifier, owner):
            raise AssertionError("Fixture dispatch duplicated")
        future = Future()
        self.calls.append(deepcopy(job))
        self.guards.append(guard)
        self.futures.append(future)
        if not self.hold:
            report = dict(status="failed" if self.fail else "completed", text="" if self.fail else job["prompt"],
                          error="fixture-failed" if self.fail else "", current_step="")
            self.journal.stage_report(identifier, owner, report)
            future.set_result(report)
        return future

    def close(self, **_):
        for guard, future in zip(self.guards, self.futures):
            guard.invalidate()
            future.cancel()
        return True


class ControllerFixture(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.protocol = AgentWorkerProtocol(self.registry)
        self.journal = WorkerExecutionJournal(self.ledger)
        self.executor = FixtureExecutor(self.journal)
        self.requests, self.losses = [], {}
        self._wire_lock = threading.Lock()
        self.rpc = AgentWorkerRpcClient(lambda route: self.peer, self.send)
        self.addCleanup(self.rpc.close)
        self.server = SimpleNamespace(get_client=lambda route: self.peer,
            agent_task_manager=SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger)),
            _worker_enrollment_registry=self.registry, _worker_execution_protocol=self.protocol,
            _publish_phone_payload=self.receive, _ensure_outbound_retry_thread=Mock())

    def send(self, paired, request):
        with self.ledger.transaction(write=False) as connection:
            saved = connection.execute("SELECT request_id FROM agent_worker_client_intents WHERE request_id=?",
                                       (request["request_id"],)).fetchone()
        self.assertIsNotNone(saved, "Request must be durable before transport send")
        with self._wire_lock:
            self.requests.append(deepcopy(request))
        return route_worker_payload(self.server, None, {}, request, client_route_id="route-a", source_id=self.source)

    def receive(self, _mqtt, _wire, value):
        with self._wire_lock:
            request = next(row for row in reversed(self.requests) if row["request_id"] == value["request_id"])
            operation = request["type"].removeprefix("agent_worker_")
            if self.losses.get(operation, 0):
                self.losses[operation] -= 1
                return True
        return self.rpc.receive(self.peer, self.source, value)

    def start(self, **options):
        options.setdefault("rpc_timeout", 0.1)
        controller = WorkerController(self.rpc, lambda route: self.peer, "route-a", self.ledger,
            self.executor, **options)
        self.addCleanup(lambda: self.assertTrue(controller.stop()))
        controller.start()
        return controller

    def enqueue(self, task="task-1", **changes):
        self.protocol.queue.enqueue(record(task, **changes), provider="codex", allowed_workers=["worker-a"])

    def until(self, predicate, *, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.02)
        self.fail("Controller condition not reached before test deadline")


class WorkerControllerTest(ControllerFixture):
    def test_shutdown_consumes_response_completed_between_tick_and_wait_check(self):
        from agent_worker_rpc import WorkerRpcResult
        controller = WorkerController(self.rpc, lambda route: self.peer, "route-a", self.ledger, self.executor)
        self.addCleanup(controller.stop)
        controller._queue("poll", "poll", dict(sequence=1))
        future = controller._ops["poll"]["future"] = Future()
        original = controller.tick
        calls = []
        def finish_between_checks():
            calls.append(True)
            if len(calls) == 1:
                now = time.monotonic()
                future.set_result(WorkerRpcResult(dict(ok=True, job=None), now, now))
            else:
                original()
        controller._stop.set()
        with patch.object(controller, "tick", side_effect=finish_between_checks):
            controller._run()
        self.assertEqual(2, len(calls))
        self.assertEqual("closed", controller.store.read()["state"])
        self.assertEqual(0, controller.store.read()["pending"])

    def test_unverified_shutdown_retains_exclusive_ownership(self):
        from agent_worker_ownership import WorkerClientOwnership
        controller = WorkerController(self.rpc, lambda route: self.peer, "route-a", self.ledger, self.executor)
        self.addCleanup(controller.stop)
        with patch.object(self.executor, "close", return_value=False):
            self.assertFalse(controller.stop())
        self.assertEqual("recovery_required", controller.snapshot()["state"])
        with self.assertRaisesRegex(WorkerExecutionFenced, "owner_unavailable"):
            WorkerClientOwnership(self.ledger).acquire()
        self.assertTrue(controller.stop())
        self.assertEqual("recovery_required", WorkerClientStore(self.ledger).read()["state"])
        owner = WorkerClientOwnership(self.ledger).acquire()
        self.addCleanup(owner.release)

    def test_expired_completed_job_uses_read_only_receipt_without_model_replay(self):
        self.losses = {"report": 100}
        self.enqueue()
        controller = self.start(max_parallel=1)
        self.until(lambda: self.protocol.queue.tasks.get("task-1")["status"] == "completed")
        with controller._lock:
            self.executor.guards[0].invalidate()
            with self.ledger.transaction() as connection:
                connection.execute("UPDATE agent_worker_leases SET expires_at_ms=1")
        self.until(lambda: controller.snapshot()["completed_tasks"] == 1)
        self.assertEqual(1, len(self.executor.calls))
        self.assertEqual(0, controller.snapshot()["uncertain_tasks"])
        self.assertTrue(any(row["type"] == "agent_worker_receipt" for row in self.requests))
        self.assertTrue(controller.is_alive())

    def test_heartbeat_expired_poll_refreshes_heartbeat_instead_of_stopping(self):
        original = self.protocol.poll
        calls = []
        def expired_once(peer, source, payload):
            from agent_worker_registry import WorkerAccessError
            calls.append(payload["request_id"])
            if len(calls) == 1:
                raise WorkerAccessError("worker_heartbeat_expired")
            return original(peer, source, payload)
        self.enqueue()
        with patch.object(self.protocol, "poll", side_effect=expired_once):
            controller = self.start(max_parallel=1)
            self.until(lambda: controller.snapshot()["completed_tasks"] == 1)
        self.assertEqual(calls[0], calls[1])
        self.assertTrue(controller.is_alive())

    def test_heartbeat_rejection_after_lost_grant_does_not_release_poll_reservation(self):
        original = self.protocol.poll
        calls = []
        self.losses = {"poll": 1}
        def reject_retry_once(peer, source, payload):
            from agent_worker_registry import WorkerAccessError
            calls.append(payload["request_id"])
            if len(calls) == 2:
                raise WorkerAccessError("worker_heartbeat_expired")
            return original(peer, source, payload)
        self.enqueue()
        with patch.object(self.protocol, "poll", side_effect=reject_retry_once):
            controller = self.start(max_parallel=1)
            self.until(lambda: controller.snapshot()["completed_tasks"] == 1)
        poll_indexes = [index for index, row in enumerate(self.requests) if row["type"] == "agent_worker_poll"]
        heartbeat = next(row for row in self.requests[poll_indexes[1] + 1:] if row["type"] == "agent_worker_heartbeat")
        self.assertEqual(0, heartbeat["available_slots"])
        self.assertEqual(1, len(self.executor.calls))

    def test_two_apps_and_turns_keep_original_identity_through_controller(self):
        self.enqueue("one", app="app-a", prompt="first-marker")
        self.enqueue("two", app="app-b", prompt="second-marker")
        controller = self.start(max_parallel=2)
        self.until(lambda: controller.snapshot()["completed_tasks"] == 2)
        self.assertEqual(2, len(self.executor.calls))
        for task, app, marker in (("one", "app-a", "first-marker"), ("two", "app-b", "second-marker")):
            state = self.protocol.queue.tasks.get(task)
            self.assertEqual((app, "chat-a", "turn-" + task, "message-" + task, 1, marker),
                (state["client_route_id"], state["client_conversation_id"], state["client_turn_id"],
                 state["source_message_id"], state["execution_generation"], state["result"]))
        self.assertTrue(controller.stop())
        self.assertEqual("closed", controller.store.read()["state"])
        state = controller.snapshot()["state"]
        self.assertTrue(controller.stop())
        self.assertEqual(state, controller.snapshot()["state"])

    def test_lost_poll_and_report_responses_retry_same_ids_without_reexecuting_model(self):
        self.losses = {"poll": 1, "report": 1}
        self.enqueue()
        controller = self.start(max_parallel=1)
        self.until(lambda: controller.snapshot()["completed_tasks"] == 1)
        self.assertEqual(1, len(self.executor.calls))
        for operation in ("poll", "report"):
            calls = [row for row in self.requests if row["type"] == "agent_worker_" + operation]
            first_id = calls[0]["request_id"]
            retried = [row for row in calls if row["request_id"] == first_id]
            self.assertGreaterEqual(len(retried), 2)
            self.assertEqual(1, len({row["sequence"] for row in retried}))
            self.assertEqual(len(retried), len({row["attempt_id"] for row in retried}))

    def test_capacity_does_not_pull_more_grants_than_configured(self):
        self.executor.hold = True
        for index in range(5):
            self.enqueue(f"task-{index}")
        controller = self.start(max_parallel=2)
        self.until(lambda: len(self.executor.calls) == 2)
        time.sleep(0.4)
        self.assertEqual(2, len(self.executor.calls))
        self.assertEqual(3, sum(self.protocol.queue.tasks.get(f"task-{index}")["status"] == "queued" for index in range(5)))
        self.assertTrue(controller.stop())
        self.assertEqual("recovery_required", controller.store.read()["state"])

    def test_pair_revocation_stops_controller_and_fences_active_guard(self):
        self.executor.hold = True
        self.enqueue()
        controller = self.start(max_parallel=1)
        self.until(lambda: len(self.executor.guards) == 1)
        self.peer["revoked"] = True
        self.until(lambda: not controller.is_alive())
        with self.assertRaises(WorkerExecutionFenced):
            self.executor.guards[0].require_live()
        self.assertEqual("recovery_required", controller.snapshot()["state"])

    def test_failed_model_is_not_counted_as_success(self):
        self.executor.fail = True
        self.enqueue()
        controller = self.start()
        self.until(lambda: controller.snapshot()["failed_tasks"] == 1)
        self.assertEqual(0, controller.snapshot()["completed_tasks"])
        self.assertEqual("failed", self.protocol.queue.tasks.get("task-1")["status"])

    def test_uncertain_job_does_not_stop_unrelated_app_work(self):
        original = self.executor.submit
        def submit(binding, owner, job, guard):
            if job["lease"]["key"][3] == "bad":
                raise RuntimeError("fixture provider cannot start")
            return original(binding, owner, job, guard)
        self.executor.submit = submit
        self.enqueue("bad", app="bad-app")
        self.enqueue("good", app="good-app")
        controller = self.start(max_parallel=2)
        self.until(lambda: controller.snapshot()["completed_tasks"] == 1)
        self.assertEqual(1, controller.snapshot()["uncertain_tasks"])
        self.assertEqual("completed", self.protocol.queue.tasks.get("good")["status"])
        self.assertTrue(controller.is_alive())

    def test_poll_response_storage_failure_prevents_dispatch_and_retains_recovery_marker(self):
        self.enqueue()
        original = WorkerClientStore.received
        def received(store, owner, slot, payload):
            if slot == "poll" and payload.get("job"):
                raise RuntimeError("fixture disk failure")
            return original(store, owner, slot, payload)
        with patch.object(WorkerClientStore, "received", received):
            controller = self.start()
            self.until(lambda: not controller.is_alive())
        self.assertEqual([], self.executor.calls)
        self.assertEqual("recovery_required", controller.store.read()["state"])
        with self.assertRaisesRegex(WorkerExecutionFenced, "recovery_required"):
            WorkerController(self.rpc, lambda route: self.peer, "route-a", self.ledger, self.executor)

    def test_disabled_or_stopped_controller_does_not_auto_run_from_responses(self):
        controller = WorkerController(self.rpc, lambda route: self.peer, "route-a", self.ledger, self.executor)
        self.assertEqual([], self.requests)
        self.assertTrue(controller.stop())
        self.assertEqual("closed", controller.store.read()["state"])
        self.assertFalse(controller.is_alive())


class WorkerClientStoreTest(WorkerFixture):
    def test_pending_intent_survives_reload_and_blocks_blind_restart(self):
        store = WorkerClientStore(self.ledger)
        store.open("owner", "route", _binding(self.peer), {"phase": "running"})
        request_id = store.intent("owner", "poll", "poll", {"sequence": 1})
        restored = WorkerClientStore(self.ledger)
        self.assertEqual(request_id, restored.intent("owner", "poll", "poll", {"sequence": 1}))
        with self.assertRaises(WorkerExecutionFenced):
            restored.intent("owner", "poll", "poll", {"sequence": 2})
        with self.assertRaises(WorkerExecutionFenced):
            restored.open("new-owner", "route", _binding(self.peer), {})
        restored.received("owner", "poll", {"ok": True, "job": None})
        restored.consume("owner", "poll", {"poll_sequence": 2})
        self.assertEqual(0, restored.read()["pending"])
        restored.close("owner", clean=True, checkpoint={"poll_sequence": 2})
        restored.open("new-owner", "route", _binding(self.peer), {})
        with self.assertRaises(WorkerExecutionFenced):
            store.intent("owner", "late", "status", {})

    def test_intents_and_response_storage_are_bounded(self):
        store = WorkerClientStore(self.ledger)
        store.open("owner", "route", _binding(self.peer), {})
        for index in range(32):
            store.intent("owner", str(index), "renew", {})
        with self.assertRaisesRegex(WorkerExecutionFenced, "full"):
            store.intent("owner", "extra", "renew", {})
        for index in range(4):
            store.received("owner", str(index), {"data": "x" * 500_000})
        with self.assertRaisesRegex(WorkerExecutionFenced, "budget_full"):
            store.received("owner", "4", {"data": "x" * 500_000})


class WorkerClientApiTest(WorkerFixture):
    def test_activation_borrows_the_desktop_model_pool(self):
        from types import SimpleNamespace
        import agent_worker_client_api as api
        pool = object()
        bridge = SimpleNamespace(get_client=lambda route: self.peer,
            agent_task_manager=SimpleNamespace(_run_events=SimpleNamespace(ledger=self.ledger), model_work_pool=pool))
        with patch.object(api, "worker_rpc_client"), patch.object(api, "WorkerProcessExecutor") as executor, \
                patch.object(api, "WorkerController") as controller:
            api.activate_worker(bridge, "route-a", api.WorkerActivation())
            self.addCleanup(controller.call_args.kwargs["ownership"].release)
            self.assertIs(pool, executor.call_args.kwargs["work_pool"])
            controller.return_value.start.assert_called_once()
            self.assertIs(controller.return_value, bridge._worker_client_controller)

    def request(self, host="127.0.0.1", token="test-token"):
        from fastapi import Request
        return Request({"type": "http", "client": (host, 1234), "headers": [(b"x-galaxyssi-token", token.encode())]})

    def test_activation_requires_local_token_before_any_controller_is_created(self):
        import agent_worker_client_api as api
        import main
        from fastapi import HTTPException
        with patch.object(main, "_desktop_task_stream_token", return_value="test-token"), patch.object(api, "activate_worker") as activate:
            for host, token, code in (("198.51.100.2", "test-token", 403), ("127.0.0.1", "", 401)):
                with self.subTest(host=host), self.assertRaises(HTTPException) as error:
                    api.enable_worker_client("route-a", api.WorkerActivation(), self.request(host, token))
                self.assertEqual(code, error.exception.status_code)
            activate.assert_not_called()

    def test_operator_activation_is_explicit_and_cannot_request_unbounded_parallelism(self):
        import agent_worker_client_api as api
        import main
        from pydantic import ValidationError
        for options in ({"max_parallel": 11}, {"max_parallel": True}, {"sandbox": "danger-full-access"}, {"providers": ["arbitrary"]}):
            with self.subTest(options=options), self.assertRaises(ValidationError):
                api.WorkerActivation(**options)
        with patch.object(main, "_desktop_task_stream_token", return_value="test-token"), \
                patch.object(api, "activate_worker", return_value={"state": "connecting"}) as activate:
            self.assertEqual("connecting", api.enable_worker_client("route-a", api.WorkerActivation(), self.request())["state"])
            self.assertEqual("route-a", activate.call_args.args[1])


@unittest.skipUnless(os.name == "nt" and os.environ.get("GALAXYSSI_LIVE_WORKER_CODEX") == "1", "Real model opt-in required")
class WorkerControllerLiveTest(ControllerFixture):
    def test_real_text_image_receipts_recover_after_actual_lease_timeout(self):
        from agent_work_pool import AgentWorkPool
        pool = AgentWorkPool(max_workers=2, max_pending=10)
        self.addCleanup(pool.close)
        self.executor = WorkerProcessExecutor(self.journal, self.ledger.path.parent / "workers", max_workers=2, work_pool=pool)
        self.losses = {"report": 100}
        marker = str(time.time_ns())
        self.enqueue("text", prompt=f"Reply exactly TIMEOUT_TEXT_{marker}.")
        self.enqueue("image", prompt=f"Read the attached image with native vision. Reply TIMEOUT_IMAGE_{marker} and the equation. Do not use tools or search.",
            attachments=[{"id": "fixture"}], request_snapshot={"version": 1, "options": {"attachments": [png_attachment()]}})
        recovered_at = []
        def receive(mqttc, wire, response):
            request = next(row for row in reversed(self.requests) if row["request_id"] == response["request_id"])
            if request["type"] == "agent_worker_receipt":
                now = time.time_ns() // 1_000_000
                expiry = request["lease"]["expires_at_ms"]
                if now <= expiry + 1000:
                    return True
                recovered_at.append((now, expiry))
            return self.receive(mqttc, wire, response)
        self.server._publish_phone_payload = receive
        controller = self.start(max_parallel=2, rpc_timeout=2)
        self.until(lambda: controller.snapshot()["completed_tasks"] == 2, timeout=100)
        self.assertTrue(all(now > expiry + 1000 for now, expiry in recovered_at))
        self.assertGreaterEqual(len(recovered_at), 2)
        self.assertEqual(0, controller.snapshot()["uncertain_tasks"])
        text = self.protocol.queue.tasks.get("text")
        image = self.protocol.queue.tasks.get("image")
        self.assertIn("TIMEOUT_TEXT_" + marker, text["result"])
        self.assertIn("TIMEOUT_IMAGE_" + marker, image["result"])
        self.assertRegex(image["result"], r"2\s*[+\uff0b]\s*2\s*[=\uff1d]\s*4")
        with self.ledger.transaction(write=False) as connection:
            self.assertEqual([("confirmed", 2)], connection.execute(
                "SELECT state, count(*) FROM agent_worker_local_executions GROUP BY state").fetchall())

    def test_controller_completes_native_text_image_jobs_and_retries_lost_report_receipt(self):
        marker = str(time.time_ns())
        attachment = png_attachment()
        from agent_work_pool import AgentWorkPool
        pool = AgentWorkPool(max_workers=2, max_pending=10)
        self.addCleanup(pool.close)
        self.executor = WorkerProcessExecutor(self.journal, self.ledger.path.parent / "workers", max_workers=2, work_pool=pool)
        self.losses = {"report": 1}
        self.enqueue("text", prompt=f"Reply with exactly CONTROLLER_TEXT_{marker}.")
        self.enqueue("image", prompt=f"Read the attached image with native vision. Reply with CONTROLLER_IMAGE_{marker} and the equation shown. Do not use tools or search.",
            attachments=[{"id": "fixture"}], request_snapshot={"version": 1, "options": {"attachments": [attachment]}})
        controller = self.start(max_parallel=2, rpc_timeout=2)
        peak = 0
        deadline = time.monotonic() + 120
        while controller.snapshot()["completed_tasks"] < 2 and time.monotonic() < deadline:
            peak = max(peak, self.executor.snapshot()["active"])
            self.assertTrue(controller.is_alive(), controller.snapshot())
            time.sleep(0.05)
        self.assertEqual(2, controller.snapshot()["completed_tasks"], controller.snapshot())
        self.assertEqual(2, peak)
        text = self.protocol.queue.tasks.get("text")
        image = self.protocol.queue.tasks.get("image")
        self.assertIn("CONTROLLER_TEXT_" + marker, text["result"])
        self.assertIn("CONTROLLER_IMAGE_" + marker, image["result"])
        self.assertRegex(image["result"], r"2\s*[+\uff0b]\s*2\s*[=\uff1d]\s*4")
        for task in (text, image):
            self.assertEqual(("app-a", "chat-a", "turn-" + task["task_id"], "message-" + task["task_id"], 1),
                (task["client_route_id"], task["client_conversation_id"], task["client_turn_id"], task["source_message_id"], task["execution_generation"]))
        self.assertEqual(3, len([request for request in self.requests if request["type"] == "agent_worker_report"]))
        with self.ledger.transaction(write=False) as connection:
            self.assertEqual([(2,)], connection.execute("SELECT count(*) FROM agent_worker_local_executions WHERE state='confirmed'").fetchall())
