"""Operator-approved App routing and original-recipient disclosure boundaries."""
import json
import threading

from agent_worker_registry import WorkerAccessError, _binding, _identifier

_LOCK = threading.RLock()


class WorkerAppRouting:
    def __init__(self, protocol, get_peer):
        self.protocol, self.get_peer = protocol, get_peer
        self.ledger = protocol.ledger
        with self.ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_app_routes (
                app TEXT PRIMARY KEY, binding TEXT NOT NULL, enabled INTEGER NOT NULL,
                targets TEXT NOT NULL)""")
            connection.execute("""CREATE TABLE IF NOT EXISTS agent_worker_origins (
                task_id TEXT PRIMARY KEY, app TEXT NOT NULL, binding TEXT NOT NULL)""")

    def _app(self, route):
        from pairing_access import has_full_executor
        value = self.get_peer(route)
        binding = _binding(value)
        if value["client_route_id"] != route or not has_full_executor(value):
            raise WorkerAccessError("worker_app_routing_not_authorized")
        return binding

    def configure(self, app, routes):
        _identifier(app)
        if (not isinstance(routes, list) or not 1 <= len(routes) <= 128
                or not all(isinstance(route, str) for route in routes) or len(set(routes)) != len(routes)):
            raise WorkerAccessError("worker_targets_required")
        routes = sorted(_identifier(route) for route in routes)
        binding = self._app(app)
        targets = []
        with self.ledger.transaction() as connection:
            if (not connection.execute("SELECT 1 FROM agent_worker_app_routes WHERE app=?", (app,)).fetchone()
                    and connection.execute("SELECT count(*) FROM agent_worker_app_routes").fetchone()[0] >= 10000):
                raise WorkerAccessError("worker_app_routes_full")
            for route in routes:
                peer = self.get_peer(route)
                if not peer:
                    raise WorkerAccessError("worker_pairing_unavailable")
                row = self.protocol.registry._authorized(connection, peer, peer["signal_name"])
                if route == app or "codex" not in json.loads(row["providers_json"]):
                    raise WorkerAccessError("worker_target_not_authorized")
                targets.append([route, row["worker_id"], row["binding"]])
            connection.execute("""INSERT INTO agent_worker_app_routes VALUES (?, ?, 1, ?)
                ON CONFLICT(app) DO UPDATE SET binding=excluded.binding, enabled=1, targets=excluded.targets""",
                (app, binding, json.dumps(targets)))
        return {"enabled": True, "provider": "codex", "worker_routes": routes}

    def status(self, app):
        with self.ledger.transaction(write=False) as connection:
            row = connection.execute("SELECT binding, enabled, targets FROM agent_worker_app_routes WHERE app=?", (app,)).fetchone()
        if not row:
            return {"enabled": False, "provider": "codex", "worker_routes": []}
        return {"enabled": bool(row[1]), "provider": "codex", "worker_routes": [value[0] for value in json.loads(row[2])]}

    def disable(self, app):
        with self.ledger.transaction() as connection:
            connection.execute("UPDATE agent_worker_app_routes SET enabled=0 WHERE app=?", (app,))
        return self.status(app)

    def enabled(self, app):
        with self.ledger.transaction(write=False) as connection:
            row = connection.execute("SELECT enabled FROM agent_worker_app_routes WHERE app=?", (app,)).fetchone()
        return bool(row and row[0])

    def admit(self, record):
        app = record["client_route_id"]
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT binding, enabled, targets FROM agent_worker_app_routes WHERE app=?", (app,)).fetchone()
            if not row or not row[1]:
                return False
            if self._app(app) != row[0]:
                raise WorkerAccessError("worker_app_pairing_changed")
            targets = []
            for route, worker_id, binding in json.loads(row[2]):
                peer = self.get_peer(route)
                try:
                    current = self.protocol.registry._authorized(connection, peer, peer["signal_name"] if peer else "")
                except WorkerAccessError:
                    continue
                if current["worker_id"] == worker_id and current["binding"] == binding and "codex" in json.loads(current["providers_json"]):
                    targets.append(worker_id)
            if not targets:
                raise WorkerAccessError("worker_routing_targets_unavailable")
            self.protocol.queue.enqueue(record, provider="codex", allowed_workers=targets, connection=connection)
            origin = connection.execute("SELECT app, binding FROM agent_worker_origins WHERE task_id=?", (record["task_id"],)).fetchone()
            if origin and origin != (app, row[0]):
                raise WorkerAccessError("worker_origin_conflict")
            connection.execute("INSERT OR IGNORE INTO agent_worker_origins VALUES (?, ?, ?)", (record["task_id"], app, row[0]))
            self.protocol._notify(connection, record)
        return True

    def can_receive(self, task_id, peer):
        with self.ledger.transaction(write=False) as connection:
            row = connection.execute("SELECT app, binding FROM agent_worker_origins WHERE task_id=?", (task_id,)).fetchone()
        if not row:
            return True
        try:
            return peer["client_route_id"] == row[0] and self._app(row[0]) == row[1] and _binding(peer) == row[1]
        except (WorkerAccessError, TypeError, KeyError):
            return False


def routing_for(bridge, *, create=False):
    from agent_run_kernel import AgentRunEventLedger
    from agent_worker_mqtt import worker_protocol
    ledger = getattr(getattr(bridge.agent_task_manager, "_run_events", None), "ledger", None)
    if not isinstance(ledger, AgentRunEventLedger):
        return None
    with _LOCK:
        cached = getattr(bridge, "_worker_app_routing_cache", None)
        path = str(ledger.path.resolve())
        if cached is not None and cached[0] == path and (cached[1] is not None or not create):
            return cached[1]
        with ledger.transaction(write=False) as connection:
            exists = connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='agent_worker_app_routes'").fetchone()
        result = WorkerAppRouting(worker_protocol(bridge), bridge.get_client) if create or exists else None
        bridge._worker_app_routing_cache = (path, result)
        return result


def recipient_allowed(bridge, task_id, peer):
    if not task_id:
        return True
    routing = routing_for(bridge)
    return routing is None or routing.can_receive(task_id, peer)
