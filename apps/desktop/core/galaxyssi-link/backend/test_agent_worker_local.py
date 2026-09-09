"""Local worker lease fences, crash ambiguity and bounded owned execution."""
import base64
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import unittest
from unittest.mock import patch

from agent_worker_execution import WorkerProcessExecutor
from agent_worker_execution_child import policy_for_job, prepare_images
from agent_worker_local import WorkerExecutionFenced, WorkerExecutionJournal, WorkerLeaseGuard
from agent_worker_protocol import AgentWorkerProtocol
from agent_worker_registry import _binding
from agent_worker_rpc import WorkerRpcResult
from agent_work_pool import AgentQueueFull
from test_agent_worker_queue import record
from test_agent_worker_registry import WorkerFixture


def observation(*, sent=100.0, received=101.0, server=100_000, expiry=130_000, initial=True, **changes):
    grant = dict(key=["app", "chat", "turn", "task", 1], epoch=1, token="private-token", expires_at_ms=expiry)
    grant.update(changes)
    value = dict(ok=True, server_time_ms=server)
    value.update({"job": {"lease": grant}} if initial else {"lease": grant})
    return WorkerRpcResult(value, sent, received)


def png_attachment():
    from PIL import Image, ImageDraw, ImageFont
    picture = Image.new("RGB", (400, 120), "white")
    font = ImageFont.truetype("arial.ttf", 44) if os.name == "nt" else ImageFont.load_default()
    ImageDraw.Draw(picture).text((40, 30), "2 + 2 = 4", font=font, fill="black")
    stream = io.BytesIO()
    picture.save(stream, format="PNG")
    data = stream.getvalue()
    return dict(name="untrusted/../../image.png", mime_type="image/png", size=len(data),
                sha256=hashlib.sha256(data).hexdigest(), data_b64=base64.b64encode(data).decode())


class WorkerGuardTest(unittest.TestCase):
    def setUp(self):
        self.now = 102.0
        self.guard = WorkerLeaseGuard(observation(), clock=lambda: self.now)

    def test_network_time_and_safety_margin_consume_lease_budget(self):
        self.assertAlmostEqual(27.5, self.guard.require_live())
        self.now = 129.5
        with self.assertRaisesRegex(WorkerExecutionFenced, "expired"):
            self.guard.require_live()
        self.now = 103
        with self.assertRaises(WorkerExecutionFenced):
            self.guard.require_live()

    def test_renewal_extends_only_same_identity_while_old_guard_is_alive(self):
        self.now = 110
        self.guard.renew(observation(sent=109, received=110, server=109_000, expiry=139_000, initial=False))
        self.assertAlmostEqual(28.5, self.guard.require_live())
        grant = self.guard.capability()
        grant["token"] = "changed"
        self.assertEqual("private-token", self.guard.capability()["token"])
        self.now = 139
        with self.assertRaises(WorkerExecutionFenced):
            self.guard.renew(observation(sent=138, received=139, server=138_000, expiry=168_000, initial=False))

    def test_expired_delayed_or_nonfinite_initial_grant_never_starts(self):
        for result in (observation(received=131), observation(expiry=99_000),
                       observation(sent=float("nan")), observation(received=99),
                       observation(server=0), observation(epoch=True), observation(key=["missing"])):
            with self.subTest(result=result), self.assertRaises(WorkerExecutionFenced):
                WorkerLeaseGuard(result, clock=lambda: 132)

    def test_foreign_generation_epoch_token_and_reordered_renewal_are_rejected(self):
        self.now = 110
        alterations = [dict(epoch=2), dict(token="other")]
        for index in range(5):
            key = ["app", "chat", "turn", "task", 1]
            key[index] = 2 if index == 4 else "other"
            alterations.append(dict(key=key))
        for changed in alterations:
            with self.subTest(changed=changed), self.assertRaises(WorkerExecutionFenced):
                self.guard.renew(observation(sent=109, received=110, server=109_000, expiry=139_000, initial=False, **changed))
        with self.assertRaises(WorkerExecutionFenced):
            self.guard.renew(observation(sent=100, received=101, initial=False))
        self.assertGreater(self.guard.require_live(), 0)

    def test_clock_regression_or_cancellation_cannot_be_reversed_by_renewal(self):
        self.now = 110
        with self.assertRaisesRegex(WorkerExecutionFenced, "server_clock"):
            self.guard.renew(observation(sent=109, received=110, server=99_000, expiry=139_000, initial=False))
        with self.assertRaises(WorkerExecutionFenced):
            self.guard.require_live()
        self.guard = WorkerLeaseGuard(observation(), clock=lambda: self.now)
        self.guard.invalidate()
        with self.assertRaises(WorkerExecutionFenced):
            self.guard.renew(observation(sent=109, received=110, server=109_000, expiry=139_000, initial=False))

    def test_unchanged_server_observation_does_not_reset_budget(self):
        self.now = 110
        self.guard.renew(observation(sent=109, received=110, server=100_000, expiry=130_000, initial=False))
        self.assertAlmostEqual(19.5, self.guard.require_live())


