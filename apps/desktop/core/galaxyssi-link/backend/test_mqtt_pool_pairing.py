import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import link_protocol
import mqtt_bridge
import pairing_state
from mqtt_peer_routes import PeerRoutes
from mqtt_pool_client import MqttPoolClient
from tests.mqtt_pool_fixture import ManualPool
import test_link_pairing_integration as fixtures


class PoolPairingTest(unittest.TestCase):
    def setUp(self):
        fixtures.LinkPairingIntegrationTests.setUp(self)
        self.mqtt = MqttPoolClient(classify_publication=lambda *args: self.mqtt.peer_routes.classify(*args),
                                   on_paths_changed=mqtt_bridge._pool_paths_changed, pool_factory=ManualPool)
        self.mqtt.peer_routes = PeerRoutes(self.mqtt)
        self.mqtt.on_subscribe = mqtt_bridge.on_subscribe
        self.pool = self.mqtt._pool

    def tearDown(self):
        self.mqtt.disconnect()
        mqtt_bridge._reset_subscription_state()
        fixtures.LinkPairingIntegrationTests.tearDown(self)

    def claim(self, broker="hivemq", *, defer=False):
        self.pool.connect(broker)
        pairing = pairing_state.new_pairing_session()
        mqtt_bridge.reconcile_mqtt_subscriptions(self.mqtt, force=True)
        self.pool.auto_suback = not defer
        route = link_protocol.new_route_id()
        claim = fixtures.client_claim(pairing["token"], route, b"multi-path phone", "Phone")
        wire = link_protocol.encrypt_pairing_claim(claim, pairing["secret"])
        message = SimpleNamespace(topic=pairing["topic"], payload=wire.encode(),
                                  broker_id=broker, broker_generation=1)
        mqtt_bridge.on_message(self.mqtt, None, message)
        return pairing_state.get_client(route)

    def decoded(self, paired):
        return json.loads(link_protocol.open_wire_packet(self.pool.sent[-1][3], paired["link_secret"]))

    def test_encrypted_qr_claim_confirms_on_first_common_path_but_still_requires_resume(self):
        paired = self.claim()
        self.assertIsNotNone(paired)
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual("hivemq", self.pool.sent[0][0])
        self.assertEqual("pairing_confirmed", self.decoded(paired)["type"])
        self.assertFalse(self.mqtt.peer_routes.ready(paired["client_route_id"]))
        self.assertTrue(all(topic in self.pool.paths["hivemq"]["topics"]
                            for topic in mqtt_bridge._topics_for_client(paired).receive_window))

    def test_subscriptions_distributed_across_brokers_cannot_falsely_confirm_pairing(self):
        paired = self.claim(defer=True)
        topics = list(mqtt_bridge._topics_for_client(paired).receive_window)
        self.pool.connect("mosquitto")
        self.pool.confirm("hivemq", topics[:1])
        self.pool.confirm("mosquitto", topics[1:])
        self.assertEqual([], self.pool.sent)
        self.assertIn(paired["client_route_id"], mqtt_bridge.mqtt_pairing_confirmations)
        self.pool.confirm("mosquitto", topics)
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual("mosquitto", self.pool.sent[0][0])
        self.assertEqual("pairing_confirmed", self.decoded(paired)["type"])

    def test_missing_ingress_broker_uses_other_fully_subscribed_path_for_confirmation(self):
        paired = self.claim(defer=True)
        self.pool.lose("hivemq")
        self.pool.connect("mosquitto")
        self.pool.confirm("mosquitto", mqtt_bridge._topics_for_client(paired).receive_window)
        self.assertEqual(1, len(self.pool.sent))
        self.assertEqual("mosquitto", self.pool.sent[0][0])

    def test_suback_callback_restores_global_subscription_state_without_rescanning_registry(self):
        paired = self.claim()
        topics = mqtt_bridge._topics_for_client(paired).receive_window
        self.pool.lose("hivemq")
        self.assertFalse(mqtt_bridge.mqtt_subscription_active)
        with patch.object(mqtt_bridge, "list_clients", side_effect=AssertionError("callback registry scan")):
            self.pool.connect("mosquitto")
        self.assertTrue(all(topic in mqtt_bridge.mqtt_subscription_active for topic in topics))
        self.assertTrue(mqtt_bridge.mqtt_subscriptions_ready.is_set())

    def test_indexed_ingress_rechecks_current_pair_without_scanning_all_contacts(self):
        paired = self.claim()
        topic = next(iter(mqtt_bridge._topics_for_client(paired).receive_window))
        with (patch.object(mqtt_bridge, "client", self.mqtt),
              patch.object(mqtt_bridge, "list_clients", side_effect=AssertionError("inbound registry scan"))):
            self.assertEqual(paired["client_route_id"], mqtt_bridge._resolve_inbound_topic(topic)[1]["client_route_id"])
            pairing_state.revoke_client(paired["client_route_id"])
            self.assertIsNone(mqtt_bridge._resolve_inbound_topic(topic))

    def test_pool_repair_does_not_disconnect_healthy_connections(self):
        self.claim()
        with patch.object(self.pool, "close") as close:
            mqtt_bridge._request_transport_reconnect(self.mqtt, "subscription_ack_timeout")
        close.assert_not_called()
        self.assertTrue(self.mqtt.is_connected())


if __name__ == "__main__":
    unittest.main()
