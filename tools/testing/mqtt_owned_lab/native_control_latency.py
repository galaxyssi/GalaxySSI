"""Real native cancellations during owned attachment ingress, without models/UI."""
import argparse
import asyncio
from dataclasses import asdict
import json
import logging
import math
from pathlib import Path
import secrets
import time

from native_measurements import summarize
from native_smoke import Worker
from owned_brokers import OwnedBrokers
from smoke import reject_bad_tls, require


def control_summary(samples):
    result = summarize(samples)
    values = sorted((sample["stages"]["cancel_event_received"] - sample["stages"]["started"]) / 1e6
                    for sample in samples)
    require(all(value >= 0 for value in values), "Invalid cancellation clock order")
    result["request_to_cancel_event_ms"] = {"p50": values[math.ceil(len(values) * .5) - 1],
        "p95": values[math.ceil(len(values) * .95) - 1], "max": values[-1]}
    return result


def overlapping_chunks(control, chunks):
    started = control["stages"]["started"]
    return [mid for mid, sample in chunks.items() if sample["stages"].get("queued", float("inf")) <= started
            < sample["stages"].get("receipt_committed", float("inf"))]


def run(lab, loop, python, report_dir, single_path=None):
    report_dir.mkdir(parents=True, exist_ok=True)
    reject_bad_tls(lab)
    workers, configs, cohorts, all_controls = [], {}, {"idle": [], "attachment_active": []}, []
    report = {"status": "running", "network": "owned_loopback_tls", "samples_per_cohort": 30,
        "single_available_path": single_path, "cohorts": cohorts, "overlap": {},
        "raw_samples": {}, "receiver_control_timings": {}, "control_tasks": {},
        "scope": "real native Signal, durable cancel dispatch/task ledger and Desktop attachment ingress; no model or Android",
        "attachment_sender_traffic": "Desktop MESSAGE classification of phone-shaped input_attachment_chunk, not Android CHUNK",
        "provisional_loaded_cancel_p95_budget_ms": 8000, "release_gate": "not_evaluated"}

    def create(label):
        config = lab.directory / (label + ".json")
        config.write_text(json.dumps({"state": str(lab.directory / label), "ca": str(lab.directory / "ca.pem"),
            "endpoints": {key: asdict(value) for key, value in lab.endpoints.items()},
            "attachments": True, "controls": True, "measure": True}), encoding="utf-8")
        configs[label] = config
        worker = Worker(python, config, label)
        workers.append(worker)
        return worker

    def wait(worker, command, predicate, timeout=45, **values):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            last = worker.call(command, **values)
            if predicate(last):
                return last
            time.sleep(.05)
        raise AssertionError(f"{worker.label} {command} observation timeout: {json.dumps(last)}")

    def cancel(record, cohort, chunks=()):
        response = left.call("control", operation="send", record=record)
        require(response["queued"], "Cancel not durably queued")
        mid = response["message_id"]
        all_controls.append((mid, record))
        if cohort:
            cohorts[cohort].append(mid)
        sample = wait(left, "measurements", lambda value: value and
            {"receipt_committed", "cancel_event_received"} <= value["stages"].keys() and
            all(packet["accepted"] is not None for packet in value["packets"].values()), message_id=mid)
        report["raw_samples"][mid] = sample
        report["control_tasks"][mid] = record["task_id"]
        state = right.call("control", operation="inspect", task_id=record["task_id"])
        report["receiver_control_timings"][record["task_id"]] = state["timing"]
        require(state["status"] == state["stored_status"] == "cancelled" and state["cancel_requested"],
                "Task cancellation was not persisted")
        if chunks:
            measurements = left.call("measurements")["samples"]
            overlap = overlapping_chunks(sample, {key: measurements[key] for key in chunks})
            report["overlap"][mid] = overlap
            require(overlap, "Loaded control had no queued unacknowledged attachment chunks at its start")
        return mid

    try:
        if single_path:
            require(single_path in lab.endpoints, "Unknown owned path")
            for name in lab.endpoints:
                if name != single_path:
                    asyncio.run_coroutine_threadsafe(lab.stop(name), loop).result(timeout=15)
        left, right = create("left"), create("right")
        routes = {label: secrets.token_urlsafe(16) for label in ("left", "right")}
        secret = secrets.token_urlsafe(32)
        left.call("configure", bundle=right.boot["bundle"], route=routes["left"], secret=secret)
        right.call("configure", bundle=left.boot["bundle"], route=routes["right"], secret=secret)
        active = {single_path} if single_path else set(lab.endpoints)
        for worker in workers:
            wait(worker, "snapshot", lambda value: value["ready"] and set(value["local_brokers"]) == active)
        report["startup"] = {worker.label: worker.call("measurements")["startup_to_authenticated_ready_ms"]
                             for worker in workers}
        report["warmup_id"] = cancel(right.call("control", operation="create"), None)
        for index in range(30):
            cancel(right.call("control", operation="create"), "idle")
            if (index + 1) % 10 == 0:
                print(json.dumps({"cohort": "idle", "completed": index + 1}), flush=True)
        wait(left, "snapshot", lambda value: not value["outbox"])
        item = left.call("attachment", operation="prepare", kind="file", size=32 * 1024 * 1024,
                         receiver_route=routes["right"])
        manifest, case = item["manifest"], item["case"]
        attachment_started = time.monotonic()
        require(left.call("attachment", operation="manifest", case=case)["queued"], "Manifest not queued")
        receipt = wait(left, "attachment", lambda value: value is not None, operation="receipt",
                       transfer_id=manifest["transfer_id"])
        submitted = set()
        while receipt["status"] != "stored":
            require(receipt["status"] == "missing", "Invalid attachment receipt")
            indices = [index for start, end in receipt["missing_ranges"] for index in range(start, end + 1)]
            require(0 < len(indices) <= 16 and not submitted.intersection(indices),
                    "Invalid or stale attachment window")
            for offset in range(0, len(indices), 4):
                measured = len(cohorts["attachment_active"]) < 30
                record = right.call("control", operation="create") if measured else None
                chunk_ids = []
                for index in indices[offset:offset + 4]:
                    response = left.call("attachment", operation="chunk", case=case, index=index)
                    require(response["queued"], "Attachment chunk not queued")
                    chunk_ids.append(response["message_id"])
                    submitted.add(index)
                if measured:
                    cancel(record, "attachment_active", chunk_ids)
                    print(json.dumps({"cohort": "attachment_active", "completed": len(cohorts["attachment_active"]),
                                      "submitted_chunks": len(submitted)}), flush=True)
            receipt = wait(left, "attachment", lambda value: value and (value["status"] == "stored" or
                value["received_bytes"] >= len(submitted) * manifest["chunk_size_bytes"]),
                operation="receipt", transfer_id=manifest["transfer_id"])
        require(len(cohorts["attachment_active"]) == 30, "Incomplete loaded cancellation cohort")
        require(receipt["sha256"] == manifest["sha256"] and receipt["received_bytes"] == manifest["size_bytes"],
                "Complete attachment receipt does not match source")
        require(left.call("attachment", operation="peer", case=case)["queued"], "Contact artifact not queued")
        artifact = wait(right, "attachment", lambda value: value["complete"] and value["business_rows"] == 1,
                        operation="inspect", manifest=manifest, message_id=item["message_id"])
        require(artifact["sha256"] == artifact["stream_sha256"] == manifest["sha256"] and
                artifact["size"] == artifact["stream_size"] == manifest["size_bytes"] and artifact["route_ok"] and
                len(artifact["attachments"]) == 1 and artifact["attachments"][0]["available"], "Invalid artifact")
        report["attachment"] = {"bytes": manifest["size_bytes"], "sha256": manifest["sha256"],
            "chunks": len(submitted), "controller_complete_seconds": time.monotonic() - attachment_started,
            "exact_one_available_artifact": True}
        for worker in workers:
            state = wait(worker, "snapshot", lambda value: not value["outbox"] and
                         value["ingress"]["pending"] == value["ingress"]["active"] == 0)
            require(not state["errors"], "Native ingress errors")
            if worker is right:
                for mid, _ in all_controls:
                    rows = [row for row in state["inbox"] if row["id"] == mid]
                    require(len(rows) == 1 and rows[0]["attempts"] == 1 and rows[0]["state"] == "dispatched",
                            "Cancellation dispatch duplicated or not completed")
        measurements = left.call("measurements")["samples"]
        report["raw_samples"] = measurements
        report["receiver_control_timings"] = right.call("control", operation="diagnostics")
        report["receiver_reply_measurements"] = right.call("measurements")
        report["control_tasks"] = {mid: record["task_id"] for mid, record in all_controls}
        report["results"] = {key: control_summary([measurements[mid] for mid in mids]) for key, mids in cohorts.items()}
        p95 = report["results"]["attachment_active"]["request_to_cancel_event_ms"]["p95"]
        report["provisional_gate"] = {"passed": p95 <= report["provisional_loaded_cancel_p95_budget_ms"],
                                      "observed_loaded_cancel_p95_ms": p95}
        report["status"] = "measured_with_business_checks_passed"
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        for worker in workers:
            if str(error).startswith(worker.label + " RPC"):
                continue
            try:
                report[worker.label + "_last_snapshot"] = worker.call("snapshot")
                report[worker.label + "_measurements"] = worker.call("measurements")
            except Exception as capture_error:
                report[worker.label + "_snapshot_error"] = str(capture_error)
        raise
    finally:
        errors = []
        for worker in reversed(workers):
            try:
                worker.stop()
            except Exception as error:
                errors.append(str(error))
        report["cleanup_errors"] = errors
        if errors:
            report["status"] = "failed"
        for label, config in configs.items():
            if config.with_suffix(".log").exists():
                (report_dir / (label + ".log")).write_bytes(config.with_suffix(".log").read_bytes())
        (report_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        if errors:
            raise AssertionError("; ".join(errors))
    return report


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint-python", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--single-path", choices=("emqx", "hivemq", "mosquitto"))
    args = parser.parse_args()
    async with OwnedBrokers() as lab:
        report = await asyncio.to_thread(run, lab, asyncio.get_running_loop(), args.endpoint_python,
                                        args.report_dir, args.single_path)
    print(json.dumps({key: value for key, value in report.items() if key not in {"raw_samples", "cohorts", "overlap"}}, indent=2))
    return 0 if report["provisional_gate"]["passed"] else 2


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    raise SystemExit(asyncio.run(main()))
