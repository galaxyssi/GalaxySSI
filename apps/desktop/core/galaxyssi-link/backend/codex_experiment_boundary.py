"""Trusted-host, opt-in execution boundary for isolated evaluation instances.

This is not a remotely selectable mode or a workspace-only sandbox guarantee.
The host must supply a private protected subtree and a dedicated workspace.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import threading


FORMAT = "galaxyssi.codex-experiment-boundary.v1"
FLAGS = {
    "web_search": "disabled", "project_doc_max_bytes": 0,
    "developer_instructions": "", "features.skip_host_skill_discovery": True,
    **{f"features.{name}": False for name in (
        "apps", "plugins", "remote_plugin", "browser_use", "browser_use_external",
        "computer_use", "in_app_browser", "memories", "multi_agent", "multi_agent_v2",
        "hooks", "image_generation", "skill_search", "view_image", "goals",
    )},
    **({"windows.sandbox": "elevated"} if os.name == "nt" else {}),
}
INSTRUCTIONS = "Work only on the supplied experiment task and permitted workspace. External capabilities are disabled."


class ExperimentBoundaryError(RuntimeError):
    """A content-free failure code suitable for a remote task receipt."""


def reject(code):
    raise ExperimentBoundaryError("experiment_boundary_" + code)


def _path(value, *, exists=True):
    if not isinstance(value, (str, os.PathLike)) or not str(value):
        reject("invalid_path")
    path = Path(value).absolute()
    for part in (path, *path.parents):
        if (part.is_symlink() or getattr(part, "is_junction", lambda: False)()
                or (os.name == "nt" and part.exists()
                    and getattr(part.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT)):
            reject("linked_path")
    return path.resolve(strict=exists)


def _within(path, parent):
    return path == parent or parent in path.parents


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _value(config, key):
    for part in key.split("."):
        if not isinstance(config, dict) or part not in config:
            return None
        config = config[part]
    return config


def runtime_private_roots(env):
    """Locations that can hold prior answers, credentials or host task evidence."""
    home = Path.home()
    roots = [home / ".codex", home / "GalaxySSI", Path(env.get("APPDATA") or home) / "GalaxySSI",
             home / "GalaxySSI_Workspace" / "tasks"]
    for key in ("CODEX_HOME", "GALAXYSSI_STATE_DIR"):
        if env.get(key, "").strip():
            roots.append(Path(env[key]).expanduser())
    if env.get("GALAXYSSI_WORKSPACE_ROOT", "").strip():
        roots.append(Path(env["GALAXYSSI_WORKSPACE_ROOT"]).expanduser() / "tasks")
    # SQLite sidecars and Electron's backend.log live beside these paths.
    for key in ("GALAXYSSI_DATABASE_PATH", "GALAXYSSI_CONFIG_PATH", "GALAXYSSI_DATA_DIR"):
        if env.get(key, "").strip():
            roots.append(Path(env[key]).expanduser().parent)
    return tuple(sorted({str(_path(root, exists=False)) for root in roots}))


class CodexExperimentBoundary:
    def __init__(self, *, scope_id, workspace, protected_root, state_path,
                 model, effort, conversation_ids, mcp_names=(), skill_paths=(), read_only=False, denied_roots=()):
        if (not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", str(scope_id))
                or not isinstance(model, str) or not model.strip() or len(model) > 200
                or effort not in {"low", "medium", "high", "xhigh"}):
            reject("invalid_selection")
        self.workspace, self.protected_root = _path(workspace), _path(protected_root)
        self.state_path = _path(state_path, exists=False)
        if (not self.workspace.is_dir() or not self.protected_root.is_dir()
                or _within(self.workspace, self.protected_root) or _within(self.protected_root, self.workspace)
                or not _within(self.state_path, self.protected_root)
                or self.state_path == self.protected_root):
            reject("overlapping_or_unprotected_paths")
        for path in (self.workspace, self.protected_root):
            if any((parent / ".git").exists() for parent in (path, *path.parents)):
                reject("git_directory")
        self.conversation_ids = frozenset(conversation_ids)
        if not self.conversation_ids or any(not isinstance(x, str) or not x.strip() or len(x) > 200 for x in self.conversation_ids):
            reject("conversation_scope")
        if any(not isinstance(x, str) or not x or len(x) > 200 or any(ord(c) < 32 for c in x) for x in mcp_names):
            reject("mcp_names")
        self.skill_paths = tuple(sorted({str(_path(x)) for x in skill_paths}))
        self.mcp_names = tuple(sorted(set(mcp_names)))
        if type(read_only) is not bool:
            reject("invalid_read_only")
        self.model, self.effort, self.read_only = model, effort, read_only
        self.denied_roots = tuple(sorted({str(_path(path, exists=False)) for path in denied_roots}
            | set(runtime_private_roots(os.environ))))
        if any(_within(self.workspace, Path(path)) or _within(Path(path), self.workspace) for path in self.denied_roots):
            reject("overlapping_denied_roots")
        self.fingerprint = _digest({"scope": scope_id, "workspace": str(self.workspace),
            "protected": str(self.protected_root), "state": str(self.state_path), "model": model,
            "effort": effort, "conversations": sorted(self.conversation_ids),
            "mcp_names": self.mcp_names, "skill_paths": self.skill_paths, "flags": FLAGS,
            "read_only": read_only, "denied_roots": self.denied_roots})
        self.profile = "galaxyssi-eval-" + self.fingerprint[:24]
        self._lock = threading.RLock()
        self._threads, self._conversations, self._verified_threads = {}, {}, set()
        self.runtime_verified = False
        if self.state_path.exists():
            if not self.state_path.is_file() or self.state_path.stat().st_size > 1024 * 1024:
                reject("state_invalid")
            try:
                value = json.loads(self.state_path.read_text(encoding="utf-8"))
                threads, conversations = value["threads"], value["conversations"]
                if (value["format"] != FORMAT or value["fingerprint"] != self.fingerprint
                        or not isinstance(threads, dict) or not isinstance(conversations, dict)
                        or any(not isinstance(k, str) or not k or len(k) > 200 for k in threads)
                        or any(not isinstance(v, dict) or set(v) != {"cwd"} for v in threads.values())
                        or any(not isinstance(k, str) or v not in threads for k, v in conversations.items())):
                    reject("state_mismatch")
                for row in threads.values():
                    self.check_workspace(row["cwd"])
                self._threads, self._conversations = threads, conversations
            except (ValueError, KeyError, TypeError):
                reject("state_invalid")

    def check_workspace(self, cwd):
        path = _path(cwd)
        if not path.is_dir() or not _within(path, self.workspace):
            reject("workspace_scope")
        return str(path)

    def verify_storage_environment(self, env):
        roots = (str(self.protected_root), *self.denied_roots)
        for root in roots:
            if str(_path(root, exists=False)) != root:
                reject("protected_path_changed")
        self.verify_private_locations(runtime_private_roots(env))

    def verify_private_locations(self, paths):
        roots = (str(self.protected_root), *self.denied_roots)
        for value in paths:
            required = _path(value, exists=False)
            if not any(_within(Path(required), Path(root)) for root in roots):
                reject("unprotected_runtime_storage")

    def admit(self, conversation_id, cwd, model, effort, images=()):
        if conversation_id not in self.conversation_ids:
            reject("conversation_scope")
        if model != self.model or effort != self.effort:
            reject("selection_changed")
        if images:
            reject("nontext_input_not_verified")
        self.check_workspace(cwd)

    def process_overrides(self):
        self.verify_storage_environment(os.environ)
        values = {**FLAGS, "model_reasoning_effort": self.effort, "default_permissions": self.profile}
        overrides = [key + "=" + json.dumps(value) for key, value in values.items()]
        fs = {":root": "read", ":minimal": "read", ":tmpdir": "deny", ":slash_tmp": "deny",
              str(self.protected_root): "deny", str(self.workspace): "read" if self.read_only else "write"}
        fs.update({path: "deny" for path in self.denied_roots})
        parent = ":read-only" if self.read_only else ":workspace"
        overrides.append("permissions." + self.profile + '={extends=' + json.dumps(parent) + ',network={enabled=false},filesystem={'
                         + ",".join(json.dumps(k) + "=" + json.dumps(v) for k, v in fs.items()) + "}}")
        overrides.append("mcp_servers={" + ",".join(json.dumps(k) + "={enabled=false}" for k in self.mcp_names) + "}")
        overrides.append("skills.config=[" + ",".join("{path=" + json.dumps(p) + ",enabled=false}" for p in self.skill_paths) + "]")
        return overrides

    def reset_process(self):
        with self._lock:
            self.runtime_verified = False
            self._verified_threads.clear()

    def verify_runtime(self, request):
        result = request("config/read", {"cwd": str(self.workspace), "includeLayers": False}, 30)
        config = result.get("config", {})
        if any(type(_value(config, key)) is not type(value) or _value(config, key) != value for key, value in FLAGS.items()):
            reject("effective_flags")
        if config.get("default_permissions") != self.profile:
            reject("default_permissions")
        self.verify_private_locations([config[key] for key in ("sqlite_home", "log_dir")
                                       if config.get(key) not in (None, "")])
        servers = config.get("mcp_servers", {})
        if not isinstance(servers, dict) or any(not isinstance(v, dict) or v.get("enabled") is not False for v in servers.values()):
            reject("mcp_config")
        for key in ("model_instructions_file", "experimental_compact_prompt_file", "compact_prompt"):
            if config.get(key) not in (None, ""):
                reject("inherited_instructions")
        self._verify_skills(request, str(self.workspace))
        self.runtime_verified = True

    def _verify_skills(self, request, cwd):
        value = request("skills/list", {"cwds": [cwd], "forceReload": True}, 30)
        rows = value.get("data")
        if (not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict)
                or rows[0].get("cwd") != cwd or rows[0].get("errors") != []
                or not isinstance(rows[0].get("skills"), list)
                or any(not isinstance(s, dict) or s.get("enabled") is not False for s in rows[0]["skills"])):
            reject("skill_inventory")

    def prepare(self, method, params):
        safe = {"initialize", "config/read", "skills/list", "mcpServerStatus/list"}
        if method in safe:
            return params
        if method not in {"thread/start", "thread/resume", "thread/read", "thread/unsubscribe", "turn/start", "turn/steer", "turn/interrupt"}:
            reject("rpc_not_allowed")
        allowed = {
            "thread/start": {"cwd", "model", "ephemeral", "approvalPolicy", "sandbox", "config", "developerInstructions", "dynamicTools"},
            "thread/resume": {"threadId", "cwd", "model", "approvalPolicy", "sandbox", "config", "developerInstructions"},
            "thread/read": {"threadId", "includeTurns"}, "thread/unsubscribe": {"threadId"},
            "turn/start": {"threadId", "input", "model", "effort", "cwd"},
            "turn/steer": {"threadId", "input", "expectedTurnId"}, "turn/interrupt": {"threadId", "turnId"},
        }
        if not isinstance(params, dict) or set(params) - allowed[method]:
            reject("rpc_fields_not_allowed")
        if not self.runtime_verified:
            reject("runtime_not_verified")
        result = dict(params)
        identifier = result.get("threadId")
        if method != "thread/start" and identifier not in self._threads:
            reject("thread_not_owned")
        if method in {"thread/start", "thread/resume"}:
            if result.get("sandbox") == "read-only" and not self.read_only:
                reject("read_only_profile_not_verified")
            cwd = self.check_workspace(result.get("cwd") or self._threads.get(identifier, {}).get("cwd"))
            if result.get("model", self.model) != self.model:
                reject("selection_changed")
            result.pop("sandbox", None)
            result.update(cwd=cwd, model=self.model, permissions=self.profile, approvalPolicy="never",
                config={**FLAGS, "model_reasoning_effort": self.effort}, developerInstructions=INSTRUCTIONS,
                runtimeWorkspaceRoots=[])
            if method == "thread/start":
                result.update(ephemeral=False, dynamicTools=[], environments=[], selectedCapabilityRoots=[],
                              allowProviderModelFallback=False)
        if method in {"turn/start", "turn/steer"}:
            if identifier not in self._verified_threads:
                reject("thread_not_verified")
            inputs = result.get("input")
            if (not isinstance(inputs, list) or not inputs
                    or any(not isinstance(x, dict) or set(x) - {"type", "text", "text_elements"}
                           or x.get("type") != "text" or not isinstance(x.get("text"), str)
                           or x.get("text_elements", []) != [] for x in inputs)):
                reject("nontext_input_not_verified")
            if method == "turn/start":
                self.check_workspace(result.get("cwd"))
                if result.get("model") != self.model or result.get("effort") != self.effort:
                    reject("selection_changed")
        return result

    def verify_thread(self, method, params, result, request):
        identifier = (result.get("thread") or {}).get("id")
        if (not isinstance(identifier, str) or not identifier or len(identifier) > 200
                or (method == "thread/resume" and identifier != params["threadId"])
                or (result.get("activePermissionProfile") or {}).get("id") != self.profile
                or result.get("approvalPolicy") != "never" or result.get("model") != self.model
                or result.get("reasoningEffort") != self.effort or result.get("cwd") != params["cwd"]
                or result.get("runtimeWorkspaceRoots") != [] or result.get("instructionSources") != []):
            reject("thread_policy")
        self.verify_capabilities(identifier, params["cwd"], request)
        with self._lock:
            self._threads[identifier] = {"cwd": params["cwd"]}
            self._persist()
            self._verified_threads.add(identifier)

    def verify_capabilities(self, identifier, cwd, request):
        self._verify_skills(request, cwd)
        value = request("mcpServerStatus/list", {"threadId": identifier}, 30)
        rows = value.get("data")
        if (not isinstance(rows, list) or value.get("nextCursor") is not None
                or any(not isinstance(r, dict) or r.get("runtimeStatus") != "disabled" or r.get("tools") != {}
                       or r.get("resources") != [] or r.get("resourceTemplates") != []
                       or r.get("toolsError") is not None for r in rows)):
            reject("mcp_inventory")

    def conversations(self):
        with self._lock:
            return dict(self._conversations)

    def save_conversations(self, values):
        with self._lock:
            if any(value not in self._threads for value in values.values()):
                reject("thread_not_owned")
            self._conversations = dict(values)
            self._persist()

    def _persist(self):
        _path(self.state_path, exists=False)
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        value = {"format": FORMAT, "fingerprint": self.fingerprint,
                 "threads": self._threads, "conversations": self._conversations}
        fd, temporary = tempfile.mkstemp(prefix=".boundary-", suffix=".json", dir=self.state_path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(value, stream, ensure_ascii=True, allow_nan=False)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.state_path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
