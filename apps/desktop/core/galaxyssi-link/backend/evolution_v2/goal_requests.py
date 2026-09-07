"""Initial goal requests projected from the shared Run event ledger."""
from __future__ import annotations

import json
import uuid

from agent_task_dag import TaskDagError, canonical, identifier
from .campaign_owner import campaign_operation
from .common import now_millis, sha256_text


GOAL_KIND = "evolution_goal_request_v1"


class GoalRequests:
    def __init__(self, durable):
        self.durable = durable
        self.ledger = durable.graph_store.ledger
        self.operation_owners = durable.operation_owners

    def load(self, campaign_id):
        identifier(campaign_id, "campaign_id")
        with self.ledger.transaction(write=False) as db:
            self.durable.graph_store._require_scope(self.durable.identity(campaign_id), db)
            row = db.execute("SELECT data_json FROM agent_run_checkpoints WHERE run_id=? AND kind=?",
                             (campaign_id, GOAL_KIND)).fetchone()
            return json.loads(row[0]) if row else None

    def pending(self):
        before = None
        while True:
            page = self.ledger.checkpoints(GOAL_KIND, limit=64, before=before, recoverable_only=True)
            if not page:
                return
            for item in page:
                value = item["data"]
                if value["status"] not in {"paused", "cancelled", "materialized", "waiting"}:
                    yield value
            last = page[-1]
            before = (last["updated_at_millis"], last["run_id"])

    def page(self, limit=64, before=None):
        rows = self.ledger.checkpoints(GOAL_KIND, limit=limit, before=before)
        cursor = {"before_updated_at": rows[-1]["updated_at_millis"], "before_id": rows[-1]["run_id"]} if len(rows) == limit else None
        return {"goals": [self.public(row["data"]) for row in rows], "next_cursor": cursor}

    def create(self, request_id, name, objective, *, auto_start=False):
        identifier(request_id, "request_id")
        if not isinstance(name, str) or not name.strip() or not isinstance(objective, str) or not objective.strip():
            raise TaskDagError("A goal requires a name and objective")
        if type(auto_start) is not bool:
            raise TaskDagError("auto_start must be boolean")
        campaign_id = "campaign-goal-" + sha256_text(request_id)[:32]
        return self._create(campaign_id, request_id, name, objective, auto_start)

    @campaign_operation
    def _create(self, campaign_id, request_id, name, objective, auto_start):
        request = {"request_id": request_id, "name": name, "objective": objective, "auto_start": auto_start}
        existing = self.load(campaign_id)
        if existing is not None:
            if any(existing[key] != value for key, value in request.items()):
                raise TaskDagError("Goal request ID was reused with different content")
            return existing
        value = {**request, "campaign_id": campaign_id, "status": "requested", "revision": 1,
                 "created_at_millis": now_millis(), "next_poll": 0}
        self._write(value, "RUN_CREATED", "goal-request")
        return value

    def _write(self, value, event_type="CHECKPOINT_SAVED", operation_id=None):
        campaign_id = value["campaign_id"]
        self.ledger.append({**self.durable.identity(campaign_id).public(), "turn_id": campaign_id,
            "action_id": "goal-decomposition", "idempotency_key": operation_id or "goal-" + uuid.uuid4().hex,
            "type": event_type, "agent_id": "local-goal-planner", "device_id": "local",
            "payload": {"projection_checkpoint": {"kind": GOAL_KIND, "data": value}}})

    @campaign_operation
    def update(self, campaign_id, expected_revision, **fields):
        current = self.load(campaign_id)
        if current is None or current["revision"] != expected_revision:
            raise TaskDagError("Goal changed while planning")
        if current["status"] in {"paused", "cancelled", "materialized"}:
            raise TaskDagError("Goal no longer accepts planning observations")
        value = {**current, **fields, "revision": current["revision"] + 1}
        self._write(value, {"reasoning": "PLANNING", "waiting": "WAITING_FOR_USER"}.get(value["status"], "CHECKPOINT_SAVED"))
        return value

    @campaign_operation
    def control(self, campaign_id, operation, context=""):
        current = self.load(campaign_id)
        if current is None:
            raise TaskDagError("Goal was not found")
        if self.durable.graph_store.load(self.durable.identity(campaign_id)) is not None:
            raise TaskDagError("Goal already has a DAG; use campaign controls")
        if current["status"] == "cancelled":
            raise TaskDagError("Goal is cancelled")
        if operation not in {"pause", "resume", "cancel"}:
            raise TaskDagError("Unknown goal control operation")
        value = {**current, "revision": current["revision"] + 1,
                 "status": {"pause": "paused", "resume": "requested", "cancel": "cancelled"}[operation], "next_poll": 0}
        if context:
            value["context"] = context
            value.pop("decision", None)
            value.pop("validation_feedback", None)
        self._write(value, {"pause": "PAUSED", "resume": "RUN_RECOVERED", "cancel": "RUN_CANCELLED"}[operation])
        return value

    @staticmethod
    def public(value):
        return {key: value[key] for key in ("campaign_id", "name", "objective", "status", "revision",
            "auto_start", "reason", "error_type", "next_poll") if key in value}
