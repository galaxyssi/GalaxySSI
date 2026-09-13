"""Owned native-Signal Desktop attachment-ingress acceptance, not Android UI."""
import argparse
import asyncio
from dataclasses import asdict
import json
import logging
from pathlib import Path
import random
import secrets
import time

from native_smoke import Worker
from owned_brokers import OwnedBrokers
from smoke import require, reject_bad_tls


def run(lab, loop, python, report_dir, large=False):
    report_dir.mkdir(parents=True, exist_ok=True)
    reject_bad_tls(lab)
    workers, configs, active = [], {}, {}
    report = {"status": "running", "network": "owned_loopback_tls", "cases": [],
              "scope": "real Desktop native Signal/input attachment/contact store; phone payload/receipt consumer fixture",
              "android_tested": False, "ui_tested": False, "performance_gate": "not_evaluated"}
    routes = {name: secrets.token_urlsafe(16) for name in ("left", "right")}

    def create(label):
        config = lab.directory / (label + ".json")
        config.write_text(json.dumps({"state": str(lab.directory / label), "ca": str(lab.directory / "ca.pem"),
            "endpoints": {key: asdict(value) for key, value in lab.endpoints.items()}, "attachments": True}), encoding="utf-8")
        configs[label] = config
        worker = Worker(python, config, label)
        workers.append(worker)
        active[label] = worker
        return worker

    def wait(worker, command, predicate, *, timeout=45, **values):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = worker.call(command, **values)
            if predicate(last):
                return last
            time.sleep(.1)
        raise AssertionError(f"{worker.label} {command} timeout: {json.dumps(last)}")

    def ready(worker, paths):
        return wait(worker, "snapshot", lambda state: state["ready"] and
            {key for key, value in state["paths"].items() if value["connected"] and value["active_subscriptions"]} == set(paths))

    def broker(label, start):
        asyncio.run_coroutine_threadsafe(lab.start(label) if start else lab.stop(label), loop).result(timeout=15)

    try:
        left, right = create("left"), create("right")
        secret = secrets.token_urlsafe(32)
        left.call("configure", bundle=right.boot["bundle"], route=routes["left"], secret=secret)
        right.call("configure", bundle=left.boot["bundle"], route=routes["right"], secret=secret)
        paths = set(lab.endpoints)
        ready(left, paths)
        ready(right, paths)
        cases = [("png", 0), ("video", 0)]
        if large:
            cases += [("file", size * 1024 * 1024) for size in (5, 21, 32)]
        for kind, size in cases:
            item = left.call("attachment", operation="prepare", kind=kind, size=size, receiver_route=routes["right"])
            manifest, case = item["manifest"], item["case"]
            result = {"kind": kind, "size": manifest["size_bytes"], "sha256": manifest["sha256"],
                      "chunk_count": manifest["chunk_count"], "message_id": item["message_id"], "windows": 0}
            report["cases"].append(result)
            started = time.monotonic()
            response = left.call("attachment", operation="manifest", case=case)
            require(response["queued"], "Manifest not durably accepted")
            receipt = wait(left, "attachment", lambda value: value is not None,
                           operation="receipt", transfer_id=manifest["transfer_id"])
            before = right.call("attachment", operation="inspect", manifest=manifest, message_id=item["message_id"])
            require(not before["complete"], "Missing attachment was presented as complete")
            first_chunk_id = None
            while receipt["status"] != "stored":
                require(receipt["status"] == "missing", f"Invalid transfer receipt: {receipt}")
                indices = [index for first, last in receipt["missing_ranges"] for index in range(first, last + 1)]
                require(0 < len(indices) <= 16, "Unbounded attachment request window")
                random.Random(result["windows"]).shuffle(indices)
                prior_bytes = receipt["received_bytes"]
                for index in indices:
                    sent = left.call("attachment", operation="chunk", case=case, index=index)
                    require(sent["queued"], "Chunk not durably accepted")
                    first_chunk_id = first_chunk_id or sent["message_id"]
                receipt = wait(left, "attachment", lambda value: value and
                    (value["status"] == "stored" or value["received_bytes"] > prior_bytes),
                    operation="receipt", transfer_id=manifest["transfer_id"])
                result["windows"] += 1
                print(json.dumps({"attachment": kind, "bytes": manifest["size_bytes"],
                    "received_bytes": receipt["received_bytes"], "windows": result["windows"]}), flush=True)
                if size == 21 * 1024 * 1024 and result["windows"] == 1:
                    # Persisted incomplete file bytes must survive a real receiver
                    # process death; do not recreate the transfer or re-send stored blocks.
                    identity = right.boot["bundle"]["identityKeySha256"]
                    right.stop(crash=True)
                    right = create("right")
                    require(identity == right.boot["bundle"]["identityKeySha256"], "Receiver identity changed")
                    right.call("resume")
                    ready(left, paths)
                    ready(right, paths)
                    broker("emqx", False)
                    paths.remove("emqx")
                    ready(left, paths)
                    ready(right, paths)
                    result["receiver_restarted"] = True
                    result["broker_stopped"] = "emqx"
                    copies = left.call("replay", message_id=first_chunk_id)
                    replayed = wait(right, "snapshot", lambda state:
                        sum(state["wire_observed"].get(copies["packet_hash"], {}).values()) >= copies["copies"] and
                        state["ingress"]["pending"] == state["ingress"]["active"] == 0)
                    row = next(row for row in replayed["inbox"] if row["id"] == first_chunk_id)
                    require(row["state"] == "dispatched" and row["attempts"] == 1, "Completed chunk repeated after restart")
                    result["completed_chunk_replayed_after_restart"] = True
            require(receipt["sha256"] == manifest["sha256"] and receipt["received_bytes"] == manifest["size_bytes"],
                    "Complete receipt does not match source")
            require(left.call("attachment", operation="peer", case=case)["queued"], "Contact message not durably accepted")
            received = wait(right, "attachment", lambda value: value["complete"] and value["business_rows"] == 1,
                            operation="inspect", manifest=manifest, message_id=item["message_id"])
            require(received["sha256"] == received["stream_sha256"] == manifest["sha256"], "Attachment bytes changed")
            require(received["size"] == received["stream_size"] == manifest["size_bytes"], "Attachment length changed")
            require(received["route_ok"] and len(received["attachments"]) == 1 and received["attachments"][0]["available"],
                    "Wrong route or duplicate/unavailable attachment")
            state = wait(left, "snapshot", lambda value: not value["outbox"])
            require(not state["errors"], "Sender native ingress error")
            receiver = right.call("snapshot")
            require(not receiver["errors"], "Receiver native ingress error")
            rows = [row for row in receiver["inbox"] if row["id"] == item["message_id"]]
            require(len(rows) == 1 and rows[0]["attempts"] == 1 and rows[0]["state"] == "dispatched", "Duplicate contact dispatch")
            if kind in {"png", "video"}:
                require(received.get("media_valid") is True, "Received media failed decoding")
                result["media"] = received.get("video", {"image_size": received.get("image_size")})
            result.update(status="passed", complete_seconds=round(time.monotonic() - started, 3),
                          hash_verified=True, one_available_attachment=True, receive_storage=receiver["receive_storage"])
            print(json.dumps({"completed_attachment": result}), flush=True)
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
        snapshots = {}
        for label, worker in active.items():
            if str(error).startswith(label + " RPC"):
                snapshots[label] = {"snapshot_error": "RPC stream is not synchronized; no second request issued"}
                continue
            try:
                snapshots[label] = worker.call("snapshot")
            except Exception as snapshot_error:
                snapshots[label] = {"snapshot_error": str(snapshot_error)}
        (report_dir / "failure-snapshots.json").write_text(json.dumps(snapshots, indent=2), encoding="utf-8")
        raise
    finally:
        failures = []
        for worker in reversed(workers):
            try:
                worker.stop()
            except Exception as error:
                failures.append(str(error))
        report["cleanup_errors"] = failures
        if failures:
            report["status"] = "failed"
        (report_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        for label, config in configs.items():
            if config.with_suffix(".log").exists():
                (report_dir / (label + ".log")).write_bytes(config.with_suffix(".log").read_bytes())
        if failures:
            raise AssertionError("; ".join(failures))
    return report


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint-python", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--large", action="store_true")
    args = parser.parse_args()
    async with OwnedBrokers() as lab:
        report = await asyncio.to_thread(run, lab, asyncio.get_running_loop(), args.endpoint_python, args.report_dir, args.large)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    asyncio.run(main())