class LocalWorkerFixture(WorkerFixture):
    def setUp(self):
        super().setUp()
        self.enroll()
        self.connect()
        self.heartbeat()
        self.protocol = AgentWorkerProtocol(self.registry)
        self.journal = WorkerExecutionJournal(self.ledger)
        self.binding = _binding(self.peer)
        self.owner = "boot-a"
        self.session = dict(incarnation=self.owner, session_epoch=1)
        self.poll_sequence = 0

    def grant(self, task="task-1", **changes):
        self.protocol.queue.enqueue(record(task, **changes), provider="codex", allowed_workers=["worker-a"])
        self.poll_sequence += 1
        start = time.monotonic()
        value = self.protocol.poll(self.peer, self.source, dict(self.session, sequence=self.poll_sequence,
            request_id=f"poll-{self.poll_sequence}"))
        result = WorkerRpcResult(dict(value, ok=True), start, time.monotonic())
        return result.payload["job"], WorkerLeaseGuard(result)


class WorkerJournalTest(LocalWorkerFixture):
    def test_replayed_grant_after_restart_never_dispatches_again(self):
        job, _ = self.grant()
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.assertTrue(self.journal.begin(identifier, self.owner))
        restored = WorkerExecutionJournal(self.ledger)
        self.assertEqual(identifier, restored.admit(self.binding, "new-process", job))
        self.assertFalse(restored.begin(identifier, "new-process"))
        self.assertFalse(restored.begin(identifier, self.owner))
        self.assertEqual("dispatched", restored.get(identifier)["state"])

    def test_scope_epoch_and_coordinator_are_all_part_of_local_identity(self):
        job, _ = self.grant()
        original = self.journal.admit(self.binding, self.owner, job)
        identifiers = {original}
        for index in range(5):
            changed = deepcopy(job)
            changed["lease"]["key"][index] = 2 if index == 4 else "other"
            identifiers.add(self.journal.admit(self.binding, self.owner, changed))
        changed = deepcopy(job)
        changed["lease"]["epoch"] += 1
        changed["lease"]["key"][4] = 3
        identifiers.add(self.journal.admit(self.binding, self.owner, changed))
        identifiers.add(self.journal.admit("f" * 64, self.owner, job))
        self.assertEqual(8, len(identifiers))
        changed = deepcopy(job)
        changed["lease"]["expires_at_ms"] += 1000
        self.assertEqual(original, self.journal.admit(self.binding, self.owner, changed))

    def test_changed_request_or_capability_cannot_reuse_dedup_identity(self):
        job, _ = self.grant()
        self.journal.admit(self.binding, self.owner, job)
        for field, value in (("prompt", "changed"), ("provider", "deepseek"), ("options", {"different": True})):
            with self.subTest(field=field), self.assertRaises(WorkerExecutionFenced):
                self.journal.admit(self.binding, self.owner, dict(job, **{field: value}))
        changed = deepcopy(job)
        changed["lease"]["token"] = "other"
        with self.assertRaises(WorkerExecutionFenced):
            self.journal.admit(self.binding, self.owner, changed)

    def test_concurrent_begin_allows_only_one_external_dispatch(self):
        job, _ = self.grant()
        identifier = self.journal.admit(self.binding, self.owner, job)
        def begin(_):
            return WorkerExecutionJournal(self.ledger).begin(identifier, self.owner)
        with ThreadPoolExecutor(10) as pool:
            self.assertEqual(1, sum(pool.map(begin, range(10))))

    def test_new_generation_does_not_overlap_running_or_uncertain_old_execution(self):
        job, _ = self.grant()
        old = self.journal.admit(self.binding, self.owner, job)
        self.assertTrue(self.journal.begin(old, self.owner))
        new_job = deepcopy(job)
        new_job["lease"]["key"][4] = 2
        new_job["lease"]["epoch"] = 2
        new = self.journal.admit(self.binding, self.owner, new_job)
        self.assertFalse(self.journal.begin(new, self.owner))
        self.journal.mark_uncertain(old, self.owner)
        self.assertFalse(self.journal.begin(new, self.owner))

    def test_new_admission_fences_old_queued_generation_and_stale_new_ids(self):
        job, _ = self.grant()
        old = self.journal.admit(self.binding, self.owner, job)
        new_job = deepcopy(job)
        new_job["lease"]["key"][4] = 2
        new_job["lease"]["epoch"] = 2
        new = self.journal.admit(self.binding, self.owner, new_job)
        self.assertFalse(self.journal.begin(old, self.owner))
        self.assertTrue(self.journal.begin(new, self.owner))
        stale = deepcopy(job)
        stale["lease"]["epoch"] = 3
        with self.assertRaisesRegex(WorkerExecutionFenced, "generation_stale"):
            self.journal.admit(self.binding, self.owner, stale)

    def test_report_is_durable_before_receipt_and_exact_retry_does_not_change_it(self):
        job, _ = self.grant()
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.journal.begin(identifier, self.owner)
        report = dict(status="completed", text="done", error="", current_step="")
        self.assertTrue(self.journal.stage_report(identifier, self.owner, report))
        restored = WorkerExecutionJournal(self.ledger)
        self.assertEqual(report, restored.get(identifier)["report"])
        self.assertFalse(restored.stage_report(identifier, self.owner, report))
        with self.assertRaises(WorkerExecutionFenced):
            restored.stage_report(identifier, self.owner, dict(report, text="changed"))
        receipt = dict(sequence=1, status_sequence=2, replayed=False)
        restored.confirm(identifier, self.owner, receipt)
        restored.confirm(identifier, self.owner, dict(receipt, replayed=True))
        with self.assertRaises(WorkerExecutionFenced):
            restored.confirm(identifier, self.owner, dict(receipt, status_sequence=3))
        self.assertFalse(restored.begin(identifier, self.owner))

    def test_journal_bound_keeps_tombstones_and_uncertain_execution_cannot_restart(self):
        journal = WorkerExecutionJournal(self.ledger, max_records=1)
        job, _ = self.grant()
        identifier = journal.admit(self.binding, self.owner, job)
        journal.mark_uncertain(identifier, self.owner)
        self.assertFalse(journal.begin(identifier, self.owner))
        with self.assertRaises(WorkerExecutionFenced):
            journal.admit("f" * 64, self.owner, job)
        self.assertEqual(identifier, journal.admit(self.binding, self.owner, job))


