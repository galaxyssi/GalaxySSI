"""Structured model decisions for bounded Agent recovery loops."""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import json
import re
from typing import Iterable

from conversation_context import ContextAttachment


RECOVERY_ACTION_HEADER = "[SIGNALASI_RECOVERY_ACTION_V1]"
RECOVERY_ACTION_FOOTER = "[/SIGNALASI_RECOVERY_ACTION_V1]"
MAX_RECOVERY_ATTACHMENTS = 10
MAX_RECOVERY_REASON_CHARACTERS = 600


class ModelRecoveryAction(str, Enum):
    REQUEST_ATTACHMENT = "request_attachment"
    RETRY = "retry"
    SWITCH_AGENT = "switch_agent"
    ASK_USER = "ask_user"
    ABORT = "abort"


@dataclass(frozen=True)
class ModelRecoveryDecision:
    action: ModelRecoveryAction
    attachment_ids: tuple[str, ...] = ()
    target_agent_id: str = ""
    reason: str = ""
    user_message: str = ""
    explicit: bool = True


@dataclass(frozen=True)
class ParsedModelRecovery:
    visible_reply: str
    decision: ModelRecoveryDecision | None


def recovery_contract(attachments: Iterable[ContextAttachment]) -> str:
    """Tell the executing model how to recover without exposing internal protocol text."""
    catalog = _catalog(attachments)
    available = json.dumps(catalog, ensure_ascii=True, separators=(",", ":"))
    return (
        "SignalASI recovery contract (internal control protocol):\n"
        "Continue the user's goal autonomously through observe, replan, verify, and finalize. "
        "Treat a prior attachment as ordinary multimodal conversation context: inspect the "
        "dialogue and infer the user's most likely useful intent instead of asking them to choose "
        "an attachment operation. "
        "Do not tell the user to re-upload a prior attachment when it is listed below. If its "
        "bytes are needed but no local file path is available, return only one recovery block "
        "using an exact artifact_id from the catalog. SignalASI will securely restore it and "
        "resume this same task. Use retry only for a genuinely transient failure, switch_agent "
        "only when another Agent is required, ask_user only when information cannot be recovered "
        "from tools or context, and abort only when continuing would be unsafe. Never invent IDs.\n"
        f"Prior attachment catalog: {available}\n"
        "Recovery block schema:\n"
        f"{RECOVERY_ACTION_HEADER}\n"
        '{"version":1,"action":"request_attachment|retry|switch_agent|ask_user|abort",'
        '"attachment_ids":["exact-id"],"target_agent_id":"",'
        '"reason":"brief reason summary","user_message":"only for ask_user or abort"}\n'
        f"{RECOVERY_ACTION_FOOTER}\n"
        "When no recovery action is needed, return the normal final answer and no recovery block."
    )


def recovery_follow_up(
    decision: ModelRecoveryDecision,
    paths: Iterable[str] = (),
) -> str:
    safe_paths = [str(value or "").strip() for value in paths if str(value or "").strip()]
    details = "\n".join(f"- {value}" for value in safe_paths)
    if decision.action == ModelRecoveryAction.REQUEST_ATTACHMENT:
        return (
            "SignalASI restored the attachment(s) you requested. Continue the same user goal "
            "from the previous observation. Inspect the files, replan if necessary, execute, "
            "verify the result, and return only the useful final response. Do not ask for these "
            "attachments again.\nAvailable verified files:\n"
            f"{details}"
        ).strip()
    if decision.action == ModelRecoveryAction.RETRY:
        return (
            "Retry the same goal from the latest verified checkpoint. Change the failed approach, "
            "observe the new result, and continue until verified or genuinely blocked."
        )
    return "Continue the same goal from the latest verified observation."


def parse_model_recovery(
    reply: str,
    attachments: Iterable[ContextAttachment] = (),
) -> ParsedModelRecovery:
    value = str(reply or "")
    available = _attachment_map(attachments)
    matches = list(_RECOVERY_BLOCK.finditer(value))
    if matches:
        match = matches[-1]
        visible = (value[:match.start()] + value[match.end():]).strip()
        decision = _decode_decision(match.group(1), available)
        return ParsedModelRecovery(visible_reply=visible, decision=decision)
    implicit = _implicit_attachment_decision(value, tuple(available.values()))
    return ParsedModelRecovery(visible_reply=value.strip(), decision=implicit)


def failure_review_prompt(
    *,
    goal: str,
    failure: str,
    attachments: Iterable[ContextAttachment] = (),
    available_agents: Iterable[str] = (),
) -> str:
    agents = [str(value or "").strip() for value in available_agents if str(value or "").strip()]
    return (
        "Act as SignalASI's recovery controller. Diagnose the failed execution from the bounded "
        "observation below, then choose one safe next action. Return exactly one recovery block "
        "and no prose. Do not repeat an approach that already failed.\n\n"
        f"Original goal:\n{str(goal or '').strip()[:8000]}\n\n"
        f"Observed failure:\n{str(failure or '').strip()[:4000]}\n\n"
        f"Available Agents: {json.dumps(agents, ensure_ascii=True)}\n\n"
        + recovery_contract(attachments)
    )


