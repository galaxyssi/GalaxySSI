"""Private host registration for exact App experiment dispatches.

The registry is immutable for a running Desktop lifetime. It is never accepted
from MQTT. A durable task carries only its admission fingerprint, not a grant.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import threading

from codex_experiment_boundary import CodexExperimentBoundary, _path, _within, reject

ENV = "GALAXYSSI_CODEX_EXPERIMENT_REGISTRY"
FORMAT = "galaxyssi.codex-experiment-registry.v1"
MARKER = "codex_experiment_admission"
_lock = threading.RLock()
_registry = None


class ExperimentRegistration:
    def __init__(self, row, denied_roots):
        required = {"scope_id", "client_route_id", "client_conversation_id", "task_ids",
                    "workspace", "protected_root", "state_path", "model", "effort",
                    "conversation_ids", "mcp_names", "skill_paths", "read_only", "task_conversations"}
        if not isinstance(row, dict) or set(row) != required:
            reject("registry_fields")
        for key in ("client_route_id", "client_conversation_id"):
            if not isinstance(row[key], str) or not row[key].strip() or len(row[key]) > 200:
                reject("registry_identity")
        tasks = row["task_ids"]
        if (not isinstance(tasks, list) or not tasks or len(tasks) > 1000
                or any(not isinstance(t, str) or not t or len(t) > 200 for t in tasks)
                or len(tasks) != len(set(tasks))):
            reject("registry_tasks")
        self.route, self.conversation = row["client_route_id"], row["client_conversation_id"]
        self.task_ids = frozenset(tasks)
        self.task_conversations = row["task_conversations"]
        if (not isinstance(self.task_conversations, dict) or set(self.task_conversations) != self.task_ids
                or any(not isinstance(v, str) or v not in row["conversation_ids"] for v in self.task_conversations.values())):
            reject("task_conversation_binding")
        self.boundary = CodexExperimentBoundary(**{k: v for k, v in row.items()
            if k not in {"client_route_id", "client_conversation_id", "task_ids", "task_conversations"}},
            denied_roots=denied_roots)
        self.marker = hashlib.sha256(json.dumps({"registration": row, "boundary": self.boundary.fingerprint},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        self.server = None
        self.lock = threading.RLock()

    def workspace(self, task_id, *, create=False):
        if task_id not in self.task_ids:
            reject("unregistered_task")
        directory = self.boundary.workspace / hashlib.sha256(task_id.encode()).hexdigest()
        _path(directory, exists=False)
        if create:
            directory.mkdir(exist_ok=True)
        return directory

    def get_server(self, executable, env, callback, factory):
        with self.lock:
            if self.server is None:
                self.server = factory(executable, env, callback, experiment_boundary=self.boundary)
            elif self.server.executable != executable:
                reject("runtime_executable_changed")
            return self.server


class CodexExperimentRegistry:
    def __init__(self, path):
        self.path = _path(path)
        if not self.path.is_file() or self.path.stat().st_size > 1024 * 1024:
            reject("registry_size")
        raw = self.path.read_bytes()
        self.digest = hashlib.sha256(raw).hexdigest()
        try:
            value = json.loads(raw)
            if set(value) != {"format", "scopes"} or value["format"] != FORMAT or not isinstance(value["scopes"], list):
                reject("registry_format")
            rows = value["scopes"]
            self.scopes = [ExperimentRegistration(row, [other["workspace"]
                for other in rows if other is not row]) for row in rows]
        except (ValueError, TypeError, KeyError):
            reject("registry_invalid")
        self.tasks = {}
        identities, state_paths = set(), set()
        for scope in self.scopes:
            if not _within(self.path, scope.boundary.protected_root):
                reject("unprotected_registry")
            if scope.boundary.state_path in state_paths or scope.boundary.state_path == self.path:
                reject("shared_state")
            state_paths.add(scope.boundary.state_path)
            for conversation in scope.boundary.conversation_ids:
                key = (scope.route, scope.conversation, conversation)
                if key in identities:
                    reject("duplicate_identity")
                identities.add(key)
            for task in scope.task_ids:
                if task in self.tasks:
                    reject("duplicate_task")
                self.tasks[task] = scope
        for index, scope in enumerate(self.scopes):
            for other in self.scopes[index + 1:]:
                a, b = scope.boundary.workspace, other.boundary.workspace
                if _within(a, b) or _within(b, a):
                    reject("shared_workspace")

    def check_unchanged(self):
        try:
            if (_path(self.path) != self.path or self.path.stat().st_size > 1024 * 1024
                    or hashlib.sha256(self.path.read_bytes()).hexdigest() != self.digest):
                reject("registry_changed")
        except OSError:
            reject("registry_missing")

    def admit(self, *, route, conversation, backend_conversation, task_id, model, effort,
              agent_id, attachments, snapshot, read_only, full_executor, scope_hint=""):
        self.check_unchanged()
        scope = self.tasks.get(task_id)
        marker = (snapshot or {}).get(MARKER)
        if scope is None:
            if marker or scope_hint or any(s.route == route and s.conversation == conversation for s in self.scopes):
                reject("unregistered_task")
            return None
        if (scope.route != route or scope.conversation != conversation or agent_id != "codex"
                or scope.task_conversations[task_id] != backend_conversation
                or not full_executor or (snapshot is not None and marker != scope.marker)
                or (scope_hint and scope_hint != scope.marker)):
            reject("admission_identity")
        if read_only and not scope.boundary.read_only:
            reject("read_only_profile_not_verified")
        scope.boundary.admit(backend_conversation, scope.boundary.workspace, model, effort, attachments)
        return scope

    def close(self):
        for scope in self.scopes:
            if scope.server is not None:
                scope.server.close()
                scope.server = None


def registry():
    global _registry
    configured = os.environ.get(ENV, "").strip()
    with _lock:
        if _registry is not None:
            if not configured or _path(configured) != _registry.path:
                reject("registry_configuration_changed")
            return _registry
        if configured:
            try:
                _registry = CodexExperimentRegistry(configured)
            except OSError:
                reject("registry_unavailable")
        return _registry


def admit(**kwargs):
    value = registry()
    if value is None:
        if (kwargs.get("snapshot") or {}).get(MARKER) or kwargs.get("scope_hint"):
            reject("registry_required")
        return None
    return value.admit(**kwargs)


def registered_workspace(task_id):
    value = registry()
    if value is None or task_id not in value.tasks:
        return None
    value.check_unchanged()
    return value.tasks[task_id].workspace(task_id)


def active_server(task_id):
    with _lock:
        scope = _registry.tasks.get(task_id) if _registry is not None else None
        return (scope is not None, scope.server if scope else None)


def close():
    global _registry
    with _lock:
        if _registry is not None:
            _registry.close()
            _registry = None
