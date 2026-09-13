from types import SimpleNamespace
import threading
import unittest
from unittest.mock import Mock

from native_control_endpoint import ControlEndpoint
from native_measurements import Measurements


class ControlEndpointTests(unittest.TestCase):
    def setUp(self):
        self.manager = Mock()
        self.endpoint = SimpleNamespace(route="A" * 22, client=object(), measurements=Measurements(),
            bridge=SimpleNamespace(agent_task_manager=self.manager, _publish_phone_payload=Mock(return_value=True)))
        self.control = ControlEndpoint(self.endpoint)

    def test_create_persists_scope_without_starting_a_model_runner(self):
        record = self.control.create()
        args = self.manager.create_external.call_args.kwargs
        self.assertEqual("", args["agent_id"])
        self.assertEqual(record["task_id"], args["task_id"])
        self.assertEqual(record["client_route_id"], args["client_route_id"])
        self.assertEqual(record["conversation_id"], args["client_conversation_id"])
        self.assertEqual(record["turn_id"], args["client_turn_id"])
        self.manager.create.assert_not_called()

    def test_real_publish_retains_control_identity_and_measures_event(self):
        record = self.control.create()
        sent = self.control.send(record)
        payload = self.endpoint.bridge._publish_phone_payload.call_args.args[2]
        self.assertEqual("agent_task_cancel", payload["type"])
        self.assertTrue(sent["queued"])
        for key, value in record.items():
            self.assertEqual(value, payload[key])
        self.control.capture({**record, "type": "agent_task_event", "task_status": "cancelled"})
        sample = self.endpoint.measurements.snapshot(sent["message_id"])
        self.assertIn("cancel_event_received", sample["stages"])

    def test_invalid_event_cannot_complete_measurement(self):
        record = self.control.create()
        sent = self.control.send(record)
        event = {**record, "task_status": "cancelled"}
        for key in ("task_id", "conversation_id", "turn_id", "source_message_id", "contact_id", "task_status"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.control.capture({**event, key: "wrong"})
        self.assertNotIn("cancel_event_received", self.endpoint.measurements.snapshot(sent["message_id"])["stages"])

    def test_bounded_tasks_samples_and_events(self):
        record = self.control.create()
        self.control.send(record)
        with self.assertRaises(ValueError):
            self.control.send(record)
        for _ in range(8):
            self.control.capture({**record, "task_status": "cancelled"})
        with self.assertRaises(ValueError):
            self.control.capture({**record, "task_status": "cancelled"})
        self.control.tasks = set(map(str, range(128)))
        with self.assertRaises(ValueError):
            self.control.create()
        with self.assertRaises(ValueError):
            self.control.command({"operation": "inspect", "task_id": "unowned"})

    def test_receiver_stage_measurements_are_owned_and_copied(self):
        self.control.stage("unowned", "dispatch_enter")
        self.control.observe_envelope({"message_id": "unowned", "payload": {
            "type": "agent_task_event", "task_id": "unowned"}})
        self.assertEqual({}, self.control.command({"operation": "diagnostics"}))
        record = self.control.create()
        self.control.stage(record["task_id"], "dispatch_enter")
        self.control.observe_envelope({"message_id": "reply", "payload": {
            "type": "agent_task_event", "task_id": record["task_id"]}})
        result = self.control.command({"operation": "diagnostics"})[record["task_id"]]
        self.assertEqual(["reply"], result["reply_ids"])
        self.assertIn("reply_encrypt_enter", result["stages"])
        self.assertIn("started", self.endpoint.measurements.snapshot("reply")["stages"])
        result["reply_ids"].clear()
        self.assertEqual(["reply"], self.control.command({"operation": "diagnostics"})[record["task_id"]]["reply_ids"])

    def test_ack_observation_preserves_result_and_restores_context(self):
        record = self.control.create()
        bridge = self.endpoint.bridge

        def ack(mqttc, wire, envelope, payload, trace, **kwargs):
            self.assertTrue(kwargs["duplicate"])
            self.control.observe_envelope({"payload": {"type": "delivery_ack"}})
            return bridge._publish_phone_payload(mqttc, wire, {"type": "delivery_ack"})

        bridge._ack_stored_application = ack
        self.control.install_ack_timing(bridge)
        self.assertTrue(bridge._ack_stored_application(None, {}, {}, {**record, "type": "agent_task_cancel"}, [], duplicate=True))
        stages = self.control.command({"operation": "diagnostics"})[record["task_id"]]["stages"]
        self.assertTrue({"ack_enter", "ack_return", "signal_ack_enter", "signal_ack_return", "signal_ack_encrypt_enter"} <= stages.keys())
        self.assertIsNone(self.control.current_ack.task_id)

    def test_ack_exception_is_not_swallowed_or_leaked_to_next_request(self):
        record = self.control.create()
        self.endpoint.bridge._ack_stored_application = Mock(side_effect=RuntimeError("owned failure"))
        self.control.install_ack_timing(self.endpoint.bridge)
        with self.assertRaisesRegex(RuntimeError, "owned failure"):
            self.endpoint.bridge._ack_stored_application(None, {}, {}, {**record, "type": "agent_task_cancel"}, [])
        self.assertIsNone(self.control.current_ack.task_id)
        self.control.observe_envelope({"payload": {"type": "delivery_ack"}})
        stages = self.control.command({"operation": "diagnostics"})[record["task_id"]]["stages"]
        self.assertNotIn("signal_ack_encrypt_enter", stages)

    def test_overlapping_ack_calls_keep_their_own_start_and_end(self):
        record = self.control.create()
        entered, release = threading.Event(), threading.Event()

        def ack(*args, **kwargs):
            if not kwargs.get("duplicate"):
                entered.set()
                if not release.wait(3):
                    raise TimeoutError("Owned release was not signaled")
            return "unchanged"

        bridge = self.endpoint.bridge
        bridge._ack_stored_application = ack
        self.control.install_ack_timing(bridge)
        args = (None, {}, {}, {**record, "type": "agent_task_cancel"}, [])
        worker = threading.Thread(target=lambda: bridge._ack_stored_application(*args))
        worker.start()
        try:
            self.assertTrue(entered.wait(2))
            self.assertEqual("unchanged", bridge._ack_stored_application(*args, duplicate=True))
        finally:
            release.set()
            worker.join(2)
        self.assertFalse(worker.is_alive())
        calls = self.control.command({"operation": "diagnostics"})[record["task_id"]]["ack_calls"]
        self.assertEqual([False, True], [item["duplicate"] for item in calls])
        primary, duplicate = (item["stages"] for item in calls)
        self.assertLess(primary["ack_enter"], duplicate["ack_enter"])
        self.assertLess(duplicate["ack_return"], primary["ack_return"])

    def test_ack_observations_are_bounded_without_blocking_real_ack(self):
        record = self.control.create()
        bridge = self.endpoint.bridge
        actual = bridge._ack_stored_application = Mock(return_value=True)
        self.control.install_ack_timing(bridge)
        for _ in range(20):
            self.assertTrue(bridge._ack_stored_application(None, {}, {},
                {**record, "type": "agent_task_cancel"}, [], duplicate=True))
        timing = self.control.command({"operation": "diagnostics"})[record["task_id"]]
        self.assertEqual(16, len(timing["ack_calls"]))
        self.assertEqual(4, timing["ack_calls_dropped"])
        self.assertEqual(20, actual.call_count)

    def test_receive_observation_keeps_exact_call_timing_and_ack_identity(self):
        record = self.control.create()
        bridge = self.endpoint.bridge
        received = [("desktop_request_received", 10), ("desktop_handler_started", 20)]
        bridge._ack_stored_application = Mock(return_value=True)
        self.control.install_ack_timing(bridge)

        def actual(mqttc, paired, wire, envelope, payload, trace, **kwargs):
            self.assertEqual("token", kwargs["admission_token"])
            self.assertIs(received, kwargs["timings"])
            bridge._ack_stored_application(mqttc, wire, envelope, payload, trace)
            self.control.stage(record["task_id"], "dispatch_enter")
            return "unchanged"

        bridge._deliver_stored_application = actual
        self.control.install_receive_timing(bridge)
        self.assertEqual("unchanged", bridge._deliver_stored_application(None, {}, {},
            {"message_id": "request"}, {**record, "type": "agent_task_cancel"}, [],
            timings=received, admission_token="token"))
        timing = self.control.command({"operation": "diagnostics", "task_id": record["task_id"]})
        call = timing["receive_calls"][0]
        self.assertEqual("request", call["message_id"])
        self.assertEqual(call["call_id"], timing["ack_calls"][0]["receive_call_id"])
        self.assertEqual(10, call["stages"]["desktop_request_received"])
        self.assertTrue({"delivery_enter", "ack_enter", "ack_return", "dispatch_enter", "delivery_return"}
                        <= call["stages"].keys())
        self.assertIsNone(self.control.current_receive.context)
        received.clear()
        call["stages"].clear()
        self.assertTrue(self.control.command({"operation": "diagnostics", "task_id": record["task_id"]})
                        ["receive_calls"][0]["stages"])

    def test_return_delivery_measures_pending_task_without_receiver_task(self):
        record = self.control.create()
        self.control.send(record)
        self.control.tasks.clear()
        event = {**record, "type": "agent_task_event", "task_status": "cancelled"}
        bridge = self.endpoint.bridge
        bridge._deliver_stored_application = lambda *args, **kwargs: self.control.capture(args[4])
        self.control.install_receive_timing(bridge)
        bridge._deliver_stored_application(None, {}, {}, {"message_id": "reply"}, event, [],
                                          timings=[("desktop_request_received", 10)])
        calls = self.control.command({"operation": "diagnostics", "task_id": record["task_id"]})["receive_calls"]
        self.assertEqual("agent_task_event", calls[0]["kind"])
        self.assertIn("cancel_event_capture", calls[0]["stages"])
        self.assertIsNone(self.control.current_receive.context)

    def test_receive_observation_preserves_exception_and_bounds(self):
        record = self.control.create()
        bridge = self.endpoint.bridge
        actual = bridge._deliver_stored_application = Mock(side_effect=RuntimeError("owned failure"))
        self.control.install_receive_timing(bridge)
        for _ in range(20):
            with self.assertRaisesRegex(RuntimeError, "owned failure"):
                bridge._deliver_stored_application(None, {}, {}, {"message_id": "request"},
                                                  {**record, "type": "agent_task_cancel"}, [])
            self.assertIsNone(self.control.current_receive.context)
        timing = self.control.command({"operation": "diagnostics", "task_id": record["task_id"]})
        self.assertEqual(16, len(timing["receive_calls"]))
        self.assertEqual(4, timing["receive_calls_dropped"])
        self.assertEqual(20, actual.call_count)

    def test_unowned_receive_is_not_observed_or_changed(self):
        actual = self.endpoint.bridge._deliver_stored_application = Mock(return_value="original")
        self.control.install_receive_timing(self.endpoint.bridge)
        args = (None, {}, {}, {"message_id": "unowned"}, {"type": "agent_task_cancel", "task_id": "unowned"}, [])
        self.assertEqual("original", self.endpoint.bridge._deliver_stored_application(*args))
        actual.assert_called_once_with(*args)
        self.assertEqual({}, self.control.timings)


if __name__ == "__main__":
    unittest.main()
