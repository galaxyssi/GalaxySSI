"""Explicit operator enrollment, separate from ordinary Signal contact pairing."""
from __future__ import annotations

import hashlib
import json
import re
import time

from agent_run_kernel import AgentRunEventLedger
from agent_worker_leases import AgentWorkerLeaseLedger
from pairing_access import grant_binding


class WorkerAccessError(RuntimeError):
    pass


def _identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", value):
        raise WorkerAccessError("worker_identifier_invalid")
    return value


def _integer(value, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise WorkerAccessError("worker_capacity_or_epoch_invalid")
    return value


def _providers(values):
    if not isinstance(values, list) or not 1 <= len(values) <= 32:
        raise WorkerAccessError("worker_providers_invalid")
    return sorted({_identifier(value) for value in values})


def _binding(peer):
    if not isinstance(peer, dict) or peer.get("revoked"):
        raise WorkerAccessError("worker_pairing_unavailable")
    fields = ("client_route_id", "signal_name", "identity_fingerprint",
              "local_identity_fingerprint", "link_secret", "access_granted_at")
    if any(not peer.get(key) for key in fields):
        raise WorkerAccessError("worker_pairing_incomplete")
    data = {key: peer[key] for key in fields}
    data["access"] = grant_binding(peer)
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


class AgentWorkerRegistry:
    def __init__(self, ledger: AgentRunEventLedger):
        self.ledger = ledger
        self.leases = AgentWorkerLeaseLedger(ledger)
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_enrollments (
                route_id TEXT PRIMARY KEY, worker_id TEXT UNIQUE NOT NULL, binding TEXT NOT NULL,
                enabled INTEGER NOT NULL, max_parallel INTEGER NOT NULL, providers_json TEXT NOT NULL,
                session_epoch INTEGER NOT NULL DEFAULT 0, incarnation TEXT NOT NULL DEFAULT '',
                connect_id TEXT NOT NULL DEFAULT '', offered_json TEXT NOT NULL DEFAULT '[]',
                available_slots INTEGER NOT NULL DEFAULT 0, heartbeat_sequence INTEGER NOT NULL DEFAULT 0,
                last_seen_ms INTEGER NOT NULL DEFAULT 0
            )""")

    @staticmethod
    def _row(connection, route):
        row = connection.execute("SELECT * FROM agent_worker_enrollments WHERE route_id=?", (route,)).fetchone()
        if row is None:
            return None
        return dict(zip(("route_id", "worker_id", "binding", "enabled", "max_parallel", "providers_json",
                         "session_epoch", "incarnation", "connect_id", "offered_json", "available_slots",
                         "heartbeat_sequence", "last_seen_ms"), row))

    @staticmethod
    def _public(row):
        age = time.time_ns() // 1_000_000 - row["last_seen_ms"]
        connected = bool(row["enabled"] and row["incarnation"] and 0 <= age <= 30_000)
        return {key: row[key] for key in ("worker_id", "max_parallel", "session_epoch", "incarnation",
                "available_slots", "last_seen_ms")} | {
                    "enabled": bool(row["enabled"]), "providers": json.loads(row["providers_json"]),
                    "offered_providers": json.loads(row["offered_json"]),
                    "connected": connected, "available_slots": row["available_slots"] if connected else 0,
                }

    @staticmethod
    def _invalidate_leases(connection, worker_id):
        connection.execute("UPDATE agent_worker_leases SET state='revoked' WHERE worker_id=? AND state='active'",
                           (worker_id,))

    def enroll(self, peer, worker_id, *, max_parallel, providers):
        """Called only by the authenticated loopback operator API, never by MQTT."""
        binding, worker_id = _binding(peer), _identifier(worker_id)
        capacity = _integer(max_parallel, 1, 128)
        providers = _providers(providers)
        route = peer["client_route_id"]
        with self.ledger.transaction() as connection:
            row = self._row(connection, route)
            other = connection.execute("SELECT route_id FROM agent_worker_enrollments WHERE worker_id=?",
                                       (worker_id,)).fetchone()
            if (row and row["worker_id"] != worker_id) or (other and other[0] != route):
                raise WorkerAccessError("worker_identity_already_bound")
            if row is None and connection.execute("SELECT count(*) FROM agent_worker_enrollments").fetchone()[0] >= 10000:
                raise WorkerAccessError("worker_registry_full")
            self._invalidate_leases(connection, worker_id)
            epoch = row["session_epoch"] + 1 if row else 0
            connection.execute("""INSERT INTO agent_worker_enrollments
                (route_id, worker_id, binding, enabled, max_parallel, providers_json, session_epoch)
                VALUES (?, ?, ?, 1, ?, ?, ?) ON CONFLICT(route_id) DO UPDATE SET
                binding=excluded.binding, enabled=1, max_parallel=excluded.max_parallel,
                providers_json=excluded.providers_json, session_epoch=excluded.session_epoch,
                incarnation='', connect_id='', offered_json='[]', available_slots=0,
                heartbeat_sequence=0, last_seen_ms=0""",
                (route, worker_id, binding, capacity, json.dumps(providers), epoch))
            return self._public(self._row(connection, route))

    def revoke(self, route):
        with self.ledger.transaction() as connection:
            row = self._row(connection, route)
            if row is None:
                raise WorkerAccessError("worker_not_enrolled")
            self._invalidate_leases(connection, row["worker_id"])
            connection.execute("""UPDATE agent_worker_enrollments SET enabled=0, available_slots=0,
                session_epoch=session_epoch+1, incarnation='', connect_id='' WHERE route_id=?""", (route,))
            return self._public(self._row(connection, route))

    def _authorized(self, connection, peer, source):
        binding = _binding(peer)
        if source != peer["signal_name"]:
            raise WorkerAccessError("worker_source_mismatch")
        row = self._row(connection, peer["client_route_id"])
        if row is None or not row["enabled"] or row["binding"] != binding:
            raise WorkerAccessError("worker_not_authorized")
        return row

    def status(self, peer, source):
        with self.ledger.transaction(write=False) as connection:
            return self._public(self._authorized(connection, peer, source))

    def connect(self, peer, source, payload):
        incarnation = _identifier(payload.get("incarnation"))
        request_id = _identifier(payload.get("request_id"))
        expected = _integer(payload.get("expected_session_epoch"), 0, 2**53 - 2)
        offered = _providers(payload.get("providers"))
        with self.ledger.transaction() as connection:
            row = self._authorized(connection, peer, source)
            if not set(offered).issubset(json.loads(row["providers_json"])):
                raise WorkerAccessError("worker_provider_not_authorized")
            if request_id == row["connect_id"]:
                if (row["incarnation"] != incarnation or row["session_epoch"] != expected + 1
                        or json.loads(row["offered_json"]) != offered):
                    raise WorkerAccessError("worker_connect_id_reused")
                return self._public(row)
            if expected != row["session_epoch"]:
                raise WorkerAccessError("worker_session_epoch_changed")
            self._invalidate_leases(connection, row["worker_id"])
            connection.execute("""UPDATE agent_worker_enrollments SET session_epoch=session_epoch+1,
                incarnation=?, connect_id=?, offered_json=?, available_slots=0, heartbeat_sequence=0,
                last_seen_ms=? WHERE route_id=?""",
                (incarnation, request_id, json.dumps(offered), time.time_ns() // 1_000_000, row["route_id"]))
            return self._public(self._row(connection, row["route_id"]))

    def heartbeat(self, peer, source, payload):
        incarnation = _identifier(payload.get("incarnation"))
        epoch = _integer(payload.get("session_epoch"), 1, 2**53 - 1)
        sequence = _integer(payload.get("sequence"), 1, 2**53 - 1)
        with self.ledger.transaction() as connection:
            row = self._authorized(connection, peer, source)
            slots = _integer(payload.get("available_slots"), 0, row["max_parallel"])
            if row["incarnation"] != incarnation or row["session_epoch"] != epoch:
                raise WorkerAccessError("worker_session_stale")
            if sequence == row["heartbeat_sequence"] and slots == row["available_slots"]:
                return self._public(row)
            if sequence <= row["heartbeat_sequence"]:
                raise WorkerAccessError("worker_heartbeat_reordered")
            connection.execute("""UPDATE agent_worker_enrollments SET available_slots=?,
                heartbeat_sequence=?, last_seen_ms=? WHERE route_id=?""",
                (slots, sequence, time.time_ns() // 1_000_000, row["route_id"]))
            return self._public(self._row(connection, row["route_id"]))
