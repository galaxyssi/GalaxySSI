"""A bounded public-broker connectivity smoke, NOT a throughput or peer-delivery test."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import secrets
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "apps/desktop/core/galaxyssi-link/backend"))
from mqtt_broker_pool import BrokerPool


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "build/reports/mqtt-multipath/public-smoke.json")
    args = parser.parse_args()
    topic = f"isolated-mqtt-diagnostic/{secrets.token_hex(16)}/loopback"
    payload = json.dumps({"kind": "connectivity_smoke", "nonce": secrets.token_hex(16)}).encode()
    started = time.monotonic()
    lock = threading.RLock()
    state: dict[str, dict] = {}
    sent: set[str] = set()

    def on_state(ingress, status, reason):
        with lock:
            row = state.setdefault(ingress.broker_id, {})
            row["state"] = status
            if reason:
                row["last_error"] = reason
            if status == "connected":
                row.setdefault("connect_ms", round((time.monotonic() - started) * 1000))

    def on_subscribed(ingress, topics, accepted):
        with lock:
            if not accepted or topic not in topics or ingress.broker_id in sent:
                return
            sent.add(ingress.broker_id)
            row = state.setdefault(ingress.broker_id, {})
            row["subscribe_ms"] = round((time.monotonic() - started) * 1000)
            row["sent_at"] = time.monotonic()
        pool.publish(ingress.broker_id, ingress.generation, topic, payload, attempt_id=ingress.broker_id)

    def on_packet(ingress, received_topic, data):
        if received_topic != topic or data != payload:
            return
        with lock:
            row = state[ingress.broker_id]
            row["loopback_ms"] = round((time.monotonic() - row["sent_at"]) * 1000)
            row["payload_verified"] = True

    def on_publish(receipt):
        with lock:
            state.setdefault(receipt.physical.broker_id, {})["broker_acked"] = receipt.broker_acked

    pool = BrokerPool(on_state=on_state, on_subscribed=on_subscribed, on_packet=on_packet, on_publish=on_publish)
    pool.subscribe({topic: 1})
    pool.start()
    try:
        deadline = started + 20
        while time.monotonic() < deadline:
            with lock:
                if sum(bool(row.get("payload_verified")) for row in state.values()) == 3:
                    break
            time.sleep(0.1)
        snapshot = pool.snapshot()
        with lock:
            observations = {broker: dict(row) for broker, row in state.items()}
    finally:
        pool.close()
    with lock:
        result = {"test": "public_broker_low_volume_loopback", "selection": "automatic",
                  "note": "One synthetic packet per connected broker; not application delivery or performance evidence.",
                  "sent_packets": len(sent), "payload_bytes": len(payload), "paths": observations, "snapshot": snapshot}
        for row in observations.values():
            row.pop("sent_at", None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
