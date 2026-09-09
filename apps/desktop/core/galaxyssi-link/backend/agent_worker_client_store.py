"""Write-before-send intents for the explicitly activated worker controller."""
import json
import uuid

from agent_worker_local import WorkerExecutionFenced
from agent_worker_leases import _canonical
from agent_worker_rpc import MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES


class WorkerClientStore:
    def __init__(self, ledger):
        self.ledger = ledger
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_client_state (
                singleton INTEGER PRIMARY KEY CHECK(singleton=1), owner TEXT NOT NULL,
                route TEXT NOT NULL, binding TEXT NOT NULL, state TEXT NOT NULL, checkpoint TEXT NOT NULL
            )""")
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_client_intents (
                slot TEXT PRIMARY KEY, owner TEXT NOT NULL, request_id TEXT NOT NULL,
                operation TEXT NOT NULL, request_json TEXT NOT NULL, response_json TEXT NOT NULL DEFAULT ''
            )""")

    def open(self, owner, route, binding, checkpoint):
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT state FROM agent_worker_client_state WHERE singleton=1").fetchone()
            if row and row[0] != "closed":
                raise WorkerExecutionFenced("worker_client_recovery_required")
            connection.execute("DELETE FROM agent_worker_client_intents")
            connection.execute("""INSERT INTO agent_worker_client_state VALUES (1, ?, ?, ?, 'open', ?)
                ON CONFLICT(singleton) DO UPDATE SET owner=excluded.owner, route=excluded.route,
                binding=excluded.binding, state='open', checkpoint=excluded.checkpoint""",
                (owner, route, binding, _canonical(checkpoint)))

    @staticmethod
    def _owner(connection, owner):
        row = connection.execute("SELECT owner, state FROM agent_worker_client_state WHERE singleton=1").fetchone()
        if row is None or row[0] != owner or row[1] != "open":
            raise WorkerExecutionFenced("worker_client_owner_fenced")

    def intent(self, owner, slot, operation, fields):
        encoded = _canonical(fields)
        if len(encoded.encode()) > MAX_REQUEST_BYTES - 512:
            raise WorkerExecutionFenced("worker_client_request_too_large")
        with self.ledger.transaction() as connection:
            self._owner(connection, owner)
            row = connection.execute("SELECT owner, request_id, operation, request_json FROM agent_worker_client_intents WHERE slot=?",
                                     (slot,)).fetchone()
            if row:
                if row[0] != owner or row[2] != operation or row[3] != encoded:
                    raise WorkerExecutionFenced("worker_client_intent_reused")
                return row[1]
            if connection.execute("SELECT count(*) FROM agent_worker_client_intents").fetchone()[0] >= 32:
                raise WorkerExecutionFenced("worker_client_intents_full")
            request_id = uuid.uuid4().hex
            connection.execute("INSERT INTO agent_worker_client_intents VALUES (?, ?, ?, ?, ?, '')",
                               (slot, owner, request_id, operation, encoded))
            return request_id

    def received(self, owner, slot, payload):
        encoded = _canonical(payload)
        if len(encoded.encode()) > MAX_RESPONSE_BYTES:
            raise WorkerExecutionFenced("worker_client_response_too_large")
        with self.ledger.transaction() as connection:
            self._owner(connection, owner)
            used = connection.execute("""SELECT COALESCE(sum(length(CAST(request_json AS BLOB)) +
                CASE WHEN slot=? THEN 0 ELSE length(CAST(response_json AS BLOB)) END), 0)
                FROM agent_worker_client_intents""", (slot,)).fetchone()[0]
            if used + len(encoded.encode()) > 2 * 1024 * 1024:
                raise WorkerExecutionFenced("worker_client_response_budget_full")
            if connection.execute("""UPDATE agent_worker_client_intents SET response_json=?
                WHERE slot=? AND owner=?""", (encoded, slot, owner)).rowcount != 1:
                raise WorkerExecutionFenced("worker_client_intent_missing")

    def consume(self, owner, slot, checkpoint):
        with self.ledger.transaction() as connection:
            self._owner(connection, owner)
            connection.execute("UPDATE agent_worker_client_state SET checkpoint=? WHERE singleton=1", (_canonical(checkpoint),))
            connection.execute("DELETE FROM agent_worker_client_intents WHERE slot=? AND owner=?", (slot, owner))

    def close(self, owner, *, clean, checkpoint):
        with self.ledger.transaction() as connection:
            self._owner(connection, owner)
            connection.execute("UPDATE agent_worker_client_state SET state=?, checkpoint=? WHERE singleton=1",
                               ("closed" if clean else "recovery_required", _canonical(checkpoint)))
            if clean:
                connection.execute("DELETE FROM agent_worker_client_intents WHERE owner=?", (owner,))

    def read(self):
        with self.ledger.transaction(write=False) as connection:
            row = connection.execute("SELECT owner, route, binding, state, checkpoint FROM agent_worker_client_state WHERE singleton=1").fetchone()
            pending = connection.execute("SELECT count(*) FROM agent_worker_client_intents").fetchone()[0]
        return None if row is None else dict(owner=row[0], route=row[1], binding=row[2], state=row[3], checkpoint=json.loads(row[4]), pending=pending)
