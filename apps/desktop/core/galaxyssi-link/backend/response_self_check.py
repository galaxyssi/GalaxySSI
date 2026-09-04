"""Deterministic final-response checks against the latest user request."""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from enum import Enum
from typing import Iterable, Mapping


class ResponseSelfCheckStatus(str, Enum):
    PASSED = "passed"
    REPAIR = "repair"
    REJECTED = "rejected"


@dataclass(frozen=True)
class ResponseSelfCheckResult:
    status: ResponseSelfCheckStatus
    reasons: tuple[str, ...]
    request_digest: str
    response_digest: str
    actionable_request: bool
    has_attachments: bool

    @property
    def accepted(self) -> bool:
        return self.status == ResponseSelfCheckStatus.PASSED

    @property
    def diagnostic(self) -> str:
        if self.accepted:
            return "Final response addresses the latest user request."
        reasons = ", ".join(self.reasons) or "response_not_verified"
        return f"Final response did not pass latest-request self-check: {reasons}"

    def public(self) -> dict:
        return {
            "status": self.status.value,
            "accepted": self.accepted,
            "reasons": list(self.reasons),
            "request_digest": self.request_digest,
            "response_digest": self.response_digest,
            "actionable_request": self.actionable_request,
            "has_attachments": self.has_attachments,
        }


ACTION_TERMS = re.compile(
    r"\b(?:analy[sz]e|build|calculate|check|compare|convert|create|debug|delete|download|"
    r"edit|explain|export|extract|find|fix|generate|install|list|make|modify|"
    r"open|prepare|read|repair|research|review|run|save|search|send|set|show|"
    r"start|stop|summari[sz]e|test|translate|update|verify|write)\b|"
    r"(?:\u5206\u6790|\u8ba1\u7b97|\u521b\u5efa|\u6253\u5f00|\u5173\u95ed|\u4fee\u590d|"
    r"\u68c0\u67e5|\u67e5\u627e|\u641c\u7d22|\u603b\u7ed3|\u7ffb\u8bd1|"
    r"\u8fd0\u884c|\u6d4b\u8bd5|\u5b89\u88c5|\u751f\u6210|\u5236\u4f5c|"
    r"\u4fee\u6539|\u7f16\u8f91|\u5bfc\u51fa|\u4fdd\u5b58|\u53d1\u9001|"
    r"\u8bbe\u7f6e|\u8bfb\u53d6|\u67e5\u770b|\u5bf9\u6bd4|\u9a8c\u8bc1)",
    re.IGNORECASE,
)
GENERIC_REQUESTS = {
    "attached files",
    "attached file",
    "attachment",
    "file",
}
ACK_EXACT = {
    "got it",
    "got it.",
    "ok",
    "okay",
    "sure",
    "understood",
    "done",
    "completed",
    "working on it",
    "i will handle this",
    "i'll handle this",
    "\u597d\u7684",
    "\u6536\u5230",
    "\u660e\u767d",
    "\u5df2\u5b8c\u6210",
    "\u5904\u7406\u597d\u4e86",
}
ACKNOWLEDGEMENT_REQUESTS = {
    "ok",
    "okay",
    "thanks",
    "thank you",
    "got it",
    "\u597d\u7684",
    "\u8c22\u8c22",
    "\u6536\u5230",
    "\u660e\u767d",
}
ACK_START = re.compile(
    r"^(?:got it|okay|sure|understood|i(?:'ll| will| am going to)|"
    r"working on it|starting now|"
    r"\u597d\u7684|\u6536\u5230|\u660e\u767d|\u6211\u4f1a|\u6211\u5c06|"
    r"\u9a6c\u4e0a|\u6b63\u5728|\u5f00\u59cb\u5904\u7406)",
    re.IGNORECASE,
)
FUTURE_ONLY = re.compile(
    r"\b(?:will|going to|working on|starting|handle this|do that)\b|"
    r"(?:\u5c06\u4f1a|\u6211\u4f1a|\u9a6c\u4e0a|\u6b63\u5728|\u5f00\u59cb\u5904\u7406)",
    re.IGNORECASE,
)
MISSING_ATTACHMENT = re.compile(
    r"(?:no|without)\s+(?:an?\s+|any\s+)?(?:attachment|image|file)|"
    r"(?:cannot|can't|could not|couldn't)\s+(?:see|find|access)\s+"
    r"(?:the\s+|an?\s+|any\s+)?(?:attachment|image|file)|"
    r"(?:please\s+)?(?:upload|attach|send)\s+(?:the\s+|an?\s+)?(?:attachment|image|file)|"
    r"(?:\u6ca1\u6709|\u672a)\u6536\u5230(?:\u9644\u4ef6|\u56fe\u7247|\u6587\u4ef6)|"
    r"(?:\u770b\u4e0d\u5230|\u627e\u4e0d\u5230)(?:\u9644\u4ef6|\u56fe\u7247|\u6587\u4ef6)|"
    r"\u8bf7(?:\u4e0a\u4f20|\u53d1\u9001)(?:\u9644\u4ef6|\u56fe\u7247|\u6587\u4ef6)",
    re.IGNORECASE,
)
ASK_FOR_TASK_AGAIN = re.compile(
    r"(?:what|which)\s+(?:task|thing)\s+(?:should|would)\s+i|"
    r"what\s+would\s+you\s+like\s+me\s+to\s+do|"
    r"please\s+(?:provide|tell\s+me)\s+(?:the\s+)?(?:task|request|goal)|"
    r"(?:\u8bf7\u544a\u8bc9\u6211|\u4f60\u60f3\u8ba9\u6211|\u9700\u8981\u6211)"
    r"(?:\u505a\u4ec0\u4e48|\u5b8c\u6210\u4ec0\u4e48|\u5904\u7406\u4ec0\u4e48)",
    re.IGNORECASE,
)