class WorkerImageTest(WorkerFixture):
    def test_remote_execution_options_do_not_relax_user_policy(self):
        job = dict(prompt="Review this design", options={"execution_mode": "plan_only", "agent_invocation": {"reasoning_effort": "high"}})
        policy = policy_for_job(job)
        self.assertEqual("plan_only", policy.execution_mode.value)
        self.assertEqual("high", policy.reasoning_effort.value)
        for budget in ({"allow_cloud": False}, {"allow_paid_providers": False}, {"network_policy": "offline_only"}):
            with self.subTest(budget=budget), self.assertRaisesRegex(ValueError, "budget_denied"):
                policy_for_job(dict(job, options={"task_budget": budget}))
        with self.assertRaisesRegex(ValueError, "artifact_return"):
            policy_for_job(dict(prompt="Generate a video and return the MP4 file", options={}))

    def test_image_bytes_and_pixels_are_preserved_and_remote_paths_are_not_used(self):
        attachment = png_attachment()
        root = self.ledger.path.parent
        paths = prepare_images({"attachments": [attachment]}, root)
        self.assertEqual(root / "input-0.png", Path(paths[0]))
        self.assertEqual(base64.b64decode(attachment["data_b64"]), Path(paths[0]).read_bytes())
        self.assertEqual(attachment["sha256"], hashlib.sha256(Path(paths[0]).read_bytes()).hexdigest())

    def test_missing_corrupted_non_image_or_mismatched_input_is_not_silently_dropped(self):
        attachment = png_attachment()
        for change in ({"data_b64": ""}, {"data_b64": "not-base64"}, {"sha256": "wrong"},
                       {"mime_type": "application/pdf"}, {"data_b64": None}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                prepare_images({"attachments": [attachment | change]}, self.ledger.path.parent)


@unittest.skipUnless(os.name == "nt", "Owned Windows process tree integration")
class WorkerProcessTest(LocalWorkerFixture):
    def executor(self, **options):
        executor = WorkerProcessExecutor(self.journal, self.ledger.path.parent / "worker", **options)
        self.addCleanup(executor.close)
        return executor

    def test_node_waiting_queue_and_job_bytes_are_bounded(self):
        jobs = [self.grant(f"task-{index}") for index in range(3)]
        executor = self.executor(max_workers=1)
        entered, release = threading.Event(), threading.Event()
        def blocked(*_):
            entered.set()
            release.wait(5)
            return "fixture"
        with patch.object(executor, "_execute", side_effect=blocked):
            try:
                first = executor.submit(self.binding, self.owner, *jobs[0])
                self.assertTrue(entered.wait(2))
                second = executor.submit(self.binding, self.owner, *jobs[1])
                self.assertEqual(1, executor.snapshot()["pending"])
                with self.assertRaises(AgentQueueFull):
                    executor.submit(self.binding, self.owner, *jobs[2])
            finally:
                release.set()
            first.result(timeout=5)
            second.result(timeout=5)
        self.assertTrue(executor.close())
        self.assertEqual(0, executor.snapshot()["request_bytes"])
        executor = self.executor()
        executor._max_request_bytes = 1
        with self.assertRaises(AgentQueueFull):
            executor.submit(self.binding, self.owner, *jobs[2])
        self.assertEqual(0, executor.snapshot()["workers"])

    def test_actual_owned_child_reports_once_and_duplicate_submission_reuses_result(self):
        import owned_process
        original = owned_process.popen
        launches = []
        report = dict(status="completed", text="fixture", error="", current_step="")
        def popen(argv, **kwargs):
            launches.append(argv)
            return original([sys.executable, "-c", f"print({json.dumps(report)!r})"], **kwargs)
        job, guard = self.grant()
        executor = self.executor(max_workers=2)
        with patch.object(owned_process, "popen", side_effect=popen):
            first = executor.submit(self.binding, self.owner, job, guard)
            duplicate = executor.submit(self.binding, self.owner, job, guard)
            self.assertIs(first, duplicate)
            self.assertEqual(report, first.result(timeout=10))
            self.assertEqual(report, executor.submit(self.binding, self.owner, job, guard).result(timeout=5))
        self.assertEqual(1, len(launches))
        self.assertTrue(executor.close())

    def test_lease_cancellation_closes_only_the_owned_tree_and_marks_uncertain(self):
        import owned_process
        from windows_process_job import active_processes
        original = owned_process.popen
        launched = threading.Event()
        processes = []
        script = "import subprocess,sys,time; subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); time.sleep(60)"
        def popen(argv, **kwargs):
            process = original([sys.executable, "-c", script], **kwargs)
            processes.append(process)
            launched.set()
            return process
        job, guard = self.grant()
        executor = self.executor(max_workers=1)
        with patch.object(owned_process, "popen", side_effect=popen):
            future = executor.submit(self.binding, self.owner, job, guard)
            self.assertTrue(launched.wait(5))
            deadline = time.monotonic() + 5
            while active_processes(processes[0].job.name) < 3 and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertGreaterEqual(active_processes(processes[0].job.name), 3)
            guard.invalidate()
            with self.assertRaises(WorkerExecutionFenced):
                future.result(timeout=10)
        self.assertEqual(0, active_processes(processes[0].job.name))
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.assertEqual("uncertain", self.journal.get(identifier)["state"])
        self.assertFalse(self.journal.begin(identifier, self.owner))

    def test_nonzero_child_exit_cannot_be_claimed_as_success(self):
        import owned_process
        original = owned_process.popen
        report = dict(status="completed", text="must not be accepted", error="", current_step="")
        def popen(argv, **kwargs):
            return original([sys.executable, "-c", f"import sys; print({json.dumps(report)!r}); sys.exit(7)"], **kwargs)
        job, guard = self.grant()
        executor = self.executor()
        with patch.object(owned_process, "popen", side_effect=popen), self.assertRaisesRegex(WorkerExecutionFenced, "exit_failed"):
            executor.submit(self.binding, self.owner, job, guard).result(timeout=10)
        identifier = self.journal.admit(self.binding, self.owner, job)
        self.assertEqual("uncertain", self.journal.get(identifier)["state"])


@unittest.skipUnless(os.name == "nt" and os.environ.get("GALAXYSSI_LIVE_WORKER_CODEX") == "1",
                     "Explicit real model opt-in required")
class WorkerRealCodexTest(LocalWorkerFixture):
    def test_real_text_and_native_image_with_local_coordinator_renewals(self):
        marker = str(time.time_ns())
        attachment = png_attachment()
        jobs = [self.grant("text", prompt=f"Reply with exactly WORKER_TEXT_{marker}."),
                self.grant("image", prompt=f"Read the attached test image with native vision. Reply with WORKER_IMAGE_{marker} and the equation shown. Do not use tools or search.",
                    attachments=[{"id": "fixture-image"}], request_snapshot={"version": 1, "options": {"attachments": [attachment]}})]
        executor = WorkerProcessExecutor(self.journal, self.ledger.path.parent / "worker", max_workers=2)
        self.addCleanup(executor.close)
        stopped = threading.Event()
        errors = []
        def renew():
            sequence = 1
            while not stopped.wait(3):
                try:
                    sequence += 1
                    self.protocol.registry.heartbeat(self.peer, self.source, dict(self.session, sequence=sequence,
                        available_slots=2, request_id=f"heartbeat-{sequence}"))
                    for job, guard in jobs:
                        start = time.monotonic()
                        value = self.protocol.renew(self.peer, self.source, dict(self.session, lease=guard.capability()))
                        guard.renew(WorkerRpcResult(dict(value, ok=True), start, time.monotonic()))
                except Exception as error:
                    errors.append(type(error).__name__)
                    return
        thread = threading.Thread(target=renew, daemon=True)
        thread.start()
        try:
            futures = [executor.submit(self.binding, self.owner, job, guard) for job, guard in jobs]
            peak_active = 0
            deadline = time.monotonic() + 120
            while any(not future.done() for future in futures):
                peak_active = max(peak_active, executor.snapshot()["active"])
                self.assertLess(time.monotonic(), deadline, "Real worker execution timed out")
                time.sleep(0.05)
            reports = [future.result() for future in futures]
        finally:
            stopped.set()
            thread.join(timeout=10)
            executor.close()
        self.assertEqual([], errors)
        self.assertEqual(2, peak_active)
        self.assertEqual(["completed", "completed"], [report["status"] for report in reports], reports)
        self.assertIn(f"WORKER_TEXT_{marker}", reports[0]["text"])
        self.assertIn(f"WORKER_IMAGE_{marker}", reports[1]["text"])
        self.assertRegex(reports[1]["text"], r"2\s*[+\uff0b]\s*2\s*[=\uff1d]\s*4")
        for (job, guard), report in zip(jobs, reports):
            # No model replay is needed to retry this durable terminal report.
            receipt = self.protocol.report(self.peer, self.source, dict(self.session, lease=job["lease"], sequence=1, report=report))
            identifier = self.journal.admit(self.binding, self.owner, job)
            self.journal.confirm(identifier, self.owner, receipt)
            self.assertEqual("confirmed", self.journal.get(identifier)["state"])
            task = self.protocol.queue.tasks.get(job["lease"]["key"][3])
            self.assertEqual(job["lease"]["key"], [task["client_route_id"], task["client_conversation_id"],
                task["client_turn_id"], task["task_id"], task["execution_generation"]])
            self.assertEqual("message-" + task["task_id"], task["source_message_id"])
