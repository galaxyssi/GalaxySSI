"""Safe restoration of prior conversation inputs into a new Agent task."""
from __future__ import annotations

import filecmp
import re
import shutil
from pathlib import Path
from typing import Iterable

from conversation_context import ContextAttachment, MobileConversationContext
import task_workspace


MAX_CONTEXT_ARTIFACTS = 10
MAX_CONTEXT_ARTIFACT_BYTES = 64 * 1024 * 1024
MAX_CONTEXT_TOTAL_BYTES = 128 * 1024 * 1024
_TRANSPORT_PREFIX = re.compile(r"^\d{2}-")


def conversation_input_artifact_paths(
    context: MobileConversationContext,
    task_history: Iterable[dict],
    *,
    current_task_id: str = "",
    limit: int = MAX_CONTEXT_ARTIFACTS,
) -> list[Path]:
    """Resolve referenced inputs only from prior tasks in this conversation."""
    safe_limit = max(1, min(int(limit or 1), MAX_CONTEXT_ARTIFACTS))
    tasks_by_turn: dict[str, list[dict]] = {}
    for task in task_history:
        task_id = str(task.get("task_id") or "").strip()
        turn_id = str(task.get("client_turn_id") or "").strip()
        if not task_id or task_id == current_task_id or not turn_id:
            continue
        tasks_by_turn.setdefault(turn_id, []).append(task)
    for tasks in tasks_by_turn.values():
        tasks.sort(
            key=lambda item: (
                int(item.get("created_at") or 0),
                str(item.get("task_id") or ""),
            ),
            reverse=True,
        )

    tasks_root = (task_workspace.workspace_root() / "tasks").resolve()
    resolved: list[Path] = []
    seen: set[str] = set()
    attachments_by_turn: dict[str, list[ContextAttachment]] = {}
    for attachment in context.attachments:
        if not attachment.group_id:
            continue
        attachments_by_turn.setdefault(attachment.group_id, []).append(attachment)

    for turn_id, expected_attachments in reversed(tuple(attachments_by_turn.items())):
        for task in tasks_by_turn.get(turn_id, ()):
            task_id = _safe_component(task.get("task_id"))
            if not task_id:
                continue
            input_root = (tasks_root / task_id / "downloads" / "input").resolve()
            if not _is_within(input_root, tasks_root) or not input_root.is_dir():
                continue
            candidates = [
                path for path in sorted(input_root.iterdir())
                if _valid_input_file(path, input_root)
            ]
            selected = _match_turn_artifacts(expected_attachments, candidates)
            for path in selected:
                key = str(path).casefold()
                if key in seen:
                    continue
                seen.add(key)
                resolved.append(path)
                if len(resolved) >= safe_limit:
                    return resolved
            if selected:
                break
    return resolved


def stage_conversation_input_artifacts(
    task_id: str,
    sources: Iterable[Path],
    *,
    limit: int = MAX_CONTEXT_ARTIFACTS,
) -> list[Path]:
    """Copy prior inputs into the current task before giving paths to an Agent."""
    safe_limit = max(1, min(int(limit or 1), MAX_CONTEXT_ARTIFACTS))
    current_root = task_workspace.task_workspace(task_id).resolve()
    destination = (current_root / "downloads" / "context").resolve()
    if not _is_within(destination, current_root):
        raise ValueError("Conversation artifact destination escaped the task workspace")
    destination.mkdir(parents=True, exist_ok=True)
    tasks_root = (task_workspace.workspace_root() / "tasks").resolve()
    staged: list[Path] = []
    total_bytes = 0
    for source_value in sources:
        source_candidate = Path(source_value)
        if source_candidate.is_symlink():
            continue
        source = source_candidate.resolve()
        try:
            relative = source.relative_to(tasks_root)
        except ValueError:
            continue
        if (
            len(relative.parts) < 4
            or relative.parts[1:3] != ("downloads", "input")
            or not source.is_file()
        ):
            continue
        size = source.stat().st_size
        if size <= 0 or size > MAX_CONTEXT_ARTIFACT_BYTES:
            continue
        if total_bytes + size > MAX_CONTEXT_TOTAL_BYTES:
            break
        target = _unique_target(destination, _TRANSPORT_PREFIX.sub("", source.name), source)
        if not target.exists():
            shutil.copy2(source, target)
        staged.append(target)
        total_bytes += size
        if len(staged) >= safe_limit:
            break
    return staged


def _valid_input_file(path: Path, input_root: Path) -> bool:
    try:
        if path.is_symlink():
            return False
        resolved = path.resolve()
        return (
            _is_within(resolved, input_root)
            and resolved.is_file()
            and 0 < resolved.stat().st_size <= MAX_CONTEXT_ARTIFACT_BYTES
        )
    except OSError:
        return False


def _match_turn_artifacts(
    expected_attachments: list[ContextAttachment],
    candidates: list[Path],
) -> list[Path]:
    expected = [attachment for attachment in expected_attachments if attachment.name]
    if not expected or not candidates:
        return []
    remaining = list(candidates)
    selected: list[Path] = []
    unmatched = []
    for attachment in expected:
        expected_name = Path(attachment.name).name.casefold()
        match = next(
            (
                path
                for path in remaining
                if _TRANSPORT_PREFIX.sub("", path.name).casefold() == expected_name
                or path.name.casefold() == expected_name
            ),
            None,
        )
        if match is None:
            expected_stem = Path(expected_name).stem
            stem_matches = [
                path
                for path in remaining
                if Path(_TRANSPORT_PREFIX.sub("", path.name).casefold()).stem == expected_stem
            ]
            if len(stem_matches) == 1:
                match = stem_matches[0]
        if match is None:
            unmatched.append(attachment)
            continue
        remaining.remove(match)
        selected.append(match)

    if unmatched and len(unmatched) == len(remaining):
        selected.extend(remaining)
    return selected


def _unique_target(directory: Path, name: str, source: Path) -> Path:
    safe_name = Path(name).name[:180] or "attachment"
    target = directory / safe_name
    serial = 2
    while target.exists():
        if target.is_file() and filecmp.cmp(target, source, shallow=False):
            return target
        target = directory / f"{Path(safe_name).stem}-{serial}{Path(safe_name).suffix}"
        serial += 1
    return target


def _safe_component(value: object) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value or "").strip())
    normalized = normalized.strip(".-")[:96]
    return normalized if normalized not in {"", ".", ".."} else ""


def _is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False