def _decode_decision(
    raw: str,
    available: dict[str, ContextAttachment],
) -> ModelRecoveryDecision | None:
    try:
        payload = json.loads(raw.strip())
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict) or int(payload.get("version") or 0) != 1:
        return None
    try:
        action = ModelRecoveryAction(str(payload.get("action") or "").strip())
    except ValueError:
        return None
    requested = payload.get("attachment_ids")
    attachment_ids: list[str] = []
    if isinstance(requested, list):
        for value in requested[:MAX_RECOVERY_ATTACHMENTS]:
            artifact_id = str(value or "").strip()
            if artifact_id and artifact_id in available and artifact_id not in attachment_ids:
                attachment_ids.append(artifact_id)
    if action == ModelRecoveryAction.REQUEST_ATTACHMENT and not attachment_ids:
        return None
    target_agent_id = _safe_text(payload.get("target_agent_id"), 120)
    if action == ModelRecoveryAction.SWITCH_AGENT and not target_agent_id:
        return None
    return ModelRecoveryDecision(
        action=action,
        attachment_ids=tuple(attachment_ids),
        target_agent_id=target_agent_id,
        reason=_safe_text(payload.get("reason"), MAX_RECOVERY_REASON_CHARACTERS),
        user_message=_safe_text(payload.get("user_message"), 2_000),
        explicit=True,
    )


def _implicit_attachment_decision(
    reply: str,
    attachments: tuple[ContextAttachment, ...],
) -> ModelRecoveryDecision | None:
    if not attachments:
        return None
    normalized = " ".join(str(reply or "").lower().split())
    if not normalized or not any(marker in normalized for marker in _MISSING_ACCESS_MARKERS):
        return None
    if not any(marker in normalized for marker in _ATTACHMENT_MARKERS):
        return None
    named = [item for item in attachments if item.name and item.name.lower() in normalized]
    if named:
        selected = named[-MAX_RECOVERY_ATTACHMENTS:]
    elif any(marker in normalized for marker in _IMAGE_MARKERS):
        selected = [item for item in attachments if item.kind == "image"][-1:]
    else:
        selected = list(attachments[-1:])
    ids = tuple(item.artifact_id for item in selected if item.artifact_id)
    if not ids:
        return None
    return ModelRecoveryDecision(
        action=ModelRecoveryAction.REQUEST_ATTACHMENT,
        attachment_ids=ids,
        reason="The executing model reported that required prior attachment bytes were unavailable",
        explicit=False,
    )


def _catalog(attachments: Iterable[ContextAttachment]) -> list[dict]:
    return [
        {
            "artifact_id": item.artifact_id,
            "kind": item.kind,
            "name": item.name,
            "mime_type": item.mime_type,
            "size_bytes": item.size_bytes,
            "turn_id": item.group_id,
        }
        for item in _attachment_map(attachments).values()
    ]


def _attachment_map(attachments: Iterable[ContextAttachment]) -> dict[str, ContextAttachment]:
    result: dict[str, ContextAttachment] = {}
    for item in attachments:
        artifact_id = str(item.artifact_id or "").strip()
        if artifact_id and len(artifact_id) <= 120:
            result[artifact_id] = item
    return result


def _safe_text(value: object, maximum: int) -> str:
    return " ".join(str(value or "").split())[:maximum]


_RECOVERY_BLOCK = re.compile(
    re.escape(RECOVERY_ACTION_HEADER) + r"\s*(.*?)\s*" + re.escape(RECOVERY_ACTION_FOOTER),
    re.DOTALL,
)
_MISSING_ACCESS_MARKERS = (
    "cannot access", "can't access", "cannot see", "can't see", "do not have access",
    "not available", "not attached", "missing attachment", "upload again", "re-upload",
    "provide the image", "provide the file", "send the image", "send the file",
    "\u65e0\u6cd5\u8bbf\u95ee", "\u65e0\u6cd5\u770b\u5230", "\u770b\u4e0d\u5230",
    "\u6ca1\u6709\u56fe\u7247", "\u6ca1\u6709\u9644\u4ef6", "\u672a\u6536\u5230\u56fe\u7247",
    "\u8bf7\u91cd\u65b0\u4e0a\u4f20", "\u8bf7\u518d\u53d1", "\u8bf7\u63d0\u4f9b\u56fe\u7247",
)
_ATTACHMENT_MARKERS = (
    "attachment", "image", "photo", "picture", "file", "document",
    "\u9644\u4ef6", "\u56fe\u7247", "\u7167\u7247", "\u56fe\u50cf", "\u6587\u4ef6", "\u6587\u6863",
)
_IMAGE_MARKERS = ("image", "photo", "picture", "\u56fe\u7247", "\u7167\u7247", "\u56fe\u50cf")
