"""Owned cancellation fixture: real task ledger/dispatch, no model process."""
import threading
import uuid
import copy


class ControlEndpoint:
    def __init__(self, endpoint):
        self.endpoint = endpoint
        self.lock = threading.Lock()
        self.pending = {}
        self.tasks = set()
        self.timings = {}
        self.current_ack = threading.local()

    def install_ack_timing(self, bridge):
        actual_ack, actual_publish = bridge._ack_stored_application, bridge._publish_phone_payload

        def acknowledge(mqttc, wire, envelope, payload, trace, **kwargs):
            task_id = payload.get("task_id") if payload.get("type") == "agent_task_cancel" else None
            previous = getattr(self.current_ack, "task_id", None)
            previous_sample = getattr(self.current_ack, "sample", None)
            self.current_ack.task_id = task_id
            sample = {"duplicate": bool(kwargs.get("duplicate")), "stages": {}}
            self.current_ack.sample = sample
            if task_id in self.tasks:
                with self.lock:
                    timing = self.timings.setdefault(task_id, {"stages": {}, "reply_ids": []})
                    calls = timing.setdefault("ack_calls", [])
                    if len(calls) < 16:
                        calls.append(sample)
                    else:
                        timing["ack_calls_dropped"] = timing.get("ack_calls_dropped", 0) + 1
            self.stage(task_id, "ack_enter")
            try:
                return actual_ack(mqttc, wire, envelope, payload, trace, **kwargs)
            finally:
                self.stage(task_id, "ack_return")
                self.current_ack.task_id = previous
                self.current_ack.sample = previous_sample

        def publish(mqttc, wire, payload, *args, **kwargs):
            task_id = getattr(self.current_ack, "task_id", None) if payload.get("type") == "delivery_ack" else None
            self.stage(task_id, "signal_ack_enter")
            try:
                return actual_publish(mqttc, wire, payload, *args, **kwargs)
            finally:
                self.stage(task_id, "signal_ack_return")

        bridge._ack_stored_application, bridge._publish_phone_payload = acknowledge, publish

    def stage(self, task_id, name):
        if task_id in self.tasks:
            with self.lock:
                now = self.endpoint.measurements.clock()
                self.timings.setdefault(task_id, {"stages": {}, "reply_ids": []})["stages"].setdefault(
                    name, now)
                sample = getattr(self.current_ack, "sample", None)
                if sample is not None and getattr(self.current_ack, "task_id", None) == task_id:
                    sample["stages"].setdefault(name, now)

    def observe_envelope(self, envelope):
        payload = envelope.get("payload", {})
        if payload.get("type") == "delivery_ack":
            self.stage(getattr(self.current_ack, "task_id", None), "signal_ack_encrypt_enter")
        task_id = payload.get("task_id")
        if payload.get("type") == "agent_task_event" and task_id in self.tasks:
            self.stage(task_id, "reply_encrypt_enter")
            mid = envelope["message_id"]
            self.endpoint.measurements.begin(mid)
            with self.lock:
                self.timings[task_id]["reply_ids"].append(mid)

    def create(self):
        if len(self.tasks) >= 128:
            raise ValueError("Owned control task limit exceeded")
        case = uuid.uuid4().hex
        record = {"task_id": case, "conversation_id": "owned-control-" + case,
                  "turn_id": "turn-" + case, "source_message_id": str(uuid.uuid4()),
                  "client_route_id": self.endpoint.route, "contact_id": "owned-control"}
        # Empty agent ID prevents a provider cancel call. The production manager
        # still persists the task and the authenticated cancel runs unchanged.
        self.endpoint.bridge.agent_task_manager.create_external(
            agent_id="", contact_id=record["contact_id"], source_message_id=record["source_message_id"],
            prompt="Owned transport cancellation probe", on_event=lambda event: None,
            task_id=case, client_conversation_id=record["conversation_id"],
            client_route_id=record["client_route_id"], client_turn_id=record["turn_id"])
        self.tasks.add(case)
        return record

    def send(self, record):
        mid = str(uuid.uuid4())
        with self.lock:
            if len(self.pending) >= 128 or record["task_id"] in self.pending:
                raise ValueError("Owned control sample limit or duplicate task")
            self.pending[record["task_id"]] = {"record": dict(record), "message_id": mid, "events": []}
        self.endpoint.measurements.begin(mid)
        payload = {**record, "message_id": mid, "type": "agent_task_cancel"}
        ok = self.endpoint.bridge._publish_phone_payload(self.endpoint.client,
            {"_client_route_id": self.endpoint.route}, payload)
        return {"queued": bool(ok), "message_id": mid}

    def capture(self, payload):
        with self.lock:
            item = self.pending.get(payload.get("task_id"))
            if item is None or any(payload.get(key) != item["record"][key] for key in
                    ("task_id", "conversation_id", "turn_id", "source_message_id", "contact_id")):
                raise ValueError("Unexpected authenticated control event scope")
            if payload.get("task_status") != "cancelled":
                raise ValueError("Control probe did not return cancelled")
            if len(item["events"]) >= 8:
                raise ValueError("Excessive control event copies")
            item["events"].append(dict(payload))
            self.endpoint.measurements.stage(item["message_id"], "cancel_event_received")

    def command(self, value):
        operation = value["operation"]
        if operation == "diagnostics":
            with self.lock:
                return copy.deepcopy(self.timings)
        if operation == "create":
            return self.create()
        if operation == "send":
            return self.send(value["record"])
        if operation == "inspect":
            task_id = value["task_id"]
            if task_id not in self.tasks:
                raise ValueError("Not an owned control task")
            manager = self.endpoint.bridge.agent_task_manager
            task = manager.get(task_id)
            stored = manager._store.get(task_id)
            with self.lock:
                timing = copy.deepcopy(self.timings.get(task_id))
            return {"status": task.status, "stored_status": stored["status"],
                    "cancel_requested": task.cancel_requested, "timing": timing}
        raise ValueError("Unsupported owned control command")
