"""Leased CI watches and meaningful transitions in the shared Run ledger."""
from __future__ import annotations

import json
from contextlib import nullcontext

from agent_run_kernel import AgentRunEventLedger
from .common import stable_json, sha256_text
from .ci_snapshot import target
from .ci_owner import CiOwnerLocks, OWNER_PATTERN, OwnerLockUnavailable


class CiLeaseLost(RuntimeError):
    pass


class CiWatchStore:
    def __init__(self, ledger: AgentRunEventLedger):
        self.ledger = ledger
        self.owner_locks = CiOwnerLocks(ledger.path.parent / (ledger.path.name + ".ci-owners"))
        with ledger.transaction() as connection:
            connection.execute("""CREATE TABLE IF NOT EXISTS evolution_ci_watches (
                task_id TEXT PRIMARY KEY, url TEXT NOT NULL, data_json TEXT NOT NULL,
                next_poll INTEGER NOT NULL, owner TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0
            )""")
            connection.execute("CREATE INDEX IF NOT EXISTS evolution_ci_due ON evolution_ci_watches(next_poll, task_id)")

    def register(self, task_id: str, url: str) -> None:
        target(url)
        data = {"task_id": task_id, "url": url, "status": "watching", "repair": None}
        with self.ledger.transaction() as connection:
            old = connection.execute("SELECT url FROM evolution_ci_watches WHERE task_id=?", (task_id,)).fetchone()
            if old:
                if old[0] != url:
                    raise ValueError("CI watch task identity cannot be rebound to another PR")
                return
            connection.execute("INSERT INTO evolution_ci_watches(task_id,url,data_json,next_poll) VALUES(?,?,?,0)",
                               (task_id, url, stable_json(data)))
            self._event(connection, data)

    def get(self, task_id: str) -> dict | None:
        with self.ledger.transaction() as connection:
            row = connection.execute("SELECT data_json FROM evolution_ci_watches WHERE task_id=?", (task_id,)).fetchone()
            return json.loads(row[0]) if row else None

    def claim_due(self, now: int, owner: str, *, limit: int = 4, lease_millis: int = 600_000) -> list[dict]:
        claimed = []
        with self.ledger.transaction() as connection:
            rows = connection.execute("""SELECT task_id, data_json, owner, lease_until, next_poll
                FROM evolution_ci_watches WHERE next_poll>=0 AND (next_poll<=? OR owner<>'')
                ORDER BY next_poll,task_id""", (now,))
            for task_id, raw, previous_owner, expires, due in rows:
                os_owned = OWNER_PATTERN.fullmatch(previous_owner) is not None
                if not os_owned and (expires > now or due > now):
                    continue
                try:
                    guard = (self.owner_locks.hold(previous_owner)
                             if os_owned and previous_owner != owner else nullcontext(True))
                    # Hold the abandoned owner's lock through the SQL update to prevent a check/use race.
                    with guard as abandoned:
                        if not abandoned:
                            continue
                        connection.execute("UPDATE evolution_ci_watches SET owner=?,lease_until=? WHERE task_id=?",
                                           (owner, now + lease_millis, task_id))
                        claimed.append(json.loads(raw))
                except OwnerLockUnavailable:
                    # Inaccessible or missing ownership evidence is not proof of process death.
                    continue
                if len(claimed) >= max(1, limit):
                    break
            return claimed

    def save(self, data: dict, owner: str, now: int, *, next_poll: int, release: bool = True) -> None:
        with self.ledger.transaction() as connection:
            old = connection.execute("""SELECT data_json FROM evolution_ci_watches
                WHERE task_id=? AND owner=? AND lease_until>?""", (data["task_id"], owner, now)).fetchone()
            if old is None:
                raise CiLeaseLost("CI observation lease expired or was replaced")
            if stable_json(json.loads(old[0])) != stable_json(data):
                self._event(connection, data)
            connection.execute("""UPDATE evolution_ci_watches SET data_json=?, next_poll=?, owner=?, lease_until=?
                WHERE task_id=?""", (stable_json(data), next_poll, "" if release else owner,
                0 if release else now + 600_000, data["task_id"]))

    def _event(self, connection, data: dict) -> None:
        task_id = data["task_id"]
        run_id = f"ci-watch:{task_id}"
        root = self.ledger.snapshot(run_id, connection=connection)
        # Repeated states can recur after a rerun, so sequence participates in event identity.
        sequence = (root["last_sequence"] if root else 0) + 1
        self.ledger.append({"client_route_id": "desktop-local", "conversation_id": run_id,
            "goal_id": task_id, "task_id": task_id, "run_id": run_id, "turn_id": run_id,
            "action_id": "ci-observation", "agent_id": "evolution-ci", "device_id": "local",
            "type": "CHECKPOINT_SAVED", "idempotency_key": f"ci:{sequence}:{sha256_text(stable_json(data))}",
            "payload": {"projection_checkpoint": {"kind": "evolution_ci_watch_v1", "data": data}}}, connection=connection)
