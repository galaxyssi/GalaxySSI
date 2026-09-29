"""Recover an explicitly referenced delivered output without a phone round trip."""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Iterable

from conversation_artifacts import (
    MAX_CONTEXT_ARTIFACTS, MAX_CONTEXT_ARTIFACT_BYTES, MAX_CONTEXT_TOTAL_BYTES,
    _task_output_candidates, stage_conversation_artifacts,
)
from conversation_context import MobileConversationContext


def restore_delivered_outputs(
    context: MobileConversationContext, task_history: Iterable[dict],
    requested_ids: Iterable[str], *, conversation_id: str, current_task_id: str,
) -> dict[str, Path]:
    if not conversation_id or not current_task_id:
        return {}
    requested = set(list(dict.fromkeys(requested_ids))[:MAX_CONTEXT_ARTIFACTS])
    expected = {item.artifact_id: item for item in context.attachments
                if item.artifact_id in requested and item.group_id
                and re.fullmatch(r"artifact-[0-9a-f]{24}", item.artifact_id)}
    if not expected:
        return {}
    # The authenticated backend conversation ID includes the client identity.
    tasks = [task for task in task_history
             if task.get("conversation_id") == conversation_id
             and task.get("task_id") != current_task_id
             and task.get("status") == "completed"]
    result: dict[str, Path] = {}
    digests: dict[Path, str] = {}
    hashed_bytes = 0
    for attachment_id, attachment in expected.items():
        for task in tasks:
            if task.get("client_turn_id") != attachment.group_id:
                continue
            candidates = _task_output_candidates(task)
            candidates.sort(key=lambda path: path.name != attachment.name)
            for source in candidates:
                try:
                    if source not in digests:
                        hashed_bytes += source.stat().st_size
                        if hashed_bytes > MAX_CONTEXT_TOTAL_BYTES:
                            return result
                        digests[source] = _digest(source)
                    if attachment_id != "artifact-" + digests[source][:24]:
                        continue
                    staged = stage_conversation_artifacts(current_task_id, [source])
                    if staged and _digest(staged[0]) == digests[source]:
                        result[attachment_id] = staged[0]
                        break
                except (OSError, ValueError):
                    continue
            if attachment_id in result:
                break
    return result


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(64 * 1024), b""):
            size += len(chunk)
            if size > MAX_CONTEXT_ARTIFACT_BYTES:
                raise ValueError("Conversation artifact grew beyond the recovery limit")
            digest.update(chunk)
    return digest.hexdigest()
