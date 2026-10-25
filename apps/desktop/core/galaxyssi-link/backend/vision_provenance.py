"""Recover image turn provenance from the current task's private request snapshot."""
from pathlib import Path


def source_turn(value) -> str:
    if not isinstance(value, str):
        return ""
    return "".join(c for c in value if c.isascii() and (c.isalnum() or c in "-_.:"))[:128]


def image_source_turns(paths: list[str], attachments: list[dict]) -> dict[str, str]:
    # Match only files already admitted to this task, never open a descriptor path.
    by_name = {Path(path).name: path for path in paths}
    result = {}
    for index, item in enumerate(attachments[:12]):
        if not isinstance(item, dict):
            continue
        turn = source_turn(item.get("historical_source_turn_id"))
        if not turn:
            continue
        name = Path(str(item.get("name") or f"attachment-{index + 1}")).name[:180]
        path = by_name.get(f"{index + 1:02d}-{name}")
        if path is None and len(paths) == len(attachments) == 1:
            path = by_name.get(name)
        if path:
            result[path] = turn
    return result


def task_image_source_turns(task_id: str, paths: list[str]) -> dict[str, str]:
    if not task_id or not paths:
        return {}
    from agent_request_snapshot import restore_request_options
    from agent_task_manager import agent_task_manager
    options = restore_request_options(agent_task_manager.recovery_request(task_id))
    return image_source_turns(paths, options.get("attachments", []))


def history_label(turn: str) -> str:
    return (
        f"Historical image reference from earlier turn {source_turn(turn)} (not a new upload). "
        "Use it only if relevant to the latest question. Replay alone does not request a repeat "
        "of the earlier image task. Do not prefix the answer with orientation, rotation, or "
        "transcription reports unless requested or a specific ambiguity affects the answer."
    )
