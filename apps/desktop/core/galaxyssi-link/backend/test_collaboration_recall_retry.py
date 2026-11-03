import hashlib
import json
import unittest
from contextlib import contextmanager
from unittest.mock import patch

from collaboration_recall_bridge import Pending, RESPONSE, RecallBroker
from test_collaboration_recall_bridge import task


class Clock:
    def __init__(self):
        self.now = 0.0
        self.on_wait = lambda: None


class Event:
    def __init__(self, clock):
        self.clock, self.signalled = clock, False

    def set(self):
        self.signalled = True

    def is_set(self):
        return self.signalled

    def wait(self, timeout):
        if not self.signalled:
            self.clock.now += timeout
            self.clock.on_wait()
        return self.signalled


@contextmanager
def simulated_time():
    clock = Clock()
    with patch("collaboration_recall_bridge.time.monotonic", side_effect=lambda: clock.now), \
            patch("collaboration_recall_bridge.time.time", side_effect=lambda: 1000 + clock.now), \
            patch("collaboration_recall_bridge.Pending", side_effect=lambda req, end: Pending(req, end, Event(clock))):
        yield clock


class CollaborationRecallRetryTest(unittest.TestCase):
    def test_rejected_or_lost_publish_recovers_without_changing_request(self):
        for first_accepted in (False, True):
            with self.subTest(first_accepted=first_accepted), simulated_time() as clock:
                broker, calls = RecallBroker(), []
                def publish(request):
                    calls.append(json.loads(json.dumps(request)))
                    if len(calls) == 1:
                        # The transport must not be able to corrupt a retried selector.
                        request["arguments"]["mode"] = "corrupted"
                        return first_accepted
                    self.assertTrue(broker.receive({**request, "type": RESPONSE,
                        "result": {"success": True, "content": "saved page"}}, "phone"))
                    return True
                self.assertEqual("saved page", broker.query(task, {"mode": "workspace"}, publish)["content"])
                self.assertEqual(calls[0], calls[1])
                self.assertEqual(2, clock.now)
                self.assertEqual({}, broker._pending)

    def test_backoff_is_bounded_by_original_deadline(self):
        for accepted in (False, True):
            with self.subTest(accepted=accepted), simulated_time() as clock:
                broker, calls = RecallBroker(), []
                def publish(request):
                    calls.append((clock.now, request))
                    return accepted
                with self.assertRaises(TimeoutError if accepted else ConnectionError):
                    broker.query(task, {"mode": "workspace"}, publish)
                self.assertEqual([0, 2, 6, 14], [at for at, _ in calls])
                self.assertEqual(20, clock.now)
                self.assertEqual(1, len({r["request_id"] for _, r in calls}))
                self.assertEqual({1020000}, {r["expires_at"] for _, r in calls})
                self.assertEqual({}, broker._pending)
                self.assertFalse(broker.receive({**calls[-1][1], "type": RESPONSE,
                    "result": {"success": True}}, "phone"))

    def test_publish_time_counts_against_deadline_and_late_response_is_rejected(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            def publish(request):
                calls.append(request)
                clock.now = 21
                self.assertFalse(broker.receive({**request, "type": RESPONSE,
                    "result": {"success": True}}, "phone"))
                return True
            with self.assertRaises(TimeoutError):
                broker.query(task, {"mode": "workspace"}, publish)
            self.assertEqual(1, len(calls))
            self.assertEqual({}, broker._pending)

    def test_cancellation_revocation_and_generation_change_stop_retries(self):
        for change in ("active", "generation", "paused", "cancel_requested", "client_route_id"):
            with self.subTest(change=change), simulated_time() as clock:
                broker, state, calls, live = RecallBroker(), task(), [], [True]
                def revoke():
                    if change == "active": live[0] = False
                    elif change == "generation": state["execution_generation"] = 2
                    elif change == "paused": state["status"] = "paused"
                    elif change == "cancel_requested": state[change] = True
                    else: state[change] = "other-phone"
                clock.on_wait = revoke
                def publish(request):
                    calls.append(request)
                    return True
                with self.assertRaises(ValueError):
                    broker.query(lambda: state, {"mode": "workspace"}, publish, active=lambda: live[0])
                self.assertEqual(1, len(calls))
                self.assertEqual({}, broker._pending)

    def test_authenticated_negative_result_is_not_retried(self):
        with simulated_time() as clock:
            broker, calls = RecallBroker(), []
            result = {"success": False, "status": "unavailable", "error": "Assignment was revoked"}
            def publish(request):
                calls.append(request)
                broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
                return True
            self.assertEqual(result, broker.query(task, {"mode": "workspace"}, publish))
            self.assertEqual(0, clock.now)
            self.assertEqual(1, len(calls))

    def test_wrong_phone_and_old_nonce_cannot_satisfy_retry(self):
        with simulated_time():
            broker, calls = RecallBroker(), []
            def publish(request):
                calls.append(request)
                response = {**request, "type": RESPONSE, "result": {"success": True}}
                self.assertFalse(broker.receive(response, "other-phone"))
                self.assertFalse(broker.receive({**response, "request_id": "old-nonce"}, "phone"))
                if len(calls) == 2:
                    self.assertTrue(broker.receive(response, "phone"))
                return True
            self.assertTrue(broker.query(task, {"mode": "workspace"}, publish)["success"])
            self.assertEqual(2, len(calls))

    def test_confirmation_retries_only_confirmation_with_same_receipt(self):
        with simulated_time():
            broker, calls = RecallBroker(), []
            delivery = {"receipt_id": "phone-receipt", "content_sha256": hashlib.sha256(b"original").hexdigest()}
            def publish(request):
                calls.append(request)
                if len(calls) == 2:
                    return True
                if request["phase"] == "read":
                    result = {"success": True, "content": "original", "delivery": delivery}
                else:
                    result = {"success": True, "status": "confirmed", "delivery": delivery,
                              "host_read_coverage": {"complete": True}}
                broker.receive({**request, "type": RESPONSE, "result": result}, "phone")
                return True
            result = broker.query(task, {"mode": "evidence", "evidence_id": "a" * 64, "sha256": "b" * 64}, publish)
            self.assertEqual("original", result["content"])
            self.assertEqual(["read", "confirm", "confirm"], [r["phase"] for r in calls])
            self.assertEqual(calls[1], calls[2])
            self.assertNotEqual(calls[0]["request_id"], calls[1]["request_id"])
            self.assertEqual(delivery, calls[2]["delivery"])
            self.assertTrue(result["host_read_coverage"]["complete"])

    def test_invalid_timeout_and_publisher_exception_never_retry(self):
        broker, calls = RecallBroker(), []
        def publish(request):
            calls.append(request)
            raise ValueError("invalid encryption state")
        for timeout in (0, -1, True, "20", 61, float("nan"), float("inf")):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                broker.query(task, {"mode": "workspace"}, publish, timeout=timeout)
        self.assertEqual([], calls)
        with self.assertRaisesRegex(ValueError, "encryption"):
            broker.query(task, {"mode": "workspace"}, publish)
        self.assertEqual(1, len(calls))
        self.assertEqual({}, broker._pending)

    def test_diagnostics_exclude_selectors_and_content(self):
        broker = RecallBroker()
        def publish(request):
            broker.receive({**request, "type": RESPONSE,
                            "result": {"success": True, "content": "private-saved-content"}}, "phone")
            return True
        with self.assertLogs("collaboration_recall_bridge", level="INFO") as recorded:
            broker.query(task, {"mode": "capabilities", "query": "private-search-words"}, publish)
        text = "\n".join(recorded.output)
        self.assertIn("attempts=1 accepted=1", text)
        self.assertIn("outcome=returned", text)
        self.assertNotIn("private-search-words", text)
        self.assertNotIn("private-saved-content", text)


if __name__ == "__main__":
    unittest.main()