def response_self_check_contract(
    latest_request: str,
    attachment_names: Iterable[str] = (),
) -> str:
    request = _bounded(latest_request, 12_000)
    attachments = _attachment_names(attachment_names)
    attachment_line = (
        "Attached inputs already available: " + ", ".join(attachments)
        if attachments
        else "No input attachment is bound to this turn."
    )
    return (
        "GalaxySSI final response self-check:\n"
        "- The latest user request below supersedes stale goals or plans.\n"
        "- Before finalizing, silently verify that the answer directly addresses it.\n"
        "- Do not return only an acknowledgement, progress promise, or completion claim.\n"
        "- Do not ask the user to resend an attachment that is listed as available.\n"
        "- Preserve verified results and clearly state any unmet requirement.\n"
        f"- {attachment_line}\n"
        f"- Request digest: {_digest(request)}\n\n"
        "Latest user request:\n"
        f"{request}"
    )


def response_repair_prompt(
    latest_request: str,
    previous_response: str,
    result: ResponseSelfCheckResult,
    attachment_names: Iterable[str] = (),
) -> str:
    attachments = _attachment_names(attachment_names)
    return (
        "Repair the final answer. The previous draft failed GalaxySSI's latest-request "
        f"self-check ({', '.join(result.reasons) or 'response_not_verified'}).\n"
        "Return only the corrected final answer. Do not return an acknowledgement or discuss "
        "this self-check. Use already available attachments instead of asking for them again.\n"
        f"Request digest: {result.request_digest}\n"
        + (
            "Available attachments: " + ", ".join(attachments) + "\n"
            if attachments else ""
        )
        + "\nLatest user request:\n"
        + _bounded(latest_request, 12_000)
        + "\n\nPrevious draft to replace:\n"
        + _bounded(previous_response, 4_000)
    )


def evaluate_response(
    latest_request: str,
    response: str,
    *,
    attachment_names: Iterable[str] = (),
    output_artifacts: Iterable[str] = (),
    expected_identity: Mapping[str, str] | None = None,
    response_identity: Mapping[str, str] | None = None,
) -> ResponseSelfCheckResult:
    request = _bounded(latest_request, 16_000)
    reply = _bounded(response, 32_000)
    attachments = _attachment_names(attachment_names)
    outputs = _attachment_names(output_artifacts)
    actionable = _is_actionable(request, bool(attachments))
    reasons: list[str] = []
    status = ResponseSelfCheckStatus.PASSED

    if not _identity_matches(expected_identity, response_identity):
        reasons.append("identity_mismatch")
        status = ResponseSelfCheckStatus.REJECTED
    elif not reply.strip() and not outputs:
        reasons.append("empty_response")
        status = ResponseSelfCheckStatus.REPAIR
    else:
        if attachments and MISSING_ATTACHMENT.search(reply):
            reasons.append("available_attachment_ignored")
        if actionable and ASK_FOR_TASK_AGAIN.search(reply):
            reasons.append("latest_request_ignored")
        if (
            not outputs
            and _is_acknowledgement_only(reply)
            and _normalized(request) not in ACKNOWLEDGEMENT_REQUESTS
        ):
            reasons.append("acknowledgement_only")
        if actionable and _normalized(reply) == _normalized(request):
            reasons.append("request_echo")
        if reasons:
            status = ResponseSelfCheckStatus.REPAIR

    return ResponseSelfCheckResult(
        status=status,
        reasons=tuple(dict.fromkeys(reasons)),
        request_digest=_digest(request),
        response_digest=_digest(reply),
        actionable_request=actionable,
        has_attachments=bool(attachments),
    )


def _is_actionable(request: str, has_attachments: bool) -> bool:
    normalized = _normalized(request)
    if not normalized or normalized in GENERIC_REQUESTS:
        return False
    return bool(ACTION_TERMS.search(request)) or (
        has_attachments and len(normalized.split()) >= 2
    )


def _is_acknowledgement_only(response: str) -> bool:
    plain = re.sub(r"[`*_>#\[\]()]", " ", response).strip()
    normalized = re.sub(r"\s+", " ", plain).strip().lower()
    if normalized in ACK_EXACT:
        return True
    if len(normalized) > 400 or len(normalized.split()) > 60:
        return False
    return bool(ACK_START.search(normalized) and FUTURE_ONLY.search(normalized))


def _identity_matches(
    expected: Mapping[str, str] | None,
    actual: Mapping[str, str] | None,
) -> bool:
    if not expected:
        return True
    if not actual:
        return False
    for key, value in expected.items():
        clean = str(value or "").strip()
        if clean and str(actual.get(key) or "").strip() != clean:
            return False
    return True


def _attachment_names(values: Iterable[str]) -> tuple[str, ...]:
    names = []
    for value in values:
        clean = str(value or "").replace("\\", "/").rsplit("/", 1)[-1].strip()
        if clean:
            names.append(clean[:240])
    return tuple(dict.fromkeys(names))


def _bounded(value: str, limit: int) -> str:
    return str(value or "").replace("\r\n", "\n").strip()[:limit]


def _normalized(value: str) -> str:
    return re.sub(r"[^\w\u3400-\u9fff]+", " ", str(value or "").lower()).strip()


def _digest(value: str) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8")).hexdigest()[:16]
