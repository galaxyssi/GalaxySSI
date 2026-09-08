"""Small opt-in TLS loopback probe on a unique topic, never on a user's routes."""
import argparse
import hashlib
import json
import secrets
import threading
import time

import paho.mqtt.client as mqtt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="broker.emqx.io")
    parser.add_argument("--port", type=int, default=8883)
    parser.add_argument("--sizes", default="1024,21883,349563")
    parser.add_argument("--timeout", type=float, default=25)
    args = parser.parse_args()
    topic = "galaxyssi-diagnostics/" + secrets.token_hex(24)
    subscribed = threading.Event()
    received = threading.Event()
    expected = [b""]
    clients = []

    def emit(**fields):
        print(json.dumps(fields), flush=True)

    def on_message(client, userdata, message):
        if hashlib.sha256(message.payload).digest() == expected[0]:
            received.set()

    try:
        for role in ("receiver", "sender"):
            client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                                 client_id="gssi-probe-" + secrets.token_hex(8),
                                 clean_session=True)
            client.tls_set()
            client.on_disconnect = lambda c, u, f, rc, p: emit(event="disconnect", reason=str(rc))
            if role == "receiver":
                client.on_connect = lambda c, u, f, rc, p: c.subscribe(topic, qos=1)
                client.on_subscribe = lambda c, u, mid, codes, p: subscribed.set() if all(int(str(code.value)) < 128 for code in codes) else None
                client.on_message = on_message
            client.connect(args.host, args.port, keepalive=30)
            client.loop_start()
            clients.append(client)
        if not subscribed.wait(args.timeout):
            raise TimeoutError("SUBACK timeout")
        for size in map(int, args.sizes.split(",")):
            if not 0 < size <= 1024 * 1024:
                raise ValueError("Probe size must be 1..1 MiB")
            payload = secrets.token_bytes(size)
            expected[0] = hashlib.sha256(payload).digest()
            received.clear()
            started = time.monotonic()
            info = clients[1].publish(topic, payload, qos=1, retain=False)
            info.wait_for_publish(timeout=args.timeout)
            ack = info.is_published()
            ack_ms = round((time.monotonic() - started) * 1000)
            delivered = received.wait(max(0, args.timeout - (time.monotonic() - started)))
            emit(bytes=size, broker_ack=ack, broker_ms=ack_ms,
                 received=delivered, elapsed_ms=round((time.monotonic() - started) * 1000))
            if not ack or not delivered:
                break
    finally:
        for client in clients:
            client.disconnect()
            client.loop_stop()


if __name__ == "__main__":
    main()
