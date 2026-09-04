"""Durable proactive task scheduling for GalaxySSI Desktop.

The scheduler intentionally separates triggers from actions. Cron, interval,
goal checkpoint, webhook, and manual triggers can run an Agent, a bounded
sub-agent team, a saved workflow, or a native tool without coupling those
concepts to one another.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import socket
import sqlite3
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field, replace
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Mapping
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


PROTOCOL = "galaxyssi.proactive-task.v1"
TRIGGER_KINDS = {"manual", "cron", "interval", "goal_checkpoint", "webhook"}
ACTION_KINDS = {
    "agent",
    "headless_swarm",
    "subagent_team",
    "workflow",
    "native_tool",
}
TEAM_ROLES = {
    "lead",
    "coordinator",
    "executor",
    "specialist",
    "observer",
    "verifier",
}
MISFIRE_POLICIES = {"skip", "fire_once", "catch_up"}
RUN_STATUSES = {
    "queued",
    "running",
    "waiting",
    "retrying",
    "completed",
    "failed",
    "cancelled",
    "skipped",
}
TERMINAL_RUN_STATUSES = {"completed", "failed", "cancelled", "skipped"}
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_MONTH_NAMES = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}
_WEEKDAY_NAMES = {
    "sun": 0,
    "mon": 1,
    "tue": 2,
    "wed": 3,
    "thu": 4,
    "fri": 5,
    "sat": 6,
}


class ProactiveTaskError(RuntimeError):
    def __init__(self, code: str, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


@dataclass(frozen=True)
class ProactiveTrigger:
    kind: str
    cron: str = ""
    time_zone: str = "UTC"
    interval_seconds: int = 0
    goal_id: str = ""
    webhook_id: str = ""
    event_filter: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def parse(cls, raw: Mapping[str, Any]) -> "ProactiveTrigger":
        kind = _text(raw.get("kind"), "trigger.kind", 32).lower()
        if kind not in TRIGGER_KINDS:
            raise ProactiveTaskError("invalid_trigger", f"Unsupported trigger kind: {kind}")
        cron = str(raw.get("cron") or "").strip()
        time_zone = str(raw.get("time_zone") or "UTC").strip() or "UTC"
        interval_seconds = _integer(raw.get("interval_seconds") or 0, 0, 31_536_000)
        goal_id = str(raw.get("goal_id") or "").strip()
        webhook_id = str(raw.get("webhook_id") or "").strip()
        event_filter = dict(raw.get("event_filter") or {})
        if len(event_filter) > 32:
            raise ProactiveTaskError("invalid_trigger", "Webhook event filter has too many fields")
        try:
            ZoneInfo(time_zone)
        except ZoneInfoNotFoundError as exc:
            raise ProactiveTaskError("invalid_time_zone", f"Unknown time zone: {time_zone}") from exc
        if kind == "cron":
            CronExpression.parse(cron)
        if kind in {"interval", "goal_checkpoint"} and interval_seconds < 60:
            raise ProactiveTaskError(
                "invalid_interval",
                "Interval and goal checkpoint triggers require at least 60 seconds",
            )
        if kind == "goal_checkpoint":
            _validate_identifier(goal_id, "trigger.goal_id")
        if kind == "webhook" and webhook_id:
            _validate_identifier(webhook_id, "trigger.webhook_id")
        return cls(
            kind=kind,
            cron=cron,
            time_zone=time_zone,
            interval_seconds=interval_seconds,
            goal_id=goal_id,
            webhook_id=webhook_id,
            event_filter=event_filter,
        )


@dataclass(frozen=True)
class ProactiveAction:
    kind: str
    target_id: str = ""
    prompt: str = ""
    arguments: dict[str, Any] = field(default_factory=dict)
    team: tuple[dict[str, str], ...] = ()
    delivery: dict[str, str] = field(default_factory=lambda: {"mode": "store"})

    @classmethod
    def parse(cls, raw: Mapping[str, Any]) -> "ProactiveAction":
        kind = _text(raw.get("kind"), "action.kind", 32).lower()
        if kind not in ACTION_KINDS:
            raise ProactiveTaskError("invalid_action", f"Unsupported action kind: {kind}")
        target_id = str(raw.get("target_id") or "").strip()
        prompt = str(raw.get("prompt") or "").strip()
        if len(target_id) > 128 or len(prompt) > 65_536:
            raise ProactiveTaskError("invalid_action", "Action target or prompt is too long")
        arguments = dict(raw.get("arguments") or {})
        team_raw = list(raw.get("team") or [])
        if len(team_raw) > 16:
            raise ProactiveTaskError("invalid_action", "Sub-agent team exceeds 16 members")
        team: list[dict[str, str]] = []
        final_responder_count = 0
        agent_ids: set[str] = set()
        roles: set[str] = set()
        for value in team_raw:
            if not isinstance(value, Mapping):
                raise ProactiveTaskError("invalid_action", "Sub-agent team member must be an object")
            agent_id = _text(value.get("agent_id"), "team.agent_id", 128)
            role = _text(value.get("role"), "team.role", 32).lower()
            if role not in TEAM_ROLES:
                raise ProactiveTaskError("invalid_action", f"Unsupported team role: {role}")
            if agent_id in agent_ids:
                raise ProactiveTaskError(
                    "invalid_action",
                    f"Sub-agent team repeats Agent: {agent_id}",
                )
            instructions = str(value.get("instructions") or "").strip()
            if len(instructions) > 8_192:
                raise ProactiveTaskError("invalid_action", "Team member instructions are too long")
            agent_ids.add(agent_id)
            roles.add(role)
            final_responder_count += int(role in {"lead", "coordinator"})
            team.append(
                {
                    "agent_id": agent_id,
                    "role": role,
                    "instructions": instructions,
                }
            )
        if kind == "subagent_team" and (not team or final_responder_count != 1):
            raise ProactiveTaskError(
                "invalid_action",
                "A sub-agent team requires exactly one lead or coordinator and at least one member",
            )
        specialist_mode = bool({"coordinator", "specialist"}.intersection(roles))
        if kind == "subagent_team" and specialist_mode and (
            "coordinator" not in roles or "lead" in roles or "specialist" not in roles
        ):
            raise ProactiveTaskError(
                "invalid_action",
                "Coordinator-specialist mode requires one coordinator and at least one specialist",
            )
        if kind == "headless_swarm" and team and (
            final_responder_count != 1
            or "coordinator" not in roles
            or "lead" in roles
            or "specialist" not in roles
        ):
            raise ProactiveTaskError(
                "invalid_action",
                "A configured headless swarm requires one coordinator and at least one specialist",
            )
        if kind not in {"subagent_team", "headless_swarm"} and team:
            raise ProactiveTaskError(
                "invalid_action",
                "Only team and headless swarm actions accept Agent team members",
            )
        if kind in {"agent", "headless_swarm", "subagent_team"} and not prompt:
            raise ProactiveTaskError(
                "invalid_action",
                "Agent actions require a goal or instructions",
            )
        if kind != "subagent_team" and not target_id:
            raise ProactiveTaskError("invalid_action", "Action target_id is required")
        if kind == "headless_swarm":
            from headless_swarm import HeadlessSwarmError, HeadlessSwarmSpec

            try:
                HeadlessSwarmSpec.parse(target_id, prompt, arguments)
            except HeadlessSwarmError as exc:
                raise ProactiveTaskError(exc.code, str(exc)) from exc
        delivery = {str(k): str(v) for k, v in dict(raw.get("delivery") or {}).items()}
        delivery_mode = delivery.get("mode", "store").strip().lower()
        if delivery_mode not in {"store", "notify", "mobile"}:
            raise ProactiveTaskError("invalid_action", f"Unsupported delivery mode: {delivery_mode}")
        delivery["mode"] = delivery_mode
        return cls(
            kind=kind,
            target_id=target_id,
            prompt=prompt,
            arguments=arguments,
            team=tuple(team),
            delivery=delivery,
        )


@dataclass(frozen=True)
class ProactivePolicy:
    misfire: str = "fire_once"
    catch_up_limit: int = 3
    jitter_seconds: int = 0
    max_attempts: int = 3
    retry_backoff_seconds: int = 5
    max_concurrency: int = 1
    max_consecutive_failures: int = 5
    deadline_at_millis: int = 0
    max_runs: int = 0
    network: str = "any"
    requires_charging: bool = False

    @classmethod
    def parse(cls, raw: Mapping[str, Any] | None) -> "ProactivePolicy":
        value = dict(raw or {})
        misfire = str(value.get("misfire") or "fire_once").strip().lower()
        if misfire not in MISFIRE_POLICIES:
            raise ProactiveTaskError("invalid_policy", f"Unsupported misfire policy: {misfire}")
        network = str(value.get("network") or "any").strip().lower()
        if network not in {"any", "unmetered", "offline"}:
            raise ProactiveTaskError("invalid_policy", f"Unsupported network policy: {network}")
        return cls(
            misfire=misfire,
            catch_up_limit=_integer(value.get("catch_up_limit") or 3, 1, 32),
            jitter_seconds=_integer(value.get("jitter_seconds") or 0, 0, 86_400),
            max_attempts=_integer(value.get("max_attempts") or 3, 1, 12),
            retry_backoff_seconds=_integer(value.get("retry_backoff_seconds") or 5, 1, 86_400),
            max_concurrency=_integer(value.get("max_concurrency") or 1, 1, 16),
            max_consecutive_failures=_integer(
                value.get("max_consecutive_failures") or 5,
                1,
                100,
            ),
            deadline_at_millis=max(0, int(value.get("deadline_at_millis") or 0)),
            max_runs=max(0, int(value.get("max_runs") or 0)),
            network=network,
            requires_charging=bool(value.get("requires_charging", False)),
        )


@dataclass(frozen=True)
class ProactiveTask:
    task_id: str
    name: str
    trigger: ProactiveTrigger
    action: ProactiveAction
    policy: ProactivePolicy
    enabled: bool
    next_run_at_millis: int
    last_run_at_millis: int = 0
    last_status: str = "queued"
    run_count: int = 0
    consecutive_failures: int = 0
    revision: int = 1
    created_at_millis: int = 0
    updated_at_millis: int = 0

    def public(self, *, include_webhook_secret: str = "") -> dict[str, Any]:
        payload = {
            "protocol": PROTOCOL,
            "task_id": self.task_id,
            "name": self.name,
            "trigger": asdict(self.trigger),
            "action": {
                **asdict(self.action),
                "team": list(self.action.team),
            },
            "policy": asdict(self.policy),
            "enabled": self.enabled,
            "next_run_at_millis": self.next_run_at_millis,
            "last_run_at_millis": self.last_run_at_millis,
            "last_status": self.last_status,
            "run_count": self.run_count,
            "consecutive_failures": self.consecutive_failures,
            "revision": self.revision,
            "created_at_millis": self.created_at_millis,
            "updated_at_millis": self.updated_at_millis,
        }
        if include_webhook_secret:
            payload["webhook_secret"] = include_webhook_secret
        return payload


@dataclass(frozen=True)
class ProactiveRun:
    run_id: str
    task_id: str
    scheduled_for_millis: int
    status: str
    attempt: int
    cause: dict[str, Any]
    started_at_millis: int = 0
    completed_at_millis: int = 0
    heartbeat_at_millis: int = 0
    output: dict[str, Any] = field(default_factory=dict)
    error_code: str = ""
    error_message: str = ""

    def public(self) -> dict[str, Any]:
        return asdict(self)


class _CronField:
    def __init__(
        self,
        text: str,
        minimum: int,
        maximum: int,
        *,
        aliases: Mapping[str, int] | None = None,
        sunday_alias: bool = False,
    ):
        self.text = text
        self.wildcard = text.strip() == "*"
        self.values = self._parse(
            text,
            minimum,
            maximum,
            aliases=aliases or {},
            sunday_alias=sunday_alias,
        )

    @staticmethod
    def _parse(
        text: str,
        minimum: int,
        maximum: int,
        *,
        aliases: Mapping[str, int],
        sunday_alias: bool,
    ) -> frozenset[int]:
        clean = text.strip().lower()
        if not clean:
            raise ProactiveTaskError("invalid_cron", "Cron field is blank")
        output: set[int] = set()

        def numeric(raw: str) -> int:
            lowered = raw.strip().lower()
            if lowered in aliases:
                return aliases[lowered]
            try:
                value = int(lowered)
            except ValueError as exc:
                raise ProactiveTaskError("invalid_cron", f"Invalid cron token: {raw}") from exc
            if sunday_alias and value == 7:
                return 0
            return value

        for clause in clean.split(","):
            base, separator, step_raw = clause.partition("/")
            step = numeric(step_raw) if separator else 1
            if step <= 0:
                raise ProactiveTaskError("invalid_cron", "Cron step must be positive")
            if base == "*":
                start, end = minimum, maximum
            elif "-" in base:
                start_raw, end_raw = base.split("-", 1)
                start, end = numeric(start_raw), numeric(end_raw)
            else:
                start = end = numeric(base)
            if not (minimum <= start <= maximum and minimum <= end <= maximum):
                raise ProactiveTaskError("invalid_cron", f"Cron value is outside {minimum}..{maximum}")
            if end < start:
                raise ProactiveTaskError("invalid_cron", "Cron ranges cannot wrap")
            output.update(range(start, end + 1, step))
        if not output:
            raise ProactiveTaskError("invalid_cron", "Cron field has no values")
        return frozenset(output)


class CronExpression:
    """Five-field cron with Vixie day-of-month/day-of-week semantics."""

    def __init__(self, expression: str):
        fields = expression.split()
        if len(fields) != 5:
            raise ProactiveTaskError("invalid_cron", "Cron requires five fields")
        self.expression = " ".join(fields)
        self.minute = _CronField(fields[0], 0, 59)
        self.hour = _CronField(fields[1], 0, 23)
        self.day = _CronField(fields[2], 1, 31)
        self.month = _CronField(fields[3], 1, 12, aliases=_MONTH_NAMES)
        self.weekday = _CronField(
            fields[4],
            0,
            6,
            aliases=_WEEKDAY_NAMES,
            sunday_alias=True,
        )

    @classmethod
    def parse(cls, expression: str) -> "CronExpression":
        return cls(expression.strip())

    def matches(self, value: datetime) -> bool:
        cron_weekday = (value.weekday() + 1) % 7
        day_match = value.day in self.day.values
        weekday_match = cron_weekday in self.weekday.values
        if self.day.wildcard and self.weekday.wildcard:
            calendar_match = True
        elif self.day.wildcard:
            calendar_match = weekday_match
        elif self.weekday.wildcard:
            calendar_match = day_match
        else:
            calendar_match = day_match or weekday_match
        return (
            value.minute in self.minute.values
            and value.hour in self.hour.values
            and value.month in self.month.values
            and calendar_match
        )

    def next_after(self, timestamp_millis: int, time_zone: str) -> int:
        zone = ZoneInfo(time_zone)
        candidate = datetime.fromtimestamp(timestamp_millis / 1000, zone)
        candidate = candidate.replace(second=0, microsecond=0) + timedelta(minutes=1)
        for _ in range(3_200_000):
            if self.matches(candidate) and _round_trip_valid(candidate, zone):
                return int(candidate.timestamp() * 1000)
            candidate += timedelta(minutes=1)
        raise ProactiveTaskError("cron_unreachable", "Cron has no occurrence within six years")

    def previous_at_or_before(self, timestamp_millis: int, time_zone: str) -> int:
        zone = ZoneInfo(time_zone)
        candidate = datetime.fromtimestamp(timestamp_millis / 1000, zone)
        candidate = candidate.replace(second=0, microsecond=0)
        for _ in range(3_200_000):
            if self.matches(candidate) and _round_trip_valid(candidate, zone):
                return int(candidate.timestamp() * 1000)
            candidate -= timedelta(minutes=1)
        raise ProactiveTaskError("cron_unreachable", "Cron has no occurrence within six years")


class ProactiveTaskStore:
    def __init__(self, database_path: Path):
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=10000")
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        return connection

    @contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connection() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS proactive_tasks (
                    task_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    trigger_json TEXT NOT NULL,
                    action_json TEXT NOT NULL,
                    policy_json TEXT NOT NULL,
                    enabled INTEGER NOT NULL,
                    next_run_at_millis INTEGER NOT NULL,
                    last_run_at_millis INTEGER NOT NULL,
                    last_status TEXT NOT NULL,
                    run_count INTEGER NOT NULL,
                    consecutive_failures INTEGER NOT NULL,
                    revision INTEGER NOT NULL,
                    created_at_millis INTEGER NOT NULL,
                    updated_at_millis INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS proactive_tasks_due
                    ON proactive_tasks(enabled, next_run_at_millis);
                CREATE TABLE IF NOT EXISTS proactive_runs (
                    run_id TEXT PRIMARY KEY,
                    task_id TEXT NOT NULL,
                    scheduled_for_millis INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    attempt INTEGER NOT NULL,
                    cause_json TEXT NOT NULL,
                    started_at_millis INTEGER NOT NULL,
                    completed_at_millis INTEGER NOT NULL,
                    heartbeat_at_millis INTEGER NOT NULL,
                    output_json TEXT NOT NULL,
                    error_code TEXT NOT NULL,
                    error_message TEXT NOT NULL,
                    UNIQUE(task_id, scheduled_for_millis),
                    FOREIGN KEY(task_id) REFERENCES proactive_tasks(task_id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS proactive_runs_task
                    ON proactive_runs(task_id, scheduled_for_millis DESC);
                CREATE TABLE IF NOT EXISTS proactive_events (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT NOT NULL,
                    timestamp_millis INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    FOREIGN KEY(run_id) REFERENCES proactive_runs(run_id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS proactive_events_run
                    ON proactive_events(run_id, sequence);
                CREATE TABLE IF NOT EXISTS proactive_webhook_nonces (
                    task_id TEXT NOT NULL,
                    nonce TEXT NOT NULL,
                    expires_at_millis INTEGER NOT NULL,
                    PRIMARY KEY(task_id, nonce),
                    FOREIGN KEY(task_id) REFERENCES proactive_tasks(task_id) ON DELETE CASCADE
                );
                """
            )

    def upsert_task(self, task: ProactiveTask) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO proactive_tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    name=excluded.name,
                    trigger_json=excluded.trigger_json,
                    action_json=excluded.action_json,
                    policy_json=excluded.policy_json,
                    enabled=excluded.enabled,
                    next_run_at_millis=excluded.next_run_at_millis,
                    last_run_at_millis=excluded.last_run_at_millis,
                    last_status=excluded.last_status,
                    run_count=excluded.run_count,
                    consecutive_failures=excluded.consecutive_failures,
                    revision=excluded.revision,
                    updated_at_millis=excluded.updated_at_millis
                """,
                (
                    task.task_id,
                    task.name,
                    _json(asdict(task.trigger)),
                    _json({**asdict(task.action), "team": list(task.action.team)}),
                    _json(asdict(task.policy)),
                    int(task.enabled),
                    task.next_run_at_millis,
                    task.last_run_at_millis,
                    task.last_status,
                    task.run_count,
                    task.consecutive_failures,
                    task.revision,
                    task.created_at_millis,
                    task.updated_at_millis,
                ),
            )

    def task(self, task_id: str) -> ProactiveTask | None:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM proactive_tasks WHERE task_id=?",
                (task_id,),
            ).fetchone()
        return _task_from_row(row) if row else None

    def tasks(self, *, limit: int = 200) -> list[ProactiveTask]:
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT * FROM proactive_tasks ORDER BY updated_at_millis DESC LIMIT ?",
                (max(1, min(limit, 1_000)),),
            ).fetchall()
        return [_task_from_row(row) for row in rows]

    def due_tasks(self, now_millis: int, *, limit: int = 100) -> list[ProactiveTask]:
        with self._connection() as connection:
            rows = connection.execute(
                """
                SELECT * FROM proactive_tasks
                WHERE enabled=1 AND next_run_at_millis>0 AND next_run_at_millis<=?
                ORDER BY next_run_at_millis
                LIMIT ?
                """,
                (now_millis, max(1, min(limit, 500))),
            ).fetchall()
        return [_task_from_row(row) for row in rows]

    def delete_task(self, task_id: str) -> bool:
        with self._lock, self._connection() as connection:
            cursor = connection.execute(
                "DELETE FROM proactive_tasks WHERE task_id=?",
                (task_id,),
            )
            return cursor.rowcount > 0

    def create_run(self, run: ProactiveRun) -> ProactiveRun | None:
        with self._lock, self._connection() as connection:
            try:
                connection.execute(
                    """
                    INSERT INTO proactive_runs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        run.run_id,
                        run.task_id,
                        run.scheduled_for_millis,
                        run.status,
                        run.attempt,
                        _json(run.cause),
                        run.started_at_millis,
                        run.completed_at_millis,
                        run.heartbeat_at_millis,
                        _json(run.output),
                        run.error_code,
                        run.error_message,
                    ),
                )
            except sqlite3.IntegrityError:
                return None
        return run

    def update_run(self, run: ProactiveRun) -> None:
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                UPDATE proactive_runs SET
                    status=?, attempt=?, cause_json=?, started_at_millis=?,
                    completed_at_millis=?, heartbeat_at_millis=?, output_json=?,
                    error_code=?, error_message=?
                WHERE run_id=?
                """,
                (
                    run.status,
                    run.attempt,
                    _json(run.cause),
                    run.started_at_millis,
                    run.completed_at_millis,
                    run.heartbeat_at_millis,
                    _json(run.output),
                    run.error_code,
                    run.error_message,
                    run.run_id,
                ),
            )

    def run(self, run_id: str) -> ProactiveRun | None:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM proactive_runs WHERE run_id=?",
                (run_id,),
            ).fetchone()
        return _run_from_row(row) if row else None

    def runs(self, *, task_id: str = "", limit: int = 100) -> list[ProactiveRun]:
        with self._connection() as connection:
            if task_id:
                rows = connection.execute(
                    """
                    SELECT * FROM proactive_runs WHERE task_id=?
                    ORDER BY scheduled_for_millis DESC LIMIT ?
                    """,
                    (task_id, max(1, min(limit, 1_000))),
                ).fetchall()
            else:
                rows = connection.execute(
                    "SELECT * FROM proactive_runs ORDER BY scheduled_for_millis DESC LIMIT ?",
                    (max(1, min(limit, 1_000)),),
                ).fetchall()
        return [_run_from_row(row) for row in rows]

    def recoverable_runs(self) -> list[ProactiveRun]:
        with self._connection() as connection:
            rows = connection.execute(
                """
                SELECT * FROM proactive_runs
                WHERE status IN ('queued', 'running', 'retrying', 'waiting')
                ORDER BY scheduled_for_millis
                LIMIT 200
                """
            ).fetchall()
        return [_run_from_row(row) for row in rows]

    def append_event(
        self,
        run_id: str,
        kind: str,
        status: str,
        detail: str = "",
        metadata: Mapping[str, Any] | None = None,
        *,
        now_millis: int,
    ) -> dict[str, Any]:
        with self._lock, self._connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO proactive_events(
                    run_id, timestamp_millis, kind, status, detail, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    now_millis,
                    str(kind)[:64],
                    str(status)[:32],
                    str(detail)[:4_096],
                    _json(dict(metadata or {})),
                ),
            )
            sequence = int(cursor.lastrowid)
        return {
            "sequence": sequence,
            "run_id": run_id,
            "timestamp_millis": now_millis,
            "kind": str(kind)[:64],
            "status": str(status)[:32],
            "detail": str(detail)[:4_096],
            "metadata": dict(metadata or {}),
        }

    def events(self, run_id: str, *, after: int = 0, limit: int = 500) -> list[dict[str, Any]]:
        with self._connection() as connection:
            rows = connection.execute(
                """
                SELECT * FROM proactive_events
                WHERE run_id=? AND sequence>?
                ORDER BY sequence LIMIT ?
                """,
                (run_id, max(0, after), max(1, min(limit, 2_000))),
            ).fetchall()
        return [
            {
                "sequence": int(row["sequence"]),
                "run_id": str(row["run_id"]),
                "timestamp_millis": int(row["timestamp_millis"]),
                "kind": str(row["kind"]),
                "status": str(row["status"]),
                "detail": str(row["detail"]),
                "metadata": _object(row["metadata_json"]),
            }
            for row in rows
        ]

    def consume_nonce(
        self,
        task_id: str,
        nonce: str,
        expires_at_millis: int,
        *,
        now_millis: int,
    ) -> bool:
        with self._lock, self._connection() as connection:
            connection.execute(
                "DELETE FROM proactive_webhook_nonces WHERE expires_at_millis<?",
                (now_millis,),
            )
            try:
                connection.execute(
                    "INSERT INTO proactive_webhook_nonces VALUES (?, ?, ?)",
                    (task_id, nonce, expires_at_millis),
                )
            except sqlite3.IntegrityError:
                return False
        return True


ProactiveDispatcher = Callable[[ProactiveTask, ProactiveRun], Mapping[str, Any] | str | None]
ProactiveEventSink = Callable[[dict[str, Any]], None]
ProactiveConstraintProbe = Callable[[ProactivePolicy], tuple[bool, str]]


class ProactiveTaskRuntime:
    def __init__(
        self,
        state_root: Path,
        dispatcher: ProactiveDispatcher,
        *,
        event_sink: ProactiveEventSink | None = None,
        now_millis: Callable[[], int] | None = None,
        max_workers: int = 6,
        poll_seconds: float = 1.0,
        constraint_probe: ProactiveConstraintProbe | None = None,
        constraint_recheck_seconds: float = 30.0,
    ):
        self.state_root = Path(state_root)
        self.state_root.mkdir(parents=True, exist_ok=True)
        self.store = ProactiveTaskStore(self.state_root / "proactive-tasks.sqlite3")
        self.dispatcher = dispatcher
        self.event_sink = event_sink or (lambda _event: None)
        self.now_millis = now_millis or (lambda: int(time.time() * 1000))
        self.poll_seconds = max(0.1, float(poll_seconds))
        self.constraint_probe = constraint_probe or _default_constraint_probe
        self.constraint_recheck_millis = int(
            max(1.0, float(constraint_recheck_seconds)) * 1000
        )
        self._executor = ThreadPoolExecutor(max_workers=max(1, max_workers), thread_name_prefix="proactive")
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._thread: threading.Thread | None = None
        self._task_semaphores: dict[str, threading.BoundedSemaphore] = {}
        self._cancel: dict[str, threading.Event] = {}
        self._lock = threading.RLock()
        self._master_key = self._load_master_key()

    def start(self) -> None:
        with self._lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop.clear()
            self._thread = threading.Thread(
                target=self._run_loop,
                name="GalaxySSIProactiveScheduler",
                daemon=True,
            )
            self._thread.start()
        self._recover_incomplete()
        self._wake.set()

    def stop(self, *, wait_for_workers: bool = False) -> None:
        self._stop.set()
        self._wake.set()
        thread = self._thread
        if thread and thread.is_alive():
            thread.join(timeout=5)
        with self._lock:
            for event in self._cancel.values():
                event.set()
        self._executor.shutdown(wait=wait_for_workers, cancel_futures=True)

    def create(
        self,
        *,
        name: str,
        trigger: Mapping[str, Any],
        action: Mapping[str, Any],
        policy: Mapping[str, Any] | None = None,
        enabled: bool = True,
        task_id: str = "",
    ) -> dict[str, Any]:
        now = self.now_millis()
        clean_id = task_id.strip() or str(uuid.uuid4())
        _validate_identifier(clean_id, "task_id")
        clean_name = _text(name, "name", 120)
        parsed_trigger = ProactiveTrigger.parse(trigger)
        if parsed_trigger.kind == "webhook" and not parsed_trigger.webhook_id:
            parsed_trigger = ProactiveTrigger(
                **{
                    **asdict(parsed_trigger),
                    "webhook_id": secrets.token_urlsafe(18).replace("-", "").replace("_", "")[:24],
                }
            )
        parsed_action = ProactiveAction.parse(action)
        parsed_policy = ProactivePolicy.parse(policy)
        task = ProactiveTask(
            task_id=clean_id,
            name=clean_name,
            trigger=parsed_trigger,
            action=parsed_action,
            policy=parsed_policy,
            enabled=bool(enabled),
            next_run_at_millis=self._initial_next_run(parsed_trigger, now) if enabled else 0,
            created_at_millis=now,
            updated_at_millis=now,
        )
        self.store.upsert_task(task)
        self._wake.set()
        secret = self.webhook_secret(task.task_id) if parsed_trigger.kind == "webhook" else ""
        return task.public(include_webhook_secret=secret)

    def update(
        self,
        task_id: str,
        *,
        name: str | None = None,
        trigger: Mapping[str, Any] | None = None,
        action: Mapping[str, Any] | None = None,
        policy: Mapping[str, Any] | None = None,
        enabled: bool | None = None,
    ) -> dict[str, Any]:
        current = self.require_task(task_id)
        now = self.now_millis()
        parsed_trigger = ProactiveTrigger.parse(trigger) if trigger is not None else current.trigger
        parsed_action = ProactiveAction.parse(action) if action is not None else current.action
        parsed_policy = ProactivePolicy.parse(policy) if policy is not None else current.policy
        next_enabled = current.enabled if enabled is None else bool(enabled)
        trigger_changed = parsed_trigger != current.trigger
        next_run = current.next_run_at_millis
        if not next_enabled:
            next_run = 0
        elif trigger_changed or not current.enabled:
            next_run = self._initial_next_run(parsed_trigger, now)
        task = replace(
            current,
            name=_text(name, "name", 120) if name is not None else current.name,
            trigger=parsed_trigger,
            action=parsed_action,
            policy=parsed_policy,
            enabled=next_enabled,
            next_run_at_millis=next_run,
            revision=current.revision + 1,
            updated_at_millis=now,
        )
        self.store.upsert_task(task)
        self._wake.set()
        return task.public()

    def require_task(self, task_id: str) -> ProactiveTask:
        task = self.store.task(task_id)
        if task is None:
            raise ProactiveTaskError("task_not_found", "Proactive task was not found")
        return task

    def delete(self, task_id: str) -> bool:
        for run in self.store.runs(task_id=task_id, limit=1_000):
            if run.status not in TERMINAL_RUN_STATUSES:
                self.cancel_run(run.run_id)
        return self.store.delete_task(task_id)

    def trigger_now(
        self,
        task_id: str,
        *,
        cause: Mapping[str, Any] | None = None,
    ) -> ProactiveRun:
        task = self.require_task(task_id)
        if not task.enabled:
            raise ProactiveTaskError("task_disabled", "Proactive task is disabled")
        return self._enqueue(task, self.now_millis(), dict(cause or {"type": "manual"}))

    def handle_webhook(
        self,
        task_id: str,
        body: bytes,
        *,
        timestamp: str,
        nonce: str,
        signature: str,
    ) -> ProactiveRun:
        task = self.require_task(task_id)
        if not task.enabled or task.trigger.kind != "webhook":
            raise ProactiveTaskError("webhook_unavailable", "Webhook task is disabled or invalid")
        if len(body) > 256 * 1024:
            raise ProactiveTaskError("webhook_too_large", "Webhook payload exceeds 256 KiB")
        if not re.fullmatch(r"[A-Za-z0-9._:-]{8,128}", nonce or ""):
            raise ProactiveTaskError("webhook_nonce_invalid", "Webhook nonce is invalid")
        try:
            timestamp_seconds = int(timestamp)
        except (TypeError, ValueError) as exc:
            raise ProactiveTaskError("webhook_timestamp_invalid", "Webhook timestamp is invalid") from exc
        now = self.now_millis()
        if abs(now - timestamp_seconds * 1000) > 5 * 60 * 1000:
            raise ProactiveTaskError("webhook_expired", "Webhook timestamp is outside the replay window")
        digest = hashlib.sha256(body).hexdigest()
        signing_input = f"{timestamp_seconds}.{nonce}.{digest}".encode("utf-8")
        expected = hmac.new(
            self.webhook_secret(task_id).encode("utf-8"),
            signing_input,
            hashlib.sha256,
        ).hexdigest()
        offered = str(signature or "").removeprefix("sha256=").strip().lower()
        if not hmac.compare_digest(expected, offered):
            raise ProactiveTaskError("webhook_signature_invalid", "Webhook signature is invalid")
        if not self.store.consume_nonce(
            task_id,
            nonce,
            now + 5 * 60 * 1000,
            now_millis=now,
        ):
            raise ProactiveTaskError("webhook_replay", "Webhook nonce has already been used")
        parsed: Any
        try:
            parsed = json.loads(body.decode("utf-8")) if body else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            parsed = {"raw_sha256": digest}
        if task.trigger.event_filter and not _event_filter_matches(task.trigger.event_filter, parsed):
            raise ProactiveTaskError("webhook_filter_mismatch", "Webhook event does not match this task")
        return self._enqueue(
            task,
            now,
            {
                "type": "webhook",
                "nonce": nonce,
                "body_sha256": digest,
                "payload": parsed,
            },
        )

    def webhook_secret(self, task_id: str) -> str:
        _validate_identifier(task_id, "task_id")
        task = self.require_task(task_id)
        discriminator = task.trigger.webhook_id or task.task_id
        digest = hmac.new(
            self._master_key,
            f"webhook:{task_id}:{discriminator}".encode(),
            hashlib.sha256,
        ).digest()
        return digest.hex()

    def tick(self, now_millis: int | None = None) -> list[ProactiveRun]:
        now = self.now_millis() if now_millis is None else int(now_millis)
        submitted: list[ProactiveRun] = []
        for task in self.store.due_tasks(now):
            if self._should_disable(task, now):
                self._set_task(task, enabled=False, next_run_at_millis=0, updated_at_millis=now)
                continue
            occurrences, next_run = self._due_occurrences(task, now)
            self._set_task(task, next_run_at_millis=next_run, updated_at_millis=now)
            for scheduled_for, status in occurrences:
                if status == "skipped":
                    run = self._new_run(task, scheduled_for, {"type": "schedule", "misfire": "skip"})
                    created = self.store.create_run(ProactiveRun(**{**asdict(run), "status": "skipped", "completed_at_millis": now}))
                    if created:
                        self._event(created, "misfire", "skipped", "Missed schedule was skipped")
                        submitted.append(created)
                    continue
                try:
                    submitted.append(
                        self._enqueue(
                            task,
                            scheduled_for,
                            {"type": task.trigger.kind, "scheduled_for_millis": scheduled_for},
                        )
                    )
                except ProactiveTaskError as exc:
                    if exc.code != "duplicate_run":
                        raise
        return submitted

    def cancel_run(self, run_id: str) -> bool:
        run = self.store.run(run_id)
        if run is None or run.status in TERMINAL_RUN_STATUSES:
            return False
        with self._lock:
            self._cancel.setdefault(run_id, threading.Event()).set()
        now = self.now_millis()
        cancelled = ProactiveRun(
            **{
                **asdict(run),
                "status": "cancelled",
                "completed_at_millis": now,
                "heartbeat_at_millis": now,
                "error_code": "cancelled",
                "error_message": "Cancellation requested",
            }
        )
        self.store.update_run(cancelled)
        self._event(cancelled, "cancel", "cancelled", "Cancellation requested")
        return True

    def record_progress(
        self,
        run_id: str,
        kind: str,
        detail: str,
        metadata: Mapping[str, Any] | None = None,
    ) -> bool:
        run = self.store.run(run_id)
        if run is None or run.status in TERMINAL_RUN_STATUSES:
            return False
        self._event(
            run,
            _text(kind, "event.kind", 64),
            run.status,
            _text(detail, "event.detail", 4_096),
            metadata,
        )
        return True

    def _run_loop(self) -> None:
        while not self._stop.is_set():
            try:
                self._resume_waiting_constraints()
                self.tick()
            except Exception as exc:
                self.event_sink(
                    {
                        "protocol": PROTOCOL,
                        "kind": "scheduler_error",
                        "status": "failed",
                        "detail": str(exc)[:1_000],
                        "timestamp_millis": self.now_millis(),
                    }
                )
            self._wake.wait(self.poll_seconds)
            self._wake.clear()

    def _recover_incomplete(self) -> None:
        for run in self.store.recoverable_runs():
            task = self.store.task(run.task_id)
            if task is None or not task.enabled:
                continue
            recovered = ProactiveRun(
                **{
                    **asdict(run),
                    "status": "retrying",
                    "error_code": "process_restarted",
                    "error_message": "Recovered after Desktop restart",
                }
            )
            self.store.update_run(recovered)
            self._event(recovered, "recover", "retrying", "Recovered after Desktop restart")
            self._submit(task, recovered)

    def _enqueue(self, task: ProactiveTask, scheduled_for: int, cause: dict[str, Any]) -> ProactiveRun:
        run = self._new_run(task, scheduled_for, cause)
        created = self.store.create_run(run)
        if created is None:
            raise ProactiveTaskError("duplicate_run", "This task occurrence is already recorded")
        self._event(created, "queued", "queued", "Proactive task queued")
        self._submit(task, created)
        return created

    def _submit(self, task: ProactiveTask, run: ProactiveRun) -> None:
        with self._lock:
            semaphore = self._task_semaphores.setdefault(
                task.task_id,
                threading.BoundedSemaphore(task.policy.max_concurrency),
            )
            self._cancel.setdefault(run.run_id, threading.Event())
        self._executor.submit(self._execute, task.task_id, run.run_id, semaphore)

    def _execute(
        self,
        task_id: str,
        run_id: str,
        semaphore: threading.BoundedSemaphore,
    ) -> None:
        with semaphore:
            task = self.store.task(task_id)
            run = self.store.run(run_id)
            if task is None or run is None or run.status == "cancelled":
                return
            cancel = self._cancel.get(run_id) or threading.Event()
            allowed, constraint_detail = self.constraint_probe(task.policy)
            if not allowed:
                now = self.now_millis()
                waiting = ProactiveRun(
                    **{
                        **asdict(run),
                        "status": "waiting",
                        "heartbeat_at_millis": now,
                        "error_code": "constraints_waiting",
                        "error_message": constraint_detail[:4_096],
                    }
                )
                self.store.update_run(waiting)
                self._event(
                    waiting,
                    "constraint",
                    "waiting",
                    constraint_detail,
                )
                self._finish_run_handle(run_id)
                return
            last_error = ""
            last_code = ""
            last_attempt = max(1, run.attempt)
            for attempt in range(max(1, run.attempt), task.policy.max_attempts + 1):
                last_attempt = attempt
                if self._stop.is_set() or cancel.is_set():
                    self.cancel_run(run_id)
                    self._finish_run_handle(run_id)
                    return
                now = self.now_millis()
                running = ProactiveRun(
                    **{
                        **asdict(run),
                        "status": "running" if attempt == 1 else "retrying",
                        "attempt": attempt,
                        "started_at_millis": run.started_at_millis or now,
                        "heartbeat_at_millis": now,
                        "error_code": "",
                        "error_message": "",
                    }
                )
                self.store.update_run(running)
                self._event(
                    running,
                    "attempt",
                    running.status,
                    f"Attempt {attempt} started",
                    {"attempt": attempt},
                )
                try:
                    result = self.dispatcher(task, running)
                    latest = self.store.run(run_id)
                    if cancel.is_set() or (latest and latest.status == "cancelled"):
                        self._finish_run_handle(run_id)
                        return
                    output = _normalize_output(result)
                    now = self.now_millis()
                    completed = ProactiveRun(
                        **{
                            **asdict(running),
                            "status": "completed",
                            "completed_at_millis": now,
                            "heartbeat_at_millis": now,
                            "output": output,
                        }
                    )
                    self.store.update_run(completed)
                    self._event(completed, "finalize", "completed", "Proactive task completed")
                    self._record_task_outcome(task, completed, success=True)
                    if task.trigger.kind == "goal_checkpoint" and bool(output.get("goal_completed")):
                        refreshed = self.store.task(task.task_id)
                        if refreshed:
                            self._set_task(
                                refreshed,
                                enabled=False,
                                next_run_at_millis=0,
                                updated_at_millis=now,
                            )
                    self._finish_run_handle(run_id)
                    return
                except ProactiveTaskError as exc:
                    last_code, last_error = exc.code, str(exc)
                    retryable = exc.retryable
                except Exception as exc:
                    last_code, last_error, retryable = "execution_failed", str(exc), True
                latest = self.store.run(run_id)
                if cancel.is_set() or (latest and latest.status == "cancelled"):
                    self._finish_run_handle(run_id)
                    return
                self._event(
                    running,
                    "observe",
                    "failed",
                    last_error,
                    {"attempt": attempt, "error_code": last_code, "retryable": retryable},
                )
                if not retryable or attempt >= task.policy.max_attempts:
                    break
                if cancel.wait(task.policy.retry_backoff_seconds * (2 ** (attempt - 1))):
                    self.cancel_run(run_id)
                    self._finish_run_handle(run_id)
                    return
            now = self.now_millis()
            failed = ProactiveRun(
                **{
                    **asdict(run),
                    "status": "failed",
                    "attempt": last_attempt,
                    "started_at_millis": run.started_at_millis or now,
                    "completed_at_millis": now,
                    "heartbeat_at_millis": now,
                    "error_code": last_code or "execution_failed",
                    "error_message": (last_error or "Proactive task failed")[:4_096],
                }
            )
            self.store.update_run(failed)
            self._event(failed, "finalize", "failed", failed.error_message)
            self._record_task_outcome(task, failed, success=False)
        self._finish_run_handle(run_id)

    def _resume_waiting_constraints(self) -> None:
        now = self.now_millis()
        for run in self.store.recoverable_runs():
            if run.status != "waiting":
                continue
            if now - run.heartbeat_at_millis < self.constraint_recheck_millis:
                continue
            task = self.store.task(run.task_id)
            if task is None or not task.enabled:
                continue
            queued = ProactiveRun(
                **{
                    **asdict(run),
                    "status": "queued",
                    "heartbeat_at_millis": now,
                    "error_code": "",
                    "error_message": "",
                }
            )
            self.store.update_run(queued)
            self._event(queued, "constraint", "queued", "Task constraints are being checked")
            self._submit(task, queued)

    def _record_task_outcome(self, task: ProactiveTask, run: ProactiveRun, *, success: bool) -> None:
        current = self.store.task(task.task_id) or task
        failures = 0 if success else current.consecutive_failures + 1
        enabled = current.enabled and failures < current.policy.max_consecutive_failures
        if current.policy.max_runs and current.run_count + 1 >= current.policy.max_runs:
            enabled = False
        self._set_task(
            current,
            enabled=enabled,
            next_run_at_millis=current.next_run_at_millis if enabled else 0,
            last_run_at_millis=run.completed_at_millis,
            last_status=run.status,
            run_count=current.run_count + 1,
            consecutive_failures=failures,
            updated_at_millis=run.completed_at_millis,
        )

    def _new_run(self, task: ProactiveTask, scheduled_for: int, cause: dict[str, Any]) -> ProactiveRun:
        return ProactiveRun(
            run_id=str(uuid.uuid4()),
            task_id=task.task_id,
            scheduled_for_millis=max(0, int(scheduled_for)),
            status="queued",
            attempt=1,
            cause=cause,
        )

    def _event(
        self,
        run: ProactiveRun,
        kind: str,
        status: str,
        detail: str,
        metadata: Mapping[str, Any] | None = None,
    ) -> None:
        event = self.store.append_event(
            run.run_id,
            kind,
            status,
            detail,
            metadata,
            now_millis=self.now_millis(),
        )
        event["protocol"] = PROTOCOL
        event["task_id"] = run.task_id
        self.event_sink(event)

    def _set_task(self, task: ProactiveTask, **changes: Any) -> ProactiveTask:
        updated = replace(task, **changes)
        self.store.upsert_task(updated)
        return updated

    def _finish_run_handle(self, run_id: str) -> None:
        with self._lock:
            self._cancel.pop(run_id, None)

    def _initial_next_run(self, trigger: ProactiveTrigger, now: int) -> int:
        if trigger.kind == "cron":
            return CronExpression.parse(trigger.cron).next_after(now - 60_000, trigger.time_zone)
        if trigger.kind in {"interval", "goal_checkpoint"}:
            return now + trigger.interval_seconds * 1000
        return 0

    def _next_run(self, task: ProactiveTask, after: int) -> int:
        if task.trigger.kind == "cron":
            base = CronExpression.parse(task.trigger.cron).next_after(after, task.trigger.time_zone)
        elif task.trigger.kind in {"interval", "goal_checkpoint"}:
            base = after + task.trigger.interval_seconds * 1000
        else:
            return 0
        return base + _deterministic_jitter(task.task_id, base, task.policy.jitter_seconds)

    def _due_occurrences(self, task: ProactiveTask, now: int) -> tuple[list[tuple[int, str]], int]:
        scheduled = task.next_run_at_millis
        if task.trigger.kind in {"interval", "goal_checkpoint"}:
            interval = task.trigger.interval_seconds * 1000
            count = max(1, ((now - scheduled) // interval) + 1)
            cursor = scheduled + count * interval
            late = now - scheduled > max(60_000, int(self.poll_seconds * 3_000))
            if not late:
                return [(scheduled, "run")], cursor
            retained_count = min(count, task.policy.catch_up_limit)
            retained_start = count - retained_count
            retained = [
                scheduled + index * interval
                for index in range(retained_start, count)
            ]
            if task.policy.misfire == "skip":
                return [(value, "skipped") for value in retained], cursor
            if task.policy.misfire == "fire_once":
                return [(retained[-1], "run")], cursor
            return [(value, "run") for value in retained], cursor

        cron = CronExpression.parse(task.trigger.cron)
        cursor = cron.next_after(now, task.trigger.time_zone)
        late = now - scheduled > max(60_000, int(self.poll_seconds * 3_000))
        if not late:
            return [(scheduled, "run")], cursor
        if task.policy.misfire == "skip":
            return [(scheduled, "skipped")], cursor
        if task.policy.misfire == "fire_once":
            return [(now, "run")], cursor
        due: list[int] = []
        previous_cursor = now
        for _ in range(task.policy.catch_up_limit):
            previous = cron.previous_at_or_before(previous_cursor, task.trigger.time_zone)
            if previous < scheduled:
                break
            due.append(previous)
            previous_cursor = previous - 60_000
        due.reverse()
        return [(value, "run") for value in due], cursor

    def _should_disable(self, task: ProactiveTask, now: int) -> bool:
        return bool(
            (task.policy.deadline_at_millis and now > task.policy.deadline_at_millis)
            or (task.policy.max_runs and task.run_count >= task.policy.max_runs)
            or task.consecutive_failures >= task.policy.max_consecutive_failures
        )

    def _load_master_key(self) -> bytes:
        path = self.state_root / "proactive-webhook-master.key"
        try:
            existing = path.read_bytes()
            if len(existing) == 32:
                return existing
        except OSError:
            pass
        key = secrets.token_bytes(32)
        temporary = path.with_suffix(".tmp")
        temporary.write_bytes(key)
        try:
            os.chmod(temporary, 0o600)
        except OSError:
            pass
        os.replace(temporary, path)
        return key


def _task_from_row(row: sqlite3.Row) -> ProactiveTask:
    return ProactiveTask(
        task_id=str(row["task_id"]),
        name=str(row["name"]),
        trigger=ProactiveTrigger.parse(_object(row["trigger_json"])),
        action=ProactiveAction.parse(_object(row["action_json"])),
        policy=ProactivePolicy.parse(_object(row["policy_json"])),
        enabled=bool(row["enabled"]),
        next_run_at_millis=int(row["next_run_at_millis"]),
        last_run_at_millis=int(row["last_run_at_millis"]),
        last_status=str(row["last_status"]),
        run_count=int(row["run_count"]),
        consecutive_failures=int(row["consecutive_failures"]),
        revision=int(row["revision"]),
        created_at_millis=int(row["created_at_millis"]),
        updated_at_millis=int(row["updated_at_millis"]),
    )


def _run_from_row(row: sqlite3.Row) -> ProactiveRun:
    status = str(row["status"])
    return ProactiveRun(
        run_id=str(row["run_id"]),
        task_id=str(row["task_id"]),
        scheduled_for_millis=int(row["scheduled_for_millis"]),
        status=status if status in RUN_STATUSES else "failed",
        attempt=int(row["attempt"]),
        cause=_object(row["cause_json"]),
        started_at_millis=int(row["started_at_millis"]),
        completed_at_millis=int(row["completed_at_millis"]),
        heartbeat_at_millis=int(row["heartbeat_at_millis"]),
        output=_object(row["output_json"]),
        error_code=str(row["error_code"]),
        error_message=str(row["error_message"]),
    )


def _event_filter_matches(expected: Mapping[str, Any], payload: Any) -> bool:
    if not isinstance(payload, Mapping):
        return False
    for key, value in expected.items():
        cursor: Any = payload
        for segment in str(key).split("."):
            if not isinstance(cursor, Mapping) or segment not in cursor:
                return False
            cursor = cursor[segment]
        if isinstance(value, list):
            if cursor not in value:
                return False
        elif cursor != value:
            return False
    return True


def _deterministic_jitter(task_id: str, occurrence: int, jitter_seconds: int) -> int:
    if jitter_seconds <= 0:
        return 0
    digest = hashlib.sha256(f"{task_id}:{occurrence}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % (jitter_seconds * 1000 + 1)


def _round_trip_valid(value: datetime, zone: ZoneInfo) -> bool:
    reconstructed = datetime.fromtimestamp(value.timestamp(), zone)
    return reconstructed.replace(fold=value.fold) == value


def _normalize_output(value: Mapping[str, Any] | str | None) -> dict[str, Any]:
    if value is None:
        return {}
    if isinstance(value, Mapping):
        return dict(value)
    return {"reply": str(value)}


def _default_constraint_probe(policy: ProactivePolicy) -> tuple[bool, str]:
    if policy.requires_charging and not _external_power_available():
        return False, "Waiting for external power"
    if policy.network == "any":
        return True, ""
    connected, metered = _network_cost_state()
    if policy.network == "offline":
        return (not connected, "" if not connected else "Waiting for offline mode")
    if not connected:
        return False, "Waiting for a network connection"
    if metered is not False:
        return False, "Waiting for a verified unmetered network"
    return True, ""


def _external_power_available() -> bool:
    if os.name == "nt":
        try:
            import ctypes

            class SystemPowerStatus(ctypes.Structure):
                _fields_ = [
                    ("ACLineStatus", ctypes.c_ubyte),
                    ("BatteryFlag", ctypes.c_ubyte),
                    ("BatteryLifePercent", ctypes.c_ubyte),
                    ("SystemStatusFlag", ctypes.c_ubyte),
                    ("BatteryLifeTime", ctypes.c_ulong),
                    ("BatteryFullLifeTime", ctypes.c_ulong),
                ]

            status = SystemPowerStatus()
            if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(status)):
                return False
            if status.BatteryFlag & 128:
                return True
            return status.ACLineStatus == 1
        except (AttributeError, OSError):
            return False
    power_root = Path("/sys/class/power_supply")
    if not power_root.exists():
        return True
    supplies = list(power_root.iterdir())
    batteries = [
        item for item in supplies
        if _read_text(item / "type").lower() == "battery"
    ]
    external = [
        item for item in supplies
        if _read_text(item / "type").lower() in {"mains", "usb", "usb_c"}
    ]
    if not batteries:
        return True
    return any(_read_text(item / "online") == "1" for item in external)


def _network_cost_state() -> tuple[bool, bool | None]:
    if os.name == "nt":
        try:
            creation_flags = int(getattr(subprocess, "CREATE_NO_WINDOW", 0))
            command = (
                "$p=[Windows.Networking.Connectivity.NetworkInformation,"
                "Windows,ContentType=WindowsRuntime]::GetInternetConnectionProfile();"
                "if($null -eq $p){'offline'}else{$p.GetConnectionCost().NetworkCostType.ToString()}"
            )
            result = subprocess.run(
                [
                    "powershell.exe",
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    command,
                ],
                capture_output=True,
                text=True,
                timeout=3,
                creationflags=creation_flags,
                check=False,
            )
            value = result.stdout.strip().splitlines()[-1].strip().lower()
            if value == "offline":
                return False, None
            if value == "unrestricted":
                return True, False
            if value in {"fixed", "variable"}:
                return True, True
        except (OSError, subprocess.SubprocessError, IndexError):
            pass
    active_interfaces = _active_network_interfaces()
    if not active_interfaces:
        return False, None
    unmetered_prefixes = ("eth", "en", "eno", "enp")
    if any(name.lower().startswith(unmetered_prefixes) for name in active_interfaces):
        return True, False
    return True, None


def _active_network_interfaces() -> list[str]:
    if os.name != "nt":
        root = Path("/sys/class/net")
        if root.exists():
            return [
                item.name
                for item in root.iterdir()
                if item.name != "lo" and _read_text(item / "operstate") == "up"
            ]
    try:
        hostname = socket.gethostname()
        addresses = {
            item[4][0]
            for item in socket.getaddrinfo(hostname, None)
            if item[0] in {socket.AF_INET, socket.AF_INET6}
        }
        return ["host"] if any(value not in {"127.0.0.1", "::1"} for value in addresses) else []
    except OSError:
        return []


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _validate_identifier(value: str, name: str) -> None:
    if not _IDENTIFIER.fullmatch(value or ""):
        raise ProactiveTaskError("invalid_identifier", f"{name} is invalid")


def _text(value: Any, name: str, maximum: int) -> str:
    clean = str(value or "").strip()
    if not clean or len(clean) > maximum:
        raise ProactiveTaskError("invalid_input", f"{name} is blank or too long")
    return clean


def _integer(value: Any, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        raise ProactiveTaskError("invalid_input", "Boolean is not an integer")
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ProactiveTaskError("invalid_input", "Expected an integer") from exc
    if not minimum <= parsed <= maximum:
        raise ProactiveTaskError("invalid_input", f"Integer must be within {minimum}..{maximum}")
    return parsed


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _object(value: str | bytes | bytearray | None) -> dict[str, Any]:
    try:
        decoded = json.loads(value or "{}")
    except (TypeError, ValueError, json.JSONDecodeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}
