import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from native_worker import Endpoint


class NativeIngressFaultTests(unittest.TestCase):
    def setUp(self):
        self.endpoint = Endpoint.__new__(Endpoint)
        self.endpoint.config = {"endpoints": {"emqx": {}, "hivemq": {}, "mosquitto": {}}}
        self.endpoint.observation_lock = threading.Lock()
        self.endpoint.paths, self.endpoint.wire_observed = {}, {}
        self.endpoint.dropped = 0
        self.endpoint.drop_incoming = self.endpoint.hold_incoming = False
        self.endpoint.hold_resume_only = False
        self.endpoint.held, self.endpoint.held_bytes = [], 0
        self.endpoint.client = Mock()
        self.endpoint.drop_broker = None
        self.endpoint.bridge = Mock()

    def receive(self, broker):
        self.endpoint.receive(None, None, SimpleNamespace(broker_id=broker, payload=b"owned synthetic packet"))

    def test_only_selected_path_is_dropped_and_clear_restores_it(self):
        self.endpoint.set_drop_broker("emqx")
        self.receive("emqx")
        self.endpoint.bridge.on_mqtt_message.assert_not_called()
        self.receive("hivemq")
        self.receive("mosquitto")
        self.assertEqual(2, self.endpoint.bridge.on_mqtt_message.call_count)
        self.assertEqual({"broker": None, "dropped": 1}, self.endpoint.set_drop_broker(None))
        self.receive("emqx")
        self.assertEqual(3, self.endpoint.bridge.on_mqtt_message.call_count)

    def test_unknown_path_cannot_change_active_fault(self):
        self.endpoint.set_drop_broker("hivemq")
        with self.assertRaises(ValueError):
            self.endpoint.set_drop_broker("public.example")
        self.assertEqual("hivemq", self.endpoint.drop_broker)

    def test_existing_all_path_drop_remains_effective(self):
        self.endpoint.drop_incoming = True
        for broker in self.endpoint.config["endpoints"]:
            self.receive(broker)
        self.assertEqual(3, self.endpoint.dropped)
        self.endpoint.bridge.on_mqtt_message.assert_not_called()

    def test_resume_only_hold_preserves_business_ingress_and_releases_original_packet(self):
        self.endpoint._is_resume_ack = Mock(side_effect=[True, False])
        self.endpoint.hold(True, resume_only=True)
        self.receive("emqx")
        self.receive("hivemq")
        self.assertEqual(1, len(self.endpoint.held))
        held = self.endpoint.held[0]
        self.endpoint.bridge.on_mqtt_message.assert_called_once()
        self.assertEqual({"holding": False, "released": 1}, self.endpoint.hold(False))
        self.assertIs(held, self.endpoint.bridge.on_mqtt_message.call_args.args[2])
        self.assertEqual([], self.endpoint.held)


if __name__ == "__main__":
    unittest.main()
