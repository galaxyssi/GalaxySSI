import hashlib
import unittest

from collaboration_milestone_bridge import MilestoneBroker, RESPONSE, publish_snapshot, validate_arguments
from test_collaboration_milestone_bridge import task


class PublicationRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.request = {"mode": "publish", "milestone_id": "original", "artifact": '{"summary":"\u539f\u7a3f"}'}
        self.query = {"mode": "receipt", "milestone_id": "original",
                      "artifact_sha256": hashlib.sha256(self.request["artifact"].encode("utf-8")).hexdigest()}

    def test_first_attempt_has_no_lookup_roundtrip(self):
        calls = []
        result = publish_snapshot(self.request, lambda req: calls.append(req) or {"success": True}, lambda: True, recover=False)
        self.assertTrue(result["success"])
        self.assertEqual([self.request], calls)

    def test_exact_recorded_receipt_avoids_republication(self):
        calls = []
        receipt = {**self.query, "success": True, "status": "recorded", "revisions": [{"original": True}]}
        result = publish_snapshot(self.request, lambda req: calls.append(req) or receipt, lambda: True, recover=True)
        self.assertEqual(receipt, result)
        self.assertEqual([self.query], calls)

    def test_only_explicit_absence_resends_original_snapshot(self):
        calls = []
        def send(req):
            calls.append(req)
            return {**req, "success": True, "status": "not_recorded" if req["mode"] == "receipt" else "recorded"}
        self.assertEqual("recorded", publish_snapshot(self.request, send, lambda: True, recover=True)["status"])
        self.assertEqual([self.query, self.request], calls)

    def test_timeout_or_rejection_does_not_submit_again(self):
        for failure in (TimeoutError("offline"), ConnectionError("disconnected"),
                        {"success": False, "status": "unavailable"}, {"success": False, "status": "rejected"}):
            with self.subTest(failure=failure):
                calls = []
                def send(req):
                    calls.append(req)
                    if isinstance(failure, Exception):
                        raise failure
                    return failure
                if isinstance(failure, Exception):
                    with self.assertRaises(type(failure)):
                        publish_snapshot(self.request, send, lambda: True, recover=True)
                else:
                    self.assertEqual(failure, publish_snapshot(self.request, send, lambda: True, recover=True))
                self.assertEqual([self.query], calls)

    def test_wrong_hash_id_unknown_outcome_and_pause_cannot_resend(self):
        for change in ({"artifact_sha256": "f" * 64}, {"milestone_id": "another"}, {"status": "returned"}):
            calls = []
            def send(req):
                calls.append(req)
                return {**req, "success": True, "status": "not_recorded", **change}
            with self.assertRaises(ValueError):
                publish_snapshot(self.request, send, lambda: True, recover=True)
            self.assertEqual([self.query], calls)
        current = [True]
        def pause(req):
            current[0] = False
            return {**req, "success": True, "status": "not_recorded"}
        with self.assertRaisesRegex(ValueError, "assignment changed"):
            publish_snapshot(self.request, pause, lambda: current[0], recover=True)

    def test_receipt_transport_keeps_full_scope_phase_and_generation_checks(self):
        broker = MilestoneBroker()
        def send(req):
            self.assertEqual(self.query, req["arguments"])
            self.assertEqual("receipt", req["phase"])
            reply = {**req, "type": RESPONSE, "result": {**self.query, "success": True, "status": "not_recorded"}}
            for change in ({"phase": "publish"}, {"execution_generation": 2}, {"task_id": "other"}):
                self.assertFalse(broker.receive({**reply, **change}, "phone"))
            self.assertFalse(broker.receive(reply, "another-phone"))
            return broker.receive(reply, "phone")
        self.assertEqual("not_recorded", broker.query(task, self.query, send)["status"])
        with self.assertRaisesRegex(TimeoutError, "original publication outcome remains uncertain"):
            broker.query(task, self.query, lambda _: True, timeout=.005)
        self.assertEqual({}, broker._pending)

    def test_receipt_rejects_authority_artifact_and_malformed_hash(self):
        for changed in ({"task_id": "other"}, {"artifact": "{}"}, {"artifact_sha256": "F" * 64},
                        {"artifact_sha256": "a" * 63}, {"milestone_id": ""}, {"artifact_sha256": None}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                validate_arguments({**self.query, **changed})


if __name__ == "__main__":
    unittest.main()
