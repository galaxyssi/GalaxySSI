"""Exact text edits that preserve all bytes outside the requested change."""
from __future__ import annotations

from .local_tool_observations import WorkspaceToolError


def edited_bytes(original, action):
    original.decode("utf-8")
    if action["operation"] == "append":
        text = action.get("text")
        if not isinstance(text, str) or not text:
            raise WorkspaceToolError("invalid_append_text", "append requires nonempty text")
        return original + text.encode("utf-8")
    old, new = action.get("old_text"), action.get("new_text")
    if not isinstance(old, str) or not old or not isinstance(new, str) or old == new:
        raise WorkspaceToolError("invalid_edit_text", "edit requires nonempty old_text and different new_text")
    needle = old.encode("utf-8")
    start = original.find(needle)
    if start < 0 or original.find(needle, start + 1) >= 0:
        raise WorkspaceToolError("edit_match_missing" if start < 0 else "edit_match_ambiguous",
                                 "old_text must match exactly once. Read the file and include enough surrounding text to identify the intended change.")
    return original.replace(needle, new.encode("utf-8"), 1)
