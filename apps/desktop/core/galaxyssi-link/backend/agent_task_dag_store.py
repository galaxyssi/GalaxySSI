"""Transactional DAG commands and recovery checkpoints in the existing Run ledger."""
from __future__ import annotations

import json
import hashlib

from agent_run_kernel import AgentRunEventLedger, AgentRunRootIdentity, AgentRunIdentityConflict
from agent_task_dag import TaskDagError, canonical, identifier, ready_nodes, reduce_graph


DAG_CHECKPOINT_KIND = "dynamic_task_dag_v1"
_EVENTS = {"create": "RUN_CREATED", "claim": "STEP_STARTED", "complete": "STEP_COMPLETED",
           "pause": "PAUSED", "resume": "RUN_RECOVERED", "cancel": "RUN_CANCELLED", "finish": "RUN_COMPLETED"}


class DurableTaskDag:
    def __init__(self, ledger: AgentRunEventLedger):
        self.ledger = ledger
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_task_dag_nodes (
                run_id TEXT NOT NULL, node_id TEXT NOT NULL, data_json TEXT NOT NULL,
                PRIMARY KEY(run_id, node_id), FOREIGN KEY(run_id) REFERENCES agent_run_roots(run_id)
            )""")

    def apply(self, identity: AgentRunRootIdentity, operation_id: str, command: dict, *, turn_id: str) -> dict:
        self._validate(identity)
        identifier(operation_id, "operation_id")
        identifier(turn_id, "turn_id")
        if not isinstance(command, dict):
            raise TaskDagError("DAG command must be an object")
        # Snapshot mutable caller input before waiting for the database writer lock.
        command = json.loads(canonical(command))
        fingerprint = hashlib.sha256(canonical(command).encode("utf-8")).hexdigest()
        idempotency_key = f"dag:{operation_id}"
        with self.ledger.transaction() as connection:
            replay = self.ledger.event_for_idempotency(identity.run_id, idempotency_key, connection=connection)
            if replay is not None:
                if replay.root_identity != identity or replay.turn_id != turn_id or replay.payload.get("dag_command_sha256") != fingerprint:
                    raise AgentRunIdentityConflict("DAG operation ID was reused with different scope or content")
                return self._replay(identity.run_id, replay.sequence, connection)
            self._require_scope(identity, connection)
            previous = self._read(identity.run_id, connection)
            graph = reduce_graph(previous, command, run_id=identity.run_id, operation_id=operation_id)
            old_nodes = previous["nodes"] if previous else {}
            changed = {key: node for key, node in graph["nodes"].items() if node != old_nodes.get(key)}
            removed = sorted(set(old_nodes) - set(graph["nodes"]))
            metadata = {key: value for key, value in graph.items() if key != "nodes"}
            self.ledger.append({
                **identity.public(), "turn_id": turn_id,
                "action_id": command.get("node_id") or operation_id,
                "idempotency_key": idempotency_key,
                "type": _EVENTS.get(command["operation"], "CHECKPOINT_SAVED"),
                "agent_id": "dag-coordinator", "device_id": "local",
                "payload": {"dag_command_sha256": fingerprint,
                            "dag_patch": {"nodes": changed, "removed": removed},
                            "projection_checkpoint": {"kind": DAG_CHECKPOINT_KIND, "data": metadata}},
            }, connection=connection)
            for key, node in changed.items():
                connection.execute("""INSERT INTO agent_task_dag_nodes VALUES (?, ?, ?)
                    ON CONFLICT(run_id, node_id) DO UPDATE SET data_json=excluded.data_json""",
                    (identity.run_id, key, canonical(node)))
            for key in removed:
                connection.execute("DELETE FROM agent_task_dag_nodes WHERE run_id=? AND node_id=?", (identity.run_id, key))
            return graph

    def load(self, identity: AgentRunRootIdentity) -> dict | None:
        self._validate(identity)
        with self.ledger.transaction(write=False) as connection:
            self._require_scope(identity, connection)
            return self._read(identity.run_id, connection)

    def ready(self, identity: AgentRunRootIdentity) -> list[str]:
        graph = self.load(identity)
        return ready_nodes(graph) if graph else []

    def recovery_page(self, *, limit: int = 64, before: tuple[int, str] | None = None) -> list[dict]:
        return self.ledger.checkpoints(DAG_CHECKPOINT_KIND, limit=limit, before=before, recoverable_only=True)

    def _require_scope(self, identity: AgentRunRootIdentity, connection) -> None:
        snapshot = self.ledger.snapshot(identity.run_id, connection=connection)
        if snapshot is not None and any(snapshot.get(key) != value for key, value in identity.public().items()):
            raise AgentRunIdentityConflict("Task graph belongs to another execution scope")

    @staticmethod
    def _read(run_id: str, connection) -> dict | None:
        row = connection.execute("SELECT data_json FROM agent_run_checkpoints WHERE run_id=? AND kind=?",
                                 (run_id, DAG_CHECKPOINT_KIND)).fetchone()
        if row is None:
            return None
        graph = json.loads(row[0])
        graph["nodes"] = {key: json.loads(data) for key, data in connection.execute(
            "SELECT node_id, data_json FROM agent_task_dag_nodes WHERE run_id=? ORDER BY node_id", (run_id,))}
        graph["nodes"] = dict(sorted(graph["nodes"].items(), key=lambda item: item[1]["position"]))
        return graph

    @staticmethod
    def _replay(run_id: str, through: int, connection) -> dict:
        # Duplicate operations return their original state, never another worker's newer lease.
        graph: dict = {"nodes": {}}
        cursor = connection.execute("""SELECT payload_json FROM agent_run_events
            WHERE run_id=? AND sequence<=? ORDER BY sequence""", (run_id, through))
        while rows := cursor.fetchmany(128):
            for (raw,) in rows:
                payload = json.loads(raw)
                patch = payload.get("dag_patch")
                if patch is None:
                    continue
                graph.update(payload["projection_checkpoint"]["data"])
                graph["nodes"].update(patch["nodes"])
                for key in patch["removed"]:
                    graph["nodes"].pop(key, None)
        return graph

    @staticmethod
    def _validate(identity: AgentRunRootIdentity) -> None:
        for key, value in identity.public().items():
            identifier(value, key)
