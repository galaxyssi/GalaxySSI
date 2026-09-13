"""Physical test adapter: catalog names may only resolve to owned loopback TLS."""
import secrets
import ssl

import paho.mqtt.client as mqtt


def client_factory(endpoints, ca_file):
    from mqtt_broker_catalog import BROKERS

    if set(endpoints) != set(BROKERS):
        raise ValueError("Exactly three owned endpoints are required")
    for item in endpoints.values():
        if item["host"] != "127.0.0.1" or not 1024 < int(item["port"]) < 65536:
            raise ValueError("Owned endpoints must be unprivileged loopback listeners")

    class LocalClient(mqtt.Client):
        def __init__(self, broker):
            super().__init__(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=secrets.token_hex(12), clean_session=True,
                             reconnect_on_failure=False, protocol=mqtt.MQTTv311)
            self.broker = broker
            context = ssl.create_default_context(cafile=str(ca_file))
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            self.tls_set_context(context)
            self.connect_timeout = 3
            self.max_inflight_messages_set(12)
            self.max_queued_messages_set(12)

        def connect(self, host, port=1883, keepalive=60, *args, **kwargs):
            expected = BROKERS[self.broker]
            if (host, port) != (expected["host"], expected["tls_port"]):
                raise ValueError("Unexpected catalog endpoint")
            endpoint = endpoints[self.broker]
            return super().connect(endpoint["host"], endpoint["port"], keepalive, *args, **kwargs)

    return lambda broker, _generation: LocalClient(broker)
