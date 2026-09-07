"""Structured local file actions, not executable instructions supplied by the model."""
from __future__ import annotations


def action_schema():
    text = {"type": "string"}
    def action(name, fields, required):
        return {"type": "object", "properties": {"operation": {"const": name}, **fields},
                "required": ["operation", *required], "additionalProperties": False}
    return {"oneOf": [
        action("list", {"path": text, "after": text}, ["path"]),
        action("read", {"path": text, "offset": {"type": "integer", "minimum": 0}}, ["path"]),
        action("write", {"path": text, "expected_revision": {"type": ["string", "null"]}, "text": text},
               ["path", "expected_revision", "text"]),
        action("edit", {"path": text, "expected_revision": text, "old_text": {"type": "string", "minLength": 1},
                        "new_text": text}, ["path", "expected_revision", "old_text", "new_text"]),
        action("append", {"path": text, "expected_revision": text, "text": {"type": "string", "minLength": 1}},
               ["path", "expected_revision", "text"]),
        action("finish", {"summary": {"type": "string", "minLength": 1}}, ["summary"]),
    ]}
