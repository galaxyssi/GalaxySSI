import unittest

from turn_execution_receipt import attach


class TurnReceiptTests(unittest.TestCase):
    def event(self, attempt, **extra):
        return {"kind": "agent", "event_id": f"provider:t:{attempt - 1}", "metadata": {
            "attempt": attempt, "provider": "codex", "execution_generation": 2, "model": "sent-model",
            "reasoning_effort": "xhigh", "token": "must-not-travel", **extra}}

    def test_terminal_replays_latest_submission_not_provider_attestation(self):
        payload = {}
        attach(payload, {"task_id": "t", "execution_generation": 2, "events": [
            self.event(2, model=""), self.event(1), self.event(3, execution_generation=1)]})
        self.assertEqual(payload, {"turn_receipt": {"generation": 2, "submission": {
            "attempt": 2, "provider": "codex", "model": "", "effort": "xhigh"}}})

    def test_receive_time_is_desktop_observation_only(self):
        payload = {}
        attach(payload, {"task_id": "t", "events": [{"kind": "tool", "metadata": {"model": "invented"}}],
               "delivery_trace": [{"stage": "phone_send_started", "at": 1000000},
                                  {"stage": "desktop_mqtt_received", "at": 50, "detail": "private-topic"}]})
        self.assertEqual(payload, {"turn_receipt": {"generation": 1, "desktop_received_at": 50}})

    def test_missing_evidence_and_foreign_tasks_do_not_write_fields(self):
        payload = {}
        attach(payload, {"task_id": "other", "execution_generation": 2, "events": [self.event(1)]})
        self.assertEqual({}, payload)
