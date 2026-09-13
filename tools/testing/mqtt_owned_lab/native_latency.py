"""Owned native small-message latency: durable commit timestamps, not RPC polls."""
import argparse
import asyncio
from dataclasses import asdict
import hashlib
import json
import logging
from pathlib import Path
import random
import secrets
import time
import uuid

from native_measurements import summarize
from native_smoke import Worker
from owned_brokers import OwnedBrokers
from smoke import require, reject_bad_tls


def run(lab, loop, python, report_dir, samples, seed, fault_primary=False):
    if not 30 <= samples <= 180 or samples % 3:
        raise ValueError("Samples per strategy must be a multiple of three between 30 and 180")
    report_dir.mkdir(parents=True, exist_ok=True)
    reject_bad_tls(lab)
    workers, configs, completed = [], {}, []
    report = {"status": "running", "network": "owned_loopback_tls", "seed": seed,
              "samples_per_strategy": samples, "blocks": completed,
              "provisional_warm_p95_ratio_budget": 1.10,
              "fault_primary": fault_primary, "fault_observations": {},
              "provisional_fault_p95_budget_ms": 8000,
              "scope": "small native peer messages; not attachments, phone, UI or model latency"}
    expected = {}

    def create(label):
        config = lab.directory / f"{label}.json"
        config.write_text(json.dumps({"state": str(lab.directory / label), "ca": str(lab.directory / "ca.pem"),
            "measure": True, "endpoints": {key: asdict(value) for key, value in lab.endpoints.items()}}), encoding="utf-8")
        configs[label] = config
        worker = Worker(python, config, label)
        workers.append(worker)
        return worker

    def paths_ready(worker, paths):
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            state = worker.call("snapshot")
            current = {key for key, path in state["paths"].items()
                       if path["connected"] and path["active_subscriptions"]}
            if state["ready"] and current == paths and set(state["local_brokers"]) == paths:
                return state
            time.sleep(.05)
        raise AssertionError(f"{worker.label} authenticated paths did not converge: {state}")

    def select_paths(paths):
        for label in sorted(lab.endpoints):
            operation = None
            if label in paths and label not in lab.brokers:
                operation = lab.start(label)
            elif label not in paths and label in lab.brokers:
                operation = lab.stop(label)
            if operation is not None:
                asyncio.run_coroutine_threadsafe(operation, loop).result(timeout=15)

    def send(worker, *, blackhole=False):
        mid = str(uuid.uuid4())
        content = "owned-native-latency-" + mid
        if blackhole:
            primary = worker.call("plan_message", message_id=mid)["broker"]
            before = right.call("drop_broker", broker=primary)["dropped"]
        require(worker.call("send", message_id=mid, content=content)["queued"], "Message was not queued")
        expected[mid] = hashlib.sha256(content.encode()).hexdigest()
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            sample = worker.call("measurements", message_id=mid)
            if (sample and "receipt_committed" in sample["stages"]
                    and all(packet["accepted"] is not None for packet in sample["packets"].values())):
                if blackhole:
                    dropped = right.call("drop_broker", broker=None)["dropped"] - before
                    packets = sorted((p for p in sample["packets"].values() if p["accepted"]), key=lambda p: p["at_ns"])
                    require(packets[0]["broker"] == primary, "Primary changed after the fault preview")
                    require(dropped > 0 and len(packets) > 1 and any(p["broker"] != primary for p in packets),
                            "No actual primary loss and alternate physical send")
                    require(packets[0].get("broker_acked_ns", float("inf")) < sample["stages"]["receipt_committed"],
                            "Primary PUBACK did not precede the real durable receipt")
                    report["fault_observations"][mid] = {"primary": primary, "dropped_packets": dropped,
                        "primary_broker_acked": True, "alternate_submission": True}
                return mid
            time.sleep(.025)
        report["failed_message_id"] = mid
        report["censored_sample"] = sample
        raise AssertionError("No authenticated durable receipt within the observation window")

    def validate(receiver, sender):
        deadline = time.monotonic() + 25
        while True:
            state = receiver.call("snapshot")
            require(not state["errors"], f"Native ingress errors: {state['errors']}")
            messages = {row["id"]: row for row in state["messages"]}
            require(len(messages) == len(state["messages"]) and not (messages.keys() - expected.keys()),
                    "Unexpected or duplicate business row")
            dispatched = {row["id"] for row in state["inbox"] if row["state"] == "dispatched"}
            if messages.keys() == expected.keys() and expected.keys() <= dispatched:
                break
            require(time.monotonic() < deadline, "Durable receipt was not followed by completed business dispatch")
            time.sleep(.05)
        for mid, digest in expected.items():
            row = messages[mid]
            require(row["route_ok"] and row["hash"] == digest and row["direction"] == "inbound", "Business ownership/content mismatch")
            entries = [item for item in state["inbox"] if item["id"] == mid]
            require(len(entries) == 1 and entries[0]["state"] == "dispatched" and entries[0]["attempts"] == 1,
                    "Business dispatch was not exactly once")
        state = sender.call("snapshot")
        require(not state["errors"] and not state["outbox"], "Sender errors or unacknowledged durable messages")

    try:
        left, right = create("left"), create("right")
        secret = secrets.token_urlsafe(32)
        left.call("configure", bundle=right.boot["bundle"], route=secrets.token_urlsafe(16), secret=secret)
        right.call("configure", bundle=left.boot["bundle"], route=secrets.token_urlsafe(16), secret=secret)
        paths = set(lab.endpoints)
        for worker in workers:
            paths_ready(worker, paths)
        report["startup"] = {worker.label: worker.call("measurements")["startup_to_authenticated_ready_ms"] for worker in workers}
        report["policy_limits"] = {worker.label: worker.call("measurements")["policy_limits"] for worker in workers}
        blocks = [("single_available", {path}) for path in sorted(paths)] + [("automatic_multi", paths)] * 3
        random.Random(seed).shuffle(blocks)
        grouped = {"single_available": [], "automatic_multi": []}
        for index, (strategy, active) in enumerate(blocks):
            started = time.perf_counter()
            select_paths(active)
            for worker in workers:
                paths_ready(worker, active)
            warmup = send(left)
            block = {"index": index, "strategy": strategy, "paths": sorted(active), "warmup_id": warmup,
                     "transition_and_warmup_ms": (time.perf_counter() - started) * 1000, "message_ids": []}
            completed.append(block)
            for _ in range(samples // 3):
                mid = send(left, blackhole=fault_primary and strategy == "automatic_multi")
                block["message_ids"].append(mid)
                grouped[strategy].append(mid)
            # Business reads occur outside measured requests and must still pass.
            validate(right, left)
            print(json.dumps({"completed_block": index, "strategy": strategy, "samples": len(grouped[strategy])}), flush=True)
        measurements = left.call("measurements")["samples"]
        report["raw_samples"] = measurements
        report["results"] = {strategy: summarize([measurements[mid] for mid in ids]) for strategy, ids in grouped.items()}
        ratio = (report["results"]["automatic_multi"]["request_to_rx_stored_ms"]["p95"] /
                 report["results"]["single_available"]["request_to_rx_stored_ms"]["p95"])
        if fault_primary:
            require(len(report["fault_observations"]) == samples, "Incomplete primary-loss cohort")
            report["provisional_fault_gate"] = {"observed_p95_ms": report["results"]["automatic_multi"]["request_to_rx_stored_ms"]["p95"],
                "passed": report["results"]["automatic_multi"]["request_to_rx_stored_ms"]["p95"] <= report["provisional_fault_p95_budget_ms"]}
            report["provisional_small_message_gate"] = None
        else:
            report["provisional_small_message_gate"] = {"observed_p95_ratio": ratio,
                "passed": ratio <= report["provisional_warm_p95_ratio_budget"]}
        report["validated_business_messages"] = len(expected)
        report["status"] = "measured_with_business_checks_passed"
        report["release_performance_gate"] = "not_evaluated"
        return report
    except BaseException as error:
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
        for worker in workers:
            if worker.process.poll() is None:
                try:
                    report[worker.label + "_last_snapshot"] = worker.call("snapshot")
                    report[worker.label + "_measurements"] = worker.call("measurements")
                except Exception as snapshot_error:
                    report[worker.label + "_snapshot_error"] = type(snapshot_error).__name__
        raise
    finally:
        cleanup_errors = []
        for worker in reversed(workers):
            try:
                worker.stop()
            except Exception as error:
                cleanup_errors.append(str(error))
        for label, config in configs.items():
            if config.with_suffix(".log").exists():
                (report_dir / f"{label}.log").write_bytes(config.with_suffix(".log").read_bytes())
        if cleanup_errors:
            report["status"] = "failed"
            report["cleanup_errors"] = cleanup_errors
        (report_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        if cleanup_errors:
            raise AssertionError("; ".join(cleanup_errors))


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint-python", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260913)
    parser.add_argument("--fault-primary", action="store_true")
    args = parser.parse_args()
    async with OwnedBrokers() as lab:
        report = await asyncio.to_thread(run, lab, asyncio.get_running_loop(), args.endpoint_python,
                                        args.report_dir, args.samples, args.seed, args.fault_primary)
    print(json.dumps({key: value for key, value in report.items() if key not in {"raw_samples", "blocks"}}, indent=2))
    gate = report.get("provisional_fault_gate") or report["provisional_small_message_gate"]
    return 0 if gate["passed"] else 2


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    raise SystemExit(asyncio.run(main()))
