"""Isolated JSON-line test endpoint; production crypto, ingress, dispatch and stores."""
from contextlib import closing
from dataclasses import replace
import hashlib
import json
import logging
import os
from pathlib import Path
import socket
import sys
import threading
import time
import traceback

from local_client import client_factory


class ErrorCapture(logging.Handler):
    def __init__(self, path):
        super().__init__(logging.ERROR)
        self.path = path
        self.errors = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []

    def emit(self, record):
        detail = "".join(traceback.format_exception(*sys.exc_info())) if sys.exc_info()[0] else ""
        if len(self.errors) < 32:
            value = {"message": record.getMessage(), "exception": detail}
            self.errors.append(value)
            with self.path.open("a", encoding="utf-8") as output:
                output.write(json.dumps(value) + "\n")
        if detail:
            sys.stderr.write(detail)


class Endpoint:
    def __init__(self, config):
        self.root = Path(config["state"]).resolve()
        if not self.root.parent.name.startswith("galaxyssi-owned-mqtt-"):
            raise ValueError("Refusing non-disposable state")
        self.root.mkdir(parents=True, exist_ok=True)
        os.environ.update(GALAXYSSI_DATA_DIR=str(self.root), GALAXYSSI_STATE_DIR=str(self.root),
                          GALAXYSSI_DATABASE_PATH=str(self.root / "app.db"),
                          GALAXYSSI_CONFIG_PATH=str(self.root / "agents.json"))
        sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "apps/desktop/core/galaxyssi-link/backend"))
        import galaxyssi_client as signal
        # Reserve an isolated API port before any production module can start a sidecar.
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            signal.SIDECAR_PORT = sock.getsockname()[1]
        signal.SIDECAR_BASE = f"http://127.0.0.1:{signal.SIDECAR_PORT}"
        signal.SIGNAL_STORE_PATH = self.root / "signal.db"
        signal.SIDECAR_DIR = self.root / "sidecar-logs"
        signal.SIDECAR_DIR.mkdir(exist_ok=True)
        self.signal = signal
        try:
            self.bundle = signal.get_signal_bundle()
        except BaseException:
            signal.stop_signal_sidecar()
            raise
        self.config = config
        self.client = self.worker = None
        self.drop_incoming = False
        self.hold_incoming = False
        self.held = []
        self.held_bytes = 0
        self.dropped = 0
        self.observation_lock = threading.Lock()
        self.paths = {}
        self.wire_observed = {}
        self.wires = {}
        self.error_capture = ErrorCapture(self.root / "errors.jsonl")
        logging.getLogger("galaxyssi.mqtt").addHandler(self.error_capture)

    def configure(self, value):
        import pairing_state
        remote = value["bundle"]
        self.route = value["route"]
        self.remote = "desktop_" + remote["identityKeySha256"][:16]
        self.secret = value["secret"]
        self.signal.replace_peer_signal_bundle(remote, self.remote)
        pairing_state.record_pairing_success(remote["identityKeySha256"], self.remote,
            client_route_id=self.route, link_secret=self.secret,
            local_identity_fingerprint=self.bundle["identityKeySha256"], display_name="Owned test peer")
        return self.start_transport()

    def start_transport(self):
        import mqtt_bridge as bridge
        import pairing_state
        from mqtt_broker_pool import BrokerPool
        from mqtt_pool_client import MqttPoolClient
        from mqtt_peer_routes import PeerRoutes

        if self.client is not None:
            raise ValueError("Transport already started")
        paired = pairing_state.list_clients()
        if len(paired) != 1:
            raise ValueError("Expected one isolated peer")
        self.route = paired[0]["client_route_id"]
        self.remote = paired[0]["signal_name"]
        self.secret = paired[0]["link_secret"]
        self.bridge = bridge
        factory = client_factory(self.config["endpoints"], self.config["ca"])
        client = MqttPoolClient(classify_publication=lambda *args: client.peer_routes.classify(*args),
            pool_factory=lambda **callbacks: BrokerPool(**callbacks, client_factory=factory))
        client.peer_routes = PeerRoutes(client)
        self.client = bridge.client = client
        bridge._refresh_pool_peers(client)
        topics = bridge._topics_for_client(paired[0])
        with bridge.mqtt_subscription_lock:
            bridge.mqtt_subscription_expected.clear()
            bridge.mqtt_subscription_expected.update({topic: self.route for topic in topics.receive_window})
        client.subscribe({topic: 1 for topic in topics.receive_window})
        client.on_publish = bridge.on_publish
        client.on_message = self.receive
        client.on_tick = self.tick
        actual_encrypt = bridge.encrypt_signal_payload

        def observed_encrypt(envelope, *args, **kwargs):
            wire = actual_encrypt(envelope, *args, **kwargs)
            self.wires.setdefault(envelope["message_id"], wire)
            return wire

        bridge.encrypt_signal_payload = observed_encrypt
        self.worker = threading.Thread(target=client.loop_forever, name="owned-native-pool", daemon=True)
        self.worker.start()
        return {"started": True, "identity": self.bundle["identityKeySha256"]}

    def receive(self, client, userdata, message):
        with self.observation_lock:
            self.paths[message.broker_id] = self.paths.get(message.broker_id, 0) + 1
            digest = hashlib.sha256(message.payload).hexdigest()
            if digest not in self.wire_observed and len(self.wire_observed) >= 128:
                self.wire_observed.pop(next(iter(self.wire_observed)))
            counts = self.wire_observed.setdefault(digest, {})
            counts[message.broker_id] = counts.get(message.broker_id, 0) + 1
            if self.drop_incoming:
                self.dropped += 1
                return
            if self.hold_incoming:
                if len(self.held) >= 128 or self.held_bytes + len(message.payload) > 4 * 1024 * 1024:
                    raise RuntimeError("Owned delayed ingress exceeded its bounded buffer")
                self.held.append(message)
                self.held_bytes += len(message.payload)
                return
        self.bridge.on_mqtt_message(client, userdata, message)

    def hold(self, enabled):
        with self.observation_lock:
            self.hold_incoming = enabled
            released = [] if enabled else self.held
            if not enabled:
                self.held, self.held_bytes = [], 0
        for message in released:
            self.bridge.on_mqtt_message(self.client, None, message)
        return {"holding": enabled, "released": len(released)}

    def tick(self):
        self.client.peer_routes.maintenance()
        self.bridge.flush_pending_inbound_messages(self.client)
        self.bridge.flush_outbound_messages(self.client)

    def snapshot(self):
        import link_delivery as delivery
        from peer_chat_store import peer_chat_store, _REMOTE_PURPOSE
        from secure_state import unseal_identifier
        store = peer_chat_store()
        rows = store.list_messages(limit=2000)
        with closing(store._connect()) as db:
            remote_ids = {row[0]: unseal_identifier(store.database_path, row[1], purpose=_REMOTE_PURPOSE)
                          for row in db.execute("SELECT message_id,remote_message_id FROM peer_messages WHERE direction='inbound'")}
        with closing(delivery._connect()) as db:
            inbox = [{"id": row[0], "state": row[1], "attempts": row[2], "error": row[3]}
                     for row in db.execute("SELECT message_id,dispatch_state,dispatch_attempts,dispatch_error FROM inbound_messages")]
            outbox = [{"id": row[0], "state": row[1], "attempts": row[2]}
                      for row in db.execute("SELECT message_id,status,attempts FROM outbound_messages")]
        with self.observation_lock:
            observations = {"received_paths": dict(self.paths), "dropped": self.dropped,
                            "wire_observed": {digest: dict(counts) for digest, counts in self.wire_observed.items()}}
            held = list(self.held)
        from link_protocol import open_wire_packet
        observations["held_resume_acks"] = []
        for message in held:
            payload = json.loads(open_wire_packet(message.payload, self.secret))
            if payload.get("type") == "link_resume_ack":
                observations["held_resume_acks"].append({"broker": message.broker_id,
                    "epoch": payload.get("acknowledged_route_epoch")})
        peer = self.client.peer_routes._peers[self.route]
        with peer.lock:
            observations["local_epoch"] = peer.local.epoch if peer.local else 0
            observations["local_brokers"] = sorted(peer.local.receive_brokers) if peer.local else []
        return {"pid": os.getpid(), "ready": self.client.peer_routes.ready(self.route),
                "paths": self.client.path_snapshot()["paths"], **observations,
                "ingress": self.bridge.mqtt_ingress_status(), "inbox": inbox, "outbox": outbox,
                "errors": list(self.error_capture.errors),
                "messages": [{"id": row["message_id"] if row["direction"] == "outbound" else remote_ids[row["message_id"]],
                              "direction": row["direction"], "delivery_status": row["delivery_status"],
                              "route_ok": row["client_route_id"] == self.route,
                              "hash": hashlib.sha256(row["content"].encode()).hexdigest()} for row in rows]}

    def send(self, value):
        mid = value["message_id"]
        payload = {"type": "peer_message", "message_id": mid, "source_message_id": mid,
                   "contact_id": self.remote, "conversation_id": "owned-native-conversation",
                   "content": value["content"], "attachments": [], "time": time.time(), "peer_chat": True}
        if value.get("padding_bytes"):
            payload["owned_lab_padding"] = "x" * min(int(value["padding_bytes"]), 1_000_000)
        ok = self.bridge._publish_phone_payload(self.client, {"_client_route_id": self.route}, payload)
        return {"queued": bool(ok), "message_id": mid}

    def replay(self, value):
        from mqtt_broker_catalog import BROKER_IDS
        from link_protocol import seal_wire_packet
        wire = self.wires[value["message_id"]]
        topic = self.bridge._client_topics(self.route).send
        encoded = seal_wire_packet(json.dumps(wire), self.secret).encode()
        descriptor = self.client.peer_routes.classify(topic, encoded)
        if descriptor is None:
            raise ValueError("Replay path is not authenticated")
        ready = self.client.ready_path_generations(descriptor.receive_topics)
        for broker, generation in ready.items():
            selected = replace(descriptor, authorized_paths=((broker, generation),),
                               attempted_brokers=frozenset(BROKER_IDS) - {broker})
            info = self.client.publish(topic, encoded, publication=selected)
            if info.rc:
                raise RuntimeError("Replay rejected")
        return {"copies": len(ready), "packet_hash": hashlib.sha256(encoded).hexdigest()}

    def close(self):
        if self.client:
            self.client.disconnect()
            self.worker.join(12)
            if self.worker.is_alive() or not self.client.wait_closed(1):
                raise RuntimeError("MQTT workers did not stop")
            if not self.bridge._stop_inbound_route_workers(timeout=10):
                raise RuntimeError("Ingress workers did not stop")
        self.signal.stop_signal_sidecar()


def main():
    endpoint = None
    try:
        config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        endpoint = Endpoint(config)
        print(json.dumps({"boot": True, "bundle": endpoint.bundle, "pid": os.getpid()}), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            try:
                command = request["command"]
                if command == "configure":
                    result = endpoint.configure(request)
                elif command == "resume":
                    result = endpoint.start_transport()
                elif command == "snapshot":
                    result = endpoint.snapshot()
                elif command == "send":
                    result = endpoint.send(request)
                elif command == "send_peer":
                    result = endpoint.bridge.publish_peer_message(endpoint.route, request["content"])
                elif command == "replay":
                    result = endpoint.replay(request)
                elif command == "drop":
                    endpoint.drop_incoming = bool(request["enabled"])
                    result = {"drop": endpoint.drop_incoming}
                elif command == "hold":
                    result = endpoint.hold(bool(request["enabled"]))
                elif command == "shutdown":
                    break
                else:
                    raise ValueError("Unknown test command")
                print(json.dumps({"id": request["id"], "result": result}), flush=True)
            except Exception as error:
                logging.exception("Owned worker command failed")
                print(json.dumps({"id": request["id"], "error": type(error).__name__}), flush=True)
    finally:
        if endpoint:
            endpoint.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    main()
