"""Owned sockets + two independent native Signal/SQLite Desktop business endpoints."""
import argparse
import asyncio
from dataclasses import asdict
import hashlib
import json
import logging
import os
from pathlib import Path
import queue
import secrets
import subprocess
import threading
import time
import uuid

from owned_brokers import OwnedBrokers
from smoke import require, reject_bad_tls


class Worker:
    def __init__(self, python, config, label):
        self.python, self.config, self.label = python, config, label
        self.sequence = 0
        self.output = queue.Queue(maxsize=256)
        self.log = config.with_suffix(".log").open("ab")
        self.process = subprocess.Popen([str(python), str(Path(__file__).with_name("native_worker.py")), str(config)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, text=True, encoding="utf-8",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.boot = self._response(35)
            require(self.boot.get("boot"), "Endpoint did not boot")
        except BaseException:
            self.stop(crash=True)
            raise

    def _read(self):
        try:
            for line in self.process.stdout:
                self.output.put(json.loads(line), timeout=5)
        except Exception as error:
            self.output.put({"error": type(error).__name__}, timeout=5)
        finally:
            self.output.put({"terminal": True}, timeout=5)

    def _response(self, timeout):
        try:
            result = self.output.get(timeout=timeout)
        except queue.Empty as error:
            raise AssertionError(f"{self.label} RPC timed out; process={self.process.poll()}") from error
        if result.get("error") or result.get("terminal"):
            raise AssertionError(f"{self.label} RPC failed: {result}; log={self.config.with_suffix('.log')}")
        return result

    def call(self, command, **values):
        self.sequence += 1
        self.process.stdin.write(json.dumps({"id": self.sequence, "command": command, **values}) + "\n")
        self.process.stdin.flush()
        response = self._response(30)
        require(response.get("id") == self.sequence, "Mismatched local control response")
        return response["result"]

    def stop(self, *, crash=False):
        if self.process.poll() is None:
            if crash:
                self._kill_tree()
            else:
                self.process.stdin.write(json.dumps({"id": 0, "command": "shutdown"}) + "\n")
                self.process.stdin.flush()
                try:
                    self.process.wait(timeout=35)
                except subprocess.TimeoutExpired:
                    self._kill_tree()
                    raise AssertionError(f"{self.label} did not stop gracefully")
                require(self.process.returncode == 0, f"{self.label} cleanup failed")
        self.reader.join(5)
        self.log.close()

    def _kill_tree(self):
        if os.name == "nt":
            subprocess.run(["taskkill.exe", "/PID", str(self.process.pid), "/T", "/F"],
                           capture_output=True, timeout=20, check=True,
                           creationflags=subprocess.CREATE_NO_WINDOW)
        else:
            # Parent-side kill support is deliberately Windows-only until the
            # child process-group and JVM ownership path is implemented elsewhere.
            raise RuntimeError("Native crash scenario currently requires Windows")
        self.process.wait(timeout=10)


def run(lab, loop, python, report_dir, delay_resume=False, offline_peer_entry=False, path_cycles=0,
        defer_after_selection=False):
    if not 0 <= path_cycles <= 100:
        raise ValueError("Path cycles must be between 0 and 100")
    reject_bad_tls(lab)
    workers = []
    observations = []
    expected = {"left": {}, "right": {}}
    configs = {}
    last_snapshots = {}

    def create(label):
        config = lab.directory / f"{label}.json"
        config.write_text(json.dumps({"state": str(lab.directory / label), "ca": str(lab.directory / "ca.pem"),
                                     "endpoints": {key: asdict(value) for key, value in lab.endpoints.items()}}), encoding="utf-8")
        configs[label] = config
        worker = Worker(python, config, label)
        workers.append(worker)
        return worker

    def wait_state(worker, predicate, label, timeout=25):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = worker.call("snapshot")
            last_snapshots[worker.label] = last
            if predicate(last):
                return last
            time.sleep(.05)
        raise AssertionError(f"{label}: {json.dumps(last)}")

    def ready(worker, paths):
        return wait_state(worker, lambda state: state["ready"] and
            {key for key, path in state["paths"].items() if path["connected"] and path["active_subscriptions"]} == set(paths),
            "Authenticated common paths not ready")

    def delivered(worker, mid):
        return wait_state(worker, lambda state: any(row["id"] == mid for row in state["messages"])
                          and any(row["id"] == mid and row["state"] == "dispatched" for row in state["inbox"]),
                          f"Business row missing: {mid}")

    def received_once(state, mid, content):
        matches = [row for row in state["messages"] if row["id"] == mid]
        require(len(matches) == 1 and matches[0]["route_ok"] and matches[0]["direction"] == "inbound"
                and matches[0]["hash"] == hashlib.sha256(content.encode()).hexdigest(), "Wrong/duplicate business content")
        inbox = [row for row in state["inbox"] if row["id"] == mid]
        require(len(inbox) == 1 and inbox[0]["state"] == "dispatched" and inbox[0]["attempts"] == 1,
                "Business dispatch was not exactly one completed attempt")

    def accepted(sender, mid):
        return wait_state(sender, lambda state: not any(row["id"] == mid for row in state["outbox"]),
                          "Durable sender queue not acknowledged")

    def enqueue(sender, content, padding=0):
        mid = str(uuid.uuid4())
        require(sender.call("send", message_id=mid, content=content, padding_bytes=padding)["queued"], "Send not queued")
        return mid

    def send(sender, receiver, label, *, padding=0):
        content = "owned-native-" + label
        started = time.perf_counter()
        mid = enqueue(sender, content, padding)
        expected[receiver.label][mid] = content
        try:
            state = delivered(receiver, mid)
        except AssertionError:
            last_snapshots[sender.label] = sender.call("snapshot")
            raise
        received_once(state, mid, content)
        accepted(sender, mid)
        observations.append({"case": label, "complete_ms": round((time.perf_counter()-started)*1000, 3)})
        print(json.dumps({"completed_case": label, "business_messages": sum(map(len, expected.values()))}), flush=True)
        return mid, content

    def broker(label, start):
        future = asyncio.run_coroutine_threadsafe(lab.start(label) if start else lab.stop(label), loop)
        future.result(timeout=15)

    try:
        left, right = create("left"), create("right")
        secret = secrets.token_urlsafe(32)
        left.call("configure", bundle=right.boot["bundle"], route=secrets.token_urlsafe(16), secret=secret)
        right.call("configure", bundle=left.boot["bundle"], route=secrets.token_urlsafe(16), secret=secret)
        paths = set(lab.endpoints)
        ready(left, paths)
        ready(right, paths)
        if delay_resume:
            left.call("hold", enabled=True)
            broker("emqx", False)
            held = wait_state(left, lambda value: value["local_brokers"] == ["hivemq", "mosquitto"]
                and any(ack["epoch"] == value["local_epoch"] and ack["broker"] != "emqx"
                        for ack in value["held_resume_acks"]), "Old resume ACK was not delayed")
            old_epoch = held["local_epoch"]
            broker("emqx", True)
            wait_state(left, lambda value: set(value["local_brokers"]) == paths and value["local_epoch"] > old_epoch,
                       "Resume epoch did not rotate before delayed delivery")
            require(left.call("hold", enabled=False)["released"] > 0, "No delayed MQTT packets released")
            ready(left, paths)
            ready(right, paths)
            state = wait_state(left, lambda value: value["ingress"]["active"] == 0 and value["ingress"]["pending"] == 0,
                               "Delayed resume ingress did not drain")
            require(not state["errors"], f"Delayed resume caused ingress errors: {state['errors']}")
            observations.append({"case": "late-resume-ack-after-path-rotation", "old_epoch_ignored": True})
        first, first_content = send(left, right, "native-prekey")
        send(right, left, "native-ratchet-reply")
        if defer_after_selection:
            mid, content = str(uuid.uuid4()), "owned-native-subscription-loss-after-selection"
            require(left.call("send", message_id=mid, content=content, pause_before_publish=True)["queued"],
                    "Unsent message was not accepted into the durable outbox")
            expected["right"][mid] = content
            state = left.call("snapshot")
            last_snapshots["left"] = state
            require(state["paused_publications"] == 1 and not state["ready"], "Subscription fault was not exercised")
            require(not any(item["id"] == mid for item in state["broker_pending"]), "Unsent message owns a ghost broker token")
            queued = [item for item in state["outbox"] if item["id"] == mid]
            require(len(queued) == 1 and queued[0]["state"] == "queued" and queued[0]["attempts"] == 0,
                    "Unsent selection consumed retry budget or did not return to the queue")
            require(not any(row["id"] == mid for row in right.call("snapshot")["messages"]),
                    "Unsent message was incorrectly delivered")
            left.call("restore_subscriptions")
            ready(left, paths)
            received_once(delivered(right, mid), mid, content)
            accepted(left, mid)
            observations.append({"case": "subscription-loss-after-selection", "same_message_recovered": True,
                                 "ghost_broker_tokens": 0, "unsent_retry_attempts": 0})
        replay = left.call("replay", message_id=first)
        require(replay["copies"] == 3, "Did not publish three real MQTT copies")
        state = wait_state(right, lambda value: set(value["wire_observed"].get(replay["packet_hash"], {})) == paths
            and value["ingress"]["active"] == 0 and value["ingress"]["pending"] == 0, "Three replay copies not drained")
        received_once(state, first, first_content)
        observations.append({"case": "three-path-replay", "dispatch_attempts": 1, "observed_brokers": sorted(paths)})

        # Force wire fragmentation without pretending the ignored padding is a real attachment.
        send(left, right, "fragmented-native-envelope", padding=450_000)
        broker("emqx", False)
        ready(left, {"hivemq", "mosquitto"})
        ready(right, {"hivemq", "mosquitto"})
        send(left, right, "one-path-down")
        send(right, left, "one-path-down-reply")

        # All MQTT packets still traverse TLS/PUBACK; discard callback ingress on
        # the sender so no application or attempt receipt can retire its outbox.
        left.call("drop", enabled=True)
        content = "owned-native-ack-loss"
        mid = enqueue(left, content)
        expected["right"][mid] = content
        received_once(delivered(right, mid), mid, content)
        state = wait_state(left, lambda value: value["dropped"] > 0, "ACK loss fault was not exercised")
        require(any(row["id"] == mid for row in state["outbox"]), "Broker ACK incorrectly retired business outbox")
        identities = {item.label: item.boot["bundle"]["identityKeySha256"] for item in (left, right)}
        old_pids = {item.label: item.process.pid for item in (left, right)}
        left.stop(crash=True)
        right.stop(crash=True)
        left, right = create("left"), create("right")
        for item in (left, right):
            require(item.boot["bundle"]["identityKeySha256"] == identities[item.label], "Restart changed Signal identity")
            require(item.process.pid != old_pids[item.label], "Process restart was not exercised")
            item.call("resume")
        ready(left, {"hivemq", "mosquitto"})
        ready(right, {"hivemq", "mosquitto"})
        accepted(left, mid)
        received_once(right.call("snapshot"), mid, content)
        observations.append({"case": "lost-receipt-two-endpoint-process-death", "dispatch_attempts": 1,
                             "identities_preserved": True, "outbox_recovered": True})
        send(right, left, "native-ratchet-after-process-death")

        broker("hivemq", False)
        broker("mosquitto", False)
        for item in (left, right):
            wait_state(item, lambda value: not any(path["connected"] for path in value["paths"].values()), "All-path outage not observed")
        content = "owned-native-all-offline"
        queued_id = enqueue(left, content)
        expected["right"][queued_id] = content
        require(any(row["id"] == queued_id for row in left.call("snapshot")["outbox"]), "Offline outbox was not persisted")
        require(not any(row["id"] == queued_id for row in right.call("snapshot")["messages"]), "Offline message unexpectedly delivered")
        broker("emqx", True)
        ready(left, {"emqx"})
        ready(right, {"emqx"})
        received_once(delivered(right, queued_id), queued_id, content)
        accepted(left, queued_id)
        observations.append({"case": "all-path-outage-single-path-recovery", "queued_id_preserved": True})
        for label in ("hivemq", "mosquitto"):
            broker(label, True)
        ready(left, paths)
        ready(right, paths)
        send(left, right, "all-paths-restored")
        for cycle in range(path_cycles):
            failed = sorted(paths)[cycle % len(paths)]
            broker(failed, False)
            ready(left, paths - {failed})
            ready(right, paths - {failed})
            send(left, right, f"rotation-{cycle + 1}-{failed}-down")
            send(right, left, f"rotation-{cycle + 1}-{failed}-reply")
            broker(failed, True)
            ready(left, paths)
            ready(right, paths)
            send(left, right, f"rotation-{cycle + 1}-{failed}-restored")
        for item in (left, right):
            state = item.call("snapshot")
            require(not state["errors"], f"Unexpected native ingress errors: {state['errors']}")
            require(len(state["messages"]) == len(expected[item.label]), "Unexpected business row")
            for mid, content in expected[item.label].items():
                received_once(state, mid, content)
        if offline_peer_entry:
            # This API targets Android, not another Desktop. Validate its durable
            # acceptance here without weakening the Desktop receiver's target check.
            for label in paths:
                broker(label, False)
            wait_state(left, lambda value: not any(path["connected"] for path in value["paths"].values()),
                       "Send entry outage not observed")
            content = "owned-native-offline-desktop-to-phone"
            result = left.call("send_peer", content=content)
            require(result["ok"] and result["queued"] and result["message"]["delivery_status"] == "queued",
                    f"Offline send entry falsely failed or delivered: {result}")
            mid = result["message_id"]
            notifications = []
            for kind in ("agent", "diagnostic"):
                queued = left.call("notify", kind=kind, content="owned-offline-" + kind)
                require(queued["ok"] and queued["queued"] and not queued["delivered"], "Notification acceptance incorrect")
                notifications.append(queued["deliveries"][0]["message_id"])
            before = left.call("snapshot")
            require(any(row["id"] == mid for row in before["outbox"]), "Send entry did not persist ciphertext")
            hashes = {row["id"]: row["wire_hash"] for row in before["outbox"]}
            require(all(message in hashes for message in notifications), "Notification ciphertext was not persisted")
            identity = left.boot["bundle"]["identityKeySha256"]
            left.stop(crash=True)
            left = create("left")
            require(left.boot["bundle"]["identityKeySha256"] == identity, "Send entry restart changed identity")
            left.call("resume")
            after = left.call("snapshot")
            require(any(row["id"] == mid for row in after["outbox"]), "Send entry outbox lost on process death")
            require(hashes == {row["id"]: row["wire_hash"] for row in after["outbox"]}, "Offline ciphertext changed or was lost")
            rows = [row for row in after["messages"] if row["id"] == mid]
            require(len(rows) == 1 and rows[0]["delivery_status"] == "queued" and rows[0]["route_ok"]
                    and rows[0]["direction"] == "outbound"
                    and rows[0]["hash"] == hashlib.sha256(content.encode()).hexdigest(),
                    "Send entry card lost, duplicated or falsely delivered after process death")
            require(not after["errors"], f"Offline send entry ingress errors: {after['errors']}")
            observations.append({"case": "desktop-send-entry-offline-process-death",
                                 "accepted_and_persisted": True, "phone_delivery_tested": False})
            observations.append({"case": "agent-and-diagnostic-offline-process-death",
                                 "persisted_messages": len(notifications), "ciphertext_preserved": True,
                                 "phone_delivery_tested": False})
        return {"status": "passed", "native_signal": True, "real_contact_store": True,
                "business_messages": sum(map(len, expected.values())),
                "path_cycles": path_cycles,
                "desktop_offline_send_entry_tested": offline_peer_entry, "observations": observations}
    finally:
        failures = []
        for item in reversed(workers):
            try:
                item.stop()
            except Exception as error:
                failures.append(str(error))
        report_dir.mkdir(parents=True, exist_ok=True)
        (report_dir / "last-snapshots.json").write_text(json.dumps(last_snapshots, indent=2), encoding="utf-8")
        for label, config in configs.items():
            if config.with_suffix(".log").exists():
                (report_dir / f"{label}.log").write_bytes(config.with_suffix(".log").read_bytes())
        if failures:
            raise AssertionError("; ".join(failures))


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint-python", type=Path, required=True, help="Python with Desktop backend requirements")
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--delay-resume", action="store_true", help="Hold real resume ACKs across a path change")
    parser.add_argument("--offline-peer-entry", action="store_true", help="Verify Desktop-to-phone offline enqueue and process recovery")
    parser.add_argument("--path-cycles", type=int, default=0, help="Repeat owned broker loss/recovery, rotating all three paths (0-100)")
    parser.add_argument("--defer-after-selection", action="store_true", help="Withdraw real subscriptions after outbox selection, then recover")
    args = parser.parse_args()
    async with OwnedBrokers() as lab:
        report = await asyncio.to_thread(run, lab, asyncio.get_running_loop(), args.endpoint_python, args.report_dir,
                                        args.delay_resume, args.offline_peer_entry, args.path_cycles, args.defer_after_selection)
    (args.report_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    asyncio.run(main())
