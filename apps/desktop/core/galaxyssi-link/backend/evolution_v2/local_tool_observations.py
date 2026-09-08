"""Stable file-action observations with a content-free durable projection."""
from __future__ import annotations

import errno
import json


class WorkspaceToolError(ValueError):
    def __init__(self, code: str, detail: str):
        super().__init__(detail)
        self.code = code


def failure_observation(error, stage):
    if isinstance(error, WorkspaceToolError):
        code, detail = error.code, str(error)
    elif stage == "model_action_parse":
        code = "invalid_action_json"
        detail = ("Your model reply was not exactly ONE action JSON object. No file action ran. "
                  "This is not a source-file parsing error. Return one action and wait for its observation.")
        if isinstance(error, json.JSONDecodeError):
            detail += f" Parser: {error.msg}, line {error.lineno}, column {error.colno}."
    elif isinstance(error, UnicodeDecodeError):
        code, detail = "non_utf8_source", "The source file is not valid UTF-8 text."
    elif isinstance(error, UnicodeEncodeError):
        code, detail = "invalid_utf8_text", "The write text cannot be encoded as UTF-8."
    elif isinstance(error, OSError):
        code, detail = {
            errno.ENOENT: ("file_not_found", "The requested source path does not exist."),
            errno.EACCES: ("file_access_denied", "The operating system denied file access."),
            errno.EPERM: ("file_access_denied", "The operating system denied file access."),
            errno.ENOSPC: ("storage_full", "The storage device has no free space."),
            errno.EISDIR: ("expected_file", "The requested path is a directory, not a file."),
            errno.ENOTDIR: ("expected_directory", "A path component is not a directory."),
        }.get(error.errno, ("file_io_failed", "The operating system reported a file I/O failure."))
    else:
        code, detail = "invalid_action", "The action does not match the required tool arguments."
    return {"ok": False, "stage": stage, "error": type(error).__name__, "error_code": code,
            "detail": detail, "effect": "unknown" if isinstance(error, OSError) else "not_applied"}


def durable_observation(action, observation, step):
    operation = action.get("operation") if isinstance(action, dict) else None
    if not isinstance(operation, str) or operation not in {"list", "read", "write", "edit", "append", "finish", "ci_checks", "ci_log"}:
        operation = "invalid"
    return {"operation": operation, "tool_step": step, "ok": observation["ok"],
            "stage": observation["stage"], "error_code": observation.get("error_code", ""),
            "effect": observation.get("effect", "read_only")}
