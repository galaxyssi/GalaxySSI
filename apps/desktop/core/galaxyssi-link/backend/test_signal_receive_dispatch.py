import copy
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import link_delivery as delivery
import link_protocol
import signal_receive_dispatch as dispatch
from tests.receive_test_support import store_received_envelope


class SignalReceiveDispatchTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="galaxyssi-dispatch-")
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name) / "delivery.db"
        self.override = patch.object(delivery, "DB_PATH", self.path)
        self.override.start()
        self.addCleanup(self.override.stop)
        self.envelope = link_protocol.make_envelope(
            {"type": "peer_message", "content": "private dispatch content"},
            source_id="phone", target_id="desktop", conversation_id="conversation")
        self.mid = self.envelope["message_id"]
        self.store()

    def store(self, envelope=None, route="pair"):
        return store_received_envelope(route, self.envelope if envelope is None else envelope)

    def state(self):
        with closing(sqlite3.connect(self.path)) as db:
            return db.execute("SELECT dispatch_state,dispatch_attempts,dispatch_error FROM inbound_messages").fetchone()

    def guard(self, route="pair", mid=None):
        return dispatch.DispatchGuard(route, mid or self.mid)

    def test_body_read_requires_existing_complete_body(self):
        self.assertEqual(self.envelope, dispatch.load_envelope("pair", self.mid))
        with self.assertRaises(RuntimeError):
            dispatch.load_envelope("other", self.mid)

    def test_only_one_concurrent_owner_in_same_process(self):
        with self.guard() as first:
            self.assertTrue(first.acquired)
            self.assertEqual("run", dispatch.begin(first, self.envelope).state)
            with self.guard() as second:
                self.assertFalse(second.acquired)
                self.assertEqual("busy", dispatch.begin(second, self.envelope).state)

    def test_completed_handoff_not_executed_again(self):
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            self.assertTrue(dispatch.finish(guard, claim))
        with self.guard() as guard:
            self.assertEqual("dispatched", dispatch.begin(guard, self.envelope).state)
        self.assertEqual([], dispatch.pending())

    def test_safe_interrupted_handoff_can_resume(self):
        with self.guard() as guard:
            dispatch.begin(guard, self.envelope)
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            self.assertEqual(("run", True), (claim.state, claim.recovered))
            dispatch.finish(guard, claim)
        self.assertEqual(("dispatched", 2, ""), self.state())

    def test_unknown_external_handoff_requires_reconciliation(self):
        envelope = link_protocol.make_envelope({"type": "external_effect"}, source_id="phone", target_id="desktop")
        self.store(envelope)
        with self.guard(mid=envelope["message_id"]) as guard:
            dispatch.begin(guard, envelope)
        with self.guard(mid=envelope["message_id"]) as guard:
            self.assertEqual("uncertain", dispatch.begin(guard, envelope).state)

    def test_task_recovery_requires_stable_identity_and_not_transcribe_only(self):
        value = {"type": "text", "client_route_id": "pair", "conversation_id": "c", "task_id": "t", "turn_id": "turn"}
        self.assertTrue(dispatch.retry_safe({"payload": value}))
        for key in ("client_route_id", "conversation_id", "task_id", "turn_id"):
            self.assertFalse(dispatch.retry_safe({"payload": {**value, key: ""}}))
        self.assertFalse(dispatch.retry_safe({"payload": {**value, "audio_mode": "transcribe_only"}}))
        self.assertFalse(dispatch.retry_safe({"payload": {**value, "type": "agent_task_cancel"}}))

    def test_mutation_and_json_type_change_are_rejected(self):
        self.envelope["payload"]["flag"] = True
        envelope = link_protocol.make_envelope(self.envelope["payload"], source_id="phone", target_id="desktop")
        self.store(envelope)
        changed = copy.deepcopy(envelope)
        changed["payload"]["flag"] = 1
        with self.guard(mid=envelope["message_id"]) as guard:
            with self.assertRaises(delivery.InboundContentConflict):
                dispatch.begin(guard, changed)
        self.assertEqual(envelope, dispatch.load_envelope("pair", envelope["message_id"]))

    def test_finish_requires_owned_token(self):
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            self.assertFalse(dispatch.finish(guard, dispatch.Claim("run", "not-owned")))
            self.assertTrue(dispatch.finish(guard, claim))
        with self.assertRaises(ValueError):
            dispatch.finish(guard, claim)

    def test_retry_keeps_body_and_obeys_backoff(self):
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            dispatch.finish(guard, claim, error=OSError("private error"), replayable=True)
        self.assertEqual([], dispatch.pending())
        self.assertEqual(("retry", 1, "OSError"), self.state())
        page = dispatch.pending(now=time.time() + 100)
        self.assertEqual(1, len(page))
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope, admission_token=page[0][3])
            self.assertEqual("run", claim.state)
            dispatch.finish(guard, claim)

    def test_pending_admission_does_not_mean_a_dead_handler(self):
        with self.guard() as guard:
            dispatch.begin(guard, self.envelope)
            page = dispatch.pending(now=time.time() + 1000)
            with self.guard() as other:
                self.assertEqual("busy", dispatch.begin(other, self.envelope, admission_token=page[0][3]).state)
        self.assertEqual("running", self.state()[0])

    def test_queue_loss_is_re_admitted_without_losing_body(self):
        at = time.time()
        first = dispatch.pending(now=at)
        self.assertEqual([], dispatch.pending(now=at + 1))
        second = dispatch.pending(now=at + 6)
        self.assertEqual(first[0][:3], second[0][:3])
        self.assertNotEqual(first[0][3], second[0][3])
        with self.guard() as guard:
            self.assertEqual("deferred", dispatch.begin(guard, self.envelope, admission_token=first[0][3]).state)
            self.assertEqual("run", dispatch.begin(guard, self.envelope, admission_token=second[0][3]).state)

    def test_recovery_queue_cannot_delay_live_first_delivery(self):
        at = time.time()
        queued = dispatch.pending(now=at)
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope, now=at + .01)
            self.assertEqual("run", claim.state)
            self.assertTrue(dispatch.finish(guard, claim))
        with self.guard() as guard:
            self.assertEqual("dispatched", dispatch.begin(guard, self.envelope,
                admission_token=queued[0][3], now=at + .02).state)
        self.assertEqual(("dispatched", 1, ""), self.state())

    def test_live_duplicate_cannot_bypass_retry_queue_backoff(self):
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            dispatch.finish(guard, claim, error=OSError("owned retry"), replayable=True)
        at = time.time() + 100
        queued = dispatch.pending(now=at)
        with self.guard() as guard:
            self.assertEqual("deferred", dispatch.begin(guard, self.envelope, now=at + .01).state)
            self.assertEqual("run", dispatch.begin(guard, self.envelope,
                admission_token=queued[0][3], now=at + .01).state)

    def test_live_duplicate_cannot_take_an_interrupted_unsafe_handler(self):
        envelope = link_protocol.make_envelope({"type": "external_effect"}, source_id="phone", target_id="desktop")
        self.store(envelope)
        with self.guard(mid=envelope["message_id"]) as guard:
            dispatch.begin(guard, envelope)
        at = time.time() + 100
        queued = next(row for row in dispatch.pending(now=at) if row[1] == envelope["message_id"])
        with self.guard(mid=envelope["message_id"]) as guard:
            self.assertEqual("deferred", dispatch.begin(guard, envelope, now=at + .01).state)
            self.assertEqual("uncertain", dispatch.begin(guard, envelope,
                admission_token=queued[3], now=at + .01).state)

    def test_pages_are_bounded_and_rotate_queued_work(self):
        for index in range(35):
            envelope = link_protocol.make_envelope({"type": "peer_message", "content": str(index)},
                                                   source_id="phone", target_id="desktop")
            self.store(envelope, route=f"pair-{index % 3}")
        at = time.time()
        first = dispatch.pending(limit=16, now=at)
        second = dispatch.pending(limit=16, now=at)
        self.assertEqual((16, 16), (len(first), len(second)))
        self.assertFalse({row[1] for row in first} & {row[1] for row in second})
        with self.assertRaises(ValueError):
            dispatch.pending(limit=1000)

    def test_explicit_revocation_removes_pending_and_invalidates_finish(self):
        with self.guard() as guard:
            claim = dispatch.begin(guard, self.envelope)
            delivery.discard_route("pair")
            self.assertFalse(dispatch.finish(guard, claim))
        self.assertEqual([], dispatch.pending())

    def test_rejected_body_is_not_repeatedly_admitted(self):
        dispatch.pending()
        dispatch.reject_stored("pair", self.mid, "expired")
        self.assertEqual("rejected", self.state()[0])
        self.assertEqual([], dispatch.pending(now=time.time() + 100))
        with self.guard() as guard:
            self.assertEqual("rejected", dispatch.begin(guard, self.envelope).state)

    def test_pending_query_uses_partial_index_not_completed_body_scan(self):
        with closing(delivery._connect()) as db:
            plan = db.execute("EXPLAIN QUERY PLAN " + dispatch.PENDING_SQL, (time.time(), 16)).fetchall()
        details = " ".join(str(row[-1]) for row in plan)
        self.assertIn("inbound_dispatch_pending", details)
        self.assertNotIn("SCAN b", details)
        self.assertNotIn("TEMP B-TREE", details)

    def test_real_process_death_releases_handler_lock_and_preserves_body(self):
        # Initialize the shared identifier key before starting another process.
        delivery._route("pair")
        script = """
import json, sys
from pathlib import Path
import link_delivery as delivery
import signal_receive_dispatch as dispatch
delivery.DB_PATH = Path(sys.argv[1])
with dispatch.DispatchGuard('pair', sys.argv[2]) as guard:
    claim = dispatch.begin(guard, dispatch.load_envelope('pair', sys.argv[2]))
    print(claim.state, flush=True)
    sys.stdin.readline()
"""
        child = subprocess.Popen([sys.executable, "-c", script, str(self.path), self.mid],
                                 cwd=Path(delivery.__file__).parent, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        deadline = threading.Timer(30, child.kill)
        deadline.start()
        try:
            self.assertEqual(b"run", child.stdout.readline().strip())
            with self.guard() as guard:
                self.assertFalse(guard.acquired)
            child.kill()
            child.communicate(timeout=10)
            with self.guard() as guard:
                self.assertTrue(guard.acquired)
                claim = dispatch.begin(guard, self.envelope)
                self.assertEqual(("run", True), (claim.state, claim.recovered))
                dispatch.finish(guard, claim)
        finally:
            deadline.cancel()
            if child.poll() is None:
                child.kill()
            child.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
