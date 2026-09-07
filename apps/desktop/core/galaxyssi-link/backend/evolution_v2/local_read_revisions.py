"""Bounded read receipts; model-facing IDs never replace file-content validation."""
from __future__ import annotations

from collections import OrderedDict
import secrets

from .local_tool_observations import WorkspaceToolError


class ReadRevisions:
    def __init__(self):
        self._prefix = secrets.token_hex(4)
        self._sequence = 0
        self._values = OrderedDict()

    def remember(self, path, digest):
        for key, value in self._values.items():
            if value == (path, digest):
                self._values.move_to_end(key)
                return key
        self._sequence += 1
        key = f"r{self._prefix}-{self._sequence}"
        self._values[key] = (path, digest)
        while len(self._values) > 128:
            self._values.popitem(last=False)
        return key

    def resolve(self, key, path):
        if not isinstance(key, str) or key not in self._values:
            raise WorkspaceToolError("read_revision_unknown", "Read the file first and use its returned read_revision; expired or invented revisions cannot be used")
        expected_path, digest = self._values[key]
        if path != expected_path:
            raise WorkspaceToolError("read_revision_path_mismatch", "This read_revision belongs to a different path; read the target file")
        self._values.move_to_end(key)
        return digest
