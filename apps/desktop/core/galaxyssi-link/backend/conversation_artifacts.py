"""Safe restoration of prior conversation artifacts into a new Agent task."""
from __future__ import annotations

import filecmp
import re
import shutil
from pathlib import Path
from typing import Iterable

from conversation_context import (
    CURRENT_REQUEST_MARKER,
    ContextAttachment,
    MobileConversationContext,
)
import task_workspace


MAX_CONTEXT_ARTIFACTS = 10
MAX_CONTEXT_ARTIFACT_BYTES = 64 * 1024 * 1024
MAX_CONTEXT_TOTAL_BYTES = 128 * 1024 * 1024
_TRANSPORT_PREFIX = re.compile(r"^\d{2}-")
_ARTIFACT_SUFFIXES = {
    ".7z", ".apk", ".csv", ".doc", ".docx", ".gif", ".html", ".jpeg", ".jpg",
    ".json", ".md", ".mp3", ".mp4", ".pdf", ".png", ".ppt", ".pptx", ".py",
    ".tar", ".tgz", ".txt", ".wav", ".webp", ".xls", ".xlsx", ".xml", ".zip",
}
_ARTIFACT_TYPE_TERMS = {
    ".7z": ("7z",),
    ".apk": ("apk",),
    ".csv": ("csv",),
    ".doc": ("doc", "document"),
    ".docx": ("docx", "document"),
    ".gif": ("gif", "image"),
    ".html": ("html", "web page"),
    ".jpeg": ("jpeg", "image"),
    ".jpg": ("jpg", "image"),
    ".json": ("json",),
    ".md": ("markdown",),
    ".mp3": ("mp3", "audio"),
    ".mp4": ("mp4", "video"),
    ".pdf": ("pdf", "document"),
    ".png": ("png", "image"),
    ".ppt": ("ppt", "presentation"),
    ".pptx": ("pptx", "presentation"),
    ".py": ("python file", "source"),
    ".tar": ("tar", "archive"),
    ".tgz": ("tgz", "archive"),
    ".txt": ("text file",),
    ".wav": ("wav", "audio"),
    ".webp": ("webp", "image"),
    ".xls": ("xls", "spreadsheet"),
    ".xlsx": ("xlsx", "spreadsheet"),
    ".xml": ("xml",),
    ".zip": ("zip", "archive"),
}
_CONTINUATION_ACTIONS = (
    "continue", "update", "modify", "edit", "change", "fix", "refine", "revise",
    "regenerate", "rebuild", "improve", "use", "return", "send", "export",
    "\u7ee7\u7eed", "\u66f4\u65b0", "\u4fee\u6539", "\u6539\u4e00\u4e0b",
    "\u4fee\u590d", "\u4f18\u5316", "\u91cd\u65b0", "\u4f7f\u7528", "\u8fd4\u56de",
    "\u53d1\u56de", "\u5bfc\u51fa",
)
_CONTINUATION_REFERENCES = (
    "same project", "same file", "same image", "same document", "previous",
    "latest", "last one", "that file", "this file", "that image", "this image",
    "it", "project", "source", "attachment", "artifact",
    "\u540c\u4e00\u4e2a\u9879\u76ee", "\u540c\u4e00\u4e2a\u6587\u4ef6",
    "\u4e0a\u4e00\u4e2a", "\u4e0a\u4e00\u8f6e", "\u521a\u624d", "\u4e4b\u524d",
    "\u8fd9\u4e2a\u6587\u4ef6", "\u90a3\u4e2a\u6587\u4ef6", "\u8fd9\u5f20\u56fe",
    "\u90a3\u5f20\u56fe", "\u9879\u76ee", "\u6e90\u7801", "\u9644\u4ef6",
)
_MULTIPLE_ARTIFACT_TERMS = (
    "all files", "all artifacts", "both files", "these files", "combine",
    "\u6240\u6709\u6587\u4ef6", "\u5168\u90e8\u6587\u4ef6",
    "\u8fd9\u4e9b\u6587\u4ef6", "\u4e24\u4e2a\u6587\u4ef6", "\u5408\u5e76",
)


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


def conversation_has_visual_context(context: MobileConversationContext) -> bool:
    """Return whether the retained conversation window contains a user image."""
    return any(
        attachment.kind.casefold() == "image"
        or attachment.mime_type.casefold().startswith("image/")
        or Path(attachment.name).suffix.casefold() in {".gif", ".jpeg", ".jpg", ".png", ".webp"}
        for attachment in context.attachments
    )


