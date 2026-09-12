"""Real TCP/TLS + production Desktop pool/resume smoke, not a native Signal/App test."""
import asyncio
from dataclasses import replace
import json
import logging
import os
from pathlib import Path
import queue
import secrets
import socket
import ssl
import sys
import threading
import time
from types import SimpleNamespace

import paho.mqtt.client as mqtt
from owned_brokers import OwnedBrokers


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def wait_for(condition, message, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.02)
    raise AssertionError(message)


def reject_bad_tls(lab):
    endpoint = lab.endpoints["emqx"]
    for context, hostname in ((ssl.create_default_context(), "localhost"), (lab.client_tls(), "wrong.invalid")):
        try:
            with socket.create_connection((endpoint.host, endpoint.port), timeout=3) as raw:
                with context.wrap_socket(raw, server_hostname=hostname):
                    pass
        except ssl.SSLCertVerificationError:
            continue
        raise AssertionError("TLS accepted an unknown CA or a mismatched hostname")


def run_transport(lab, loop):
    from link_protocol import new_link_secret, open_wire_packet, seal_wire_packet
    from mqtt_broker_catalog import BROKER_IDS
    from mqtt_broker_pool import BROKERS, BrokerPool
    from mqtt_peer_routes import PeerBinding, PeerRoutes
    from mqtt_pool_client import MqttPoolClient

    reject_bad_tls(lab)
    errors = queue.Queue(maxsize=32)
    endpoints = []

    class LocalClient(mqtt.Client):
        def __init__(self, broker):
            super().__init__(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                             client_id=secrets.token_hex(12), clean_session=True,
                             reconnect_on_failure=False, protocol=mqtt.MQTTv311)
            self.broker = broker
            self.tls_set_context(lab.client_tls())
            self.connect_timeout = 3
            self.max_inflight_messages_set(12)
            self.max_queued_messages_set(12)

        def connect(self, host, port=1883, keepalive=60, *args, **kwargs):
            expected = BROKERS[self.broker]
            require((host, port) == (expected["host"], expected["tls_port"]), "Unexpected production endpoint")
            endpoint = lab.endpoints[self.broker]
            return super().connect(endpoint.host, endpoint.port, keepalive, *args, **kwargs)

    def endpoint(binding):
        client = MqttPoolClient(classify_publication=lambda *args: routes.classify(*args),
            pool_factory=lambda **callbacks: BrokerPool(**callbacks, client_factory=lambda broker, _gen: LocalClient(broker)))
        routes = PeerRoutes(client)
        routes.replace([binding])
        client.subscribe({topic: 1 for topic in binding.receive_topics})
        incoming = queue.Queue(maxsize=32)

        def receive(_client, _data, message):
            try:
                payload = json.loads(open_wire_packet(message.payload, binding.secret))
                if not routes.handle_verified(binding.scope, payload, broker_id=message.broker_id,
                        generation=message.broker_generation, authenticated_identity=binding.identity):
                    incoming.put_nowait((payload, message.broker_id))
            except Exception as error:
                if not errors.full():
                    errors.put_nowait(type(error).__name__)

        client.on_message = receive
        client.on_tick = routes.maintenance
        worker = threading.Thread(target=client.loop_forever, name=f"owned-lab-{binding.scope}", daemon=True)
        item = SimpleNamespace(client=client, routes=routes, binding=binding, incoming=incoming, worker=worker)
        endpoints.append(item)
        worker.start()
        return item

    def ready(paths):
        return all(set(item.client.ready_path_generations(item.binding.receive_topics)) == set(paths)
                   and item.routes.ready(item.binding.scope) for item in endpoints)

    def send(source, target, number, path=None):
        payload = {"type": "owned_lab_smoke", "id": number, "body": "synthetic-" + "x" * 256}
        encoded = seal_wire_packet(json.dumps(payload), source.binding.secret).encode()
        descriptor = source.routes.classify(source.binding.send_topic, encoded)
        require(descriptor is not None, "No authenticated business route")
        if path:
            generation = source.client.ready_path_generations(source.binding.receive_topics)[path]
            descriptor = replace(descriptor, authorized_paths=((path, generation),),
                                 attempted_brokers=frozenset(BROKER_IDS) - {path})
        started = time.perf_counter()
        info = source.client.publish(source.binding.send_topic, encoded, publication=descriptor)
        require(info.rc == mqtt.MQTT_ERR_SUCCESS, "Publication not admitted")
        observed, broker = target.incoming.get(timeout=8)
        require(observed == payload and (path is None or broker == path), "Incorrect content or path")
        require(source.incoming.empty(), "Sender received its own directed message")
        return {"broker": broker, "receive_ms": round((time.perf_counter() - started) * 1000, 3)}

    try:
        secret = new_link_secret()
        topic = "owned-lab/" + secrets.token_hex(16)
        left = endpoint(PeerBinding("lab-left", "a" * 64, "b" * 64, secret, topic + "/right", frozenset({topic + "/left"})))
        right = endpoint(PeerBinding("lab-right", "b" * 64, "a" * 64, secret, topic + "/left", frozenset({topic + "/right"})))
        wait_for(lambda: ready(BROKER_IDS), "Three TLS/SUBACK/authenticated routes did not become ready")
        samples = []
        for broker in BROKER_IDS:
            samples.append(send(left, right, len(samples), broker))
            samples.append(send(right, left, len(samples), broker))
        asyncio.run_coroutine_threadsafe(lab.stop("emqx"), loop).result(timeout=10)
        wait_for(lambda: ready({"hivemq", "mosquitto"}), "One outage disabled the healthy paths")
        samples.append(send(left, right, len(samples)))
        samples.append(send(right, left, len(samples)))
        asyncio.run_coroutine_threadsafe(lab.start("emqx"), loop).result(timeout=10)
        wait_for(lambda: ready(BROKER_IDS), "Restarted path did not resubscribe and resume")
        samples.append(send(left, right, len(samples), "emqx"))
        samples.append(send(right, left, len(samples), "emqx"))
        require(errors.empty(), f"Ingress errors: {list(errors.queue)}")
        require(all(item.incoming.empty() for item in endpoints), "Unexpected extra business packet")
        return {"status": "passed", "tls_negative_cases": 2, "directed_messages": len(samples),
                "broker_failure_recovery": "passed", "samples": samples}
    finally:
        for item in endpoints:
            item.client.disconnect()
        for item in endpoints:
            item.worker.join(8)
            require(not item.worker.is_alive() and item.client.wait_closed(1), "Pool workers did not close")


async def main():
    async with OwnedBrokers() as lab:
        # Set isolated state before importing any production persistence module.
        os.environ["GALAXYSSI_DATA_DIR"] = str(lab.directory / "state")
        os.environ["GALAXYSSI_STATE_DIR"] = str(lab.directory / "state")
        sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "apps/desktop/core/galaxyssi-link/backend"))
        report = await asyncio.to_thread(run_transport, lab, asyncio.get_running_loop())
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    asyncio.run(main())