def conversation_output_artifact_paths(
    content: str,
    task_history: Iterable[dict],
    *,
    current_task_id: str = "",
    limit: int = MAX_CONTEXT_ARTIFACTS,
) -> list[Path]:
    """Resolve prior Agent outputs only when the current turn refers to them."""
    safe_limit = max(1, min(int(limit or 1), MAX_CONTEXT_ARTIFACTS))
    tasks = sorted(
        (
            task
            for task in task_history
            if str(task.get("task_id") or "").strip() != current_task_id
            and str(task.get("status") or "completed") == "completed"
        ),
        key=lambda item: (
            int(item.get("completed_at") or item.get("updated_at") or item.get("created_at") or 0),
            str(item.get("task_id") or ""),
        ),
        reverse=True,
    )
    candidates_by_task: list[list[Path]] = []
    for task in tasks:
        candidates = _task_output_candidates(task)
        if candidates:
            candidates_by_task.append(candidates)
    if not candidates_by_task:
        return []

    active_content = str(content or "")
    if CURRENT_REQUEST_MARKER in active_content:
        active_content = active_content.rsplit(CURRENT_REQUEST_MARKER, 1)[-1]
    normalized = " ".join(active_content.casefold().split())
    named = [
        path
        for candidates in candidates_by_task
        for path in candidates
        if path.name.casefold() in normalized
    ]
    if named:
        return _deduplicate_paths(named)[:safe_limit]
    if not _artifact_continuation_requested(normalized):
        return []

    requested_suffixes = {
        suffix
        for suffix, terms in _ARTIFACT_TYPE_TERMS.items()
        if any(_contains_term(normalized, term) for term in terms)
    }
    wants_multiple = any(term in normalized for term in _MULTIPLE_ARTIFACT_TERMS)
    for candidates in candidates_by_task:
        relevant = [
            path for path in candidates
            if not requested_suffixes or path.suffix.casefold() in requested_suffixes
        ]
        if not relevant:
            continue
        return relevant[:safe_limit] if wants_multiple else relevant[:1]
    return []


def stage_conversation_artifacts(
    task_id: str,
    sources: Iterable[Path],
    *,
    limit: int = MAX_CONTEXT_ARTIFACTS,
) -> list[Path]:
    """Copy trusted prior inputs or outputs into the current task."""
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
        if not _valid_conversation_source(source, relative):
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


def stage_conversation_input_artifacts(
    task_id: str,
    sources: Iterable[Path],
    *,
    limit: int = MAX_CONTEXT_ARTIFACTS,
) -> list[Path]:
    """Backward-compatible alias for staging trusted conversation artifacts."""
    return stage_conversation_artifacts(task_id, sources, limit=limit)


def _task_output_candidates(task: dict) -> list[Path]:
    task_id = _safe_component(task.get("task_id"))
    if not task_id:
        return []
    tasks_root = (task_workspace.workspace_root() / "tasks").resolve()
    task_root = (tasks_root / task_id).resolve()
    if not _is_within(task_root, tasks_root) or not task_root.is_dir():
        return []
    metadata = task.get("output_files")
    values = metadata if isinstance(metadata, list) and metadata else task_workspace.task_artifacts(task_id)
    candidates: list[Path] = []
    for value in values:
        if not isinstance(value, dict):
            continue
        relative_value = str(value.get("relative_path") or "").replace("\\", "/").strip("/")
        relative = Path(*relative_value.split("/")) if relative_value else Path()
        if (
            not relative_value
            or any(part in {"", ".", ".."} for part in relative.parts)
            or relative.parts[0].casefold() not in {"outputs", "downloads", "screenshots"}
        ):
            continue
        if (
            relative.parts[0].casefold() == "downloads"
            and len(relative.parts) > 1
            and relative.parts[1].casefold() in {"input", "context"}
        ):
            continue
        source = (task_root / relative).resolve()
        if not _valid_output_file(source, task_root):
            continue
        candidates.append(source)
    return sorted(
        _deduplicate_paths(candidates),
        key=lambda path: (path.stat().st_mtime_ns, path.name.casefold()),
        reverse=True,
    )


def _artifact_continuation_requested(normalized: str) -> bool:
    if not normalized:
        return False
    if normalized in {"continue", "continue.", "\u7ee7\u7eed", "\u7ee7\u7eed\u3002"}:
        return True
    has_action = any(term in normalized for term in _CONTINUATION_ACTIONS)
    has_reference = any(term in normalized for term in _CONTINUATION_REFERENCES)
    has_artifact_type = any(
        _contains_term(normalized, term)
        for terms in _ARTIFACT_TYPE_TERMS.values()
        for term in terms
    )
    return has_action and (has_reference or has_artifact_type)


def _contains_term(content: str, term: str) -> bool:
    if not term or term not in content:
        return False
    if not term.isascii() or " " in term:
        return True
    return re.search(rf"(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])", content) is not None


def _valid_conversation_source(source: Path, relative: Path) -> bool:
    if len(relative.parts) < 3 or not source.is_file():
        return False
    category = relative.parts[1].casefold()
    if category not in {"outputs", "downloads", "screenshots"}:
        return False
    return not (
        category == "downloads"
        and len(relative.parts) > 2
        and relative.parts[2].casefold() == "context"
    )


def _valid_output_file(source: Path, task_root: Path) -> bool:
    try:
        return (
            not source.is_symlink()
            and _is_within(source, task_root)
            and source.is_file()
            and source.suffix.casefold() in _ARTIFACT_SUFFIXES
            and 0 < source.stat().st_size <= MAX_CONTEXT_ARTIFACT_BYTES
        )
    except OSError:
        return False


def _deduplicate_paths(values: Iterable[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[str] = set()
    for path in values:
        key = str(path).casefold()
        if key in seen:
            continue
        seen.add(key)
        result.append(path)
    return result


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
