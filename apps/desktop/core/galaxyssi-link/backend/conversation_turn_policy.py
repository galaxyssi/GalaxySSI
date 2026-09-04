"""Classify a new request while an Agent turn is already running."""
from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum

from conversation_context import current_request


class ActiveTurnDisposition(str, Enum):
    INDEPENDENT = "independent"
    STEER = "steer"
    INTERRUPT = "interrupt"


class ActiveTurnInterventionKind(str, Enum):
    NONE = "none"
    CONSTRAINT = "constraint"
    GOAL_CHANGE = "goal_change"
    INTERRUPT = "interrupt"


@dataclass(frozen=True)
class ActiveTurnDecision:
    disposition: ActiveTurnDisposition
    intervention_kind: ActiveTurnInterventionKind = ActiveTurnInterventionKind.NONE

    @property
    def intervenes(self) -> bool:
        return self.disposition != ActiveTurnDisposition.INDEPENDENT


_INDEPENDENT_PREFIXES = (
    "new task",
    "start a new task",
    "separate task",
    "another task",
    "independent task",
    "\u65b0\u4efb\u52a1",
    "\u65b0\u7684\u4efb\u52a1",
    "\u53e6\u4e00\u4e2a\u4efb\u52a1",
    "\u53e6\u5916\u4e00\u4e2a\u4efb\u52a1",
    "\u5355\u72ec\u4efb\u52a1",
    "\u72ec\u7acb\u4efb\u52a1",
)

_INTERRUPT_PATTERNS = (
    re.compile(
        r"^(?:stop|cancel|abort|interrupt)"
        r"(?:\s+(?:this|the|current|active|the\s+current))?"
        r"(?:\s+(?:task|run|job))?[.!?\s]*$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:please\s+)?(?:stop|cancel|abort)\s+(?:working|running|now)[.!?\s]*$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:\u505c\u6b62|\u53d6\u6d88|\u4e2d\u65ad)"
        r"(?:\u5f53\u524d|\u8fd9\u4e2a|\u8be5)?"
        r"(?:\u4efb\u52a1|\u6267\u884c|\u8fd0\u884c)?"
        r"[\uff01\uff1f\u3002!?\s]*$",
    ),
    re.compile(
        r"^(?:\u5148\u505c\u4e0b|\u505c\u4e0b\u6765|\u522b\u505a\u4e86|"
        r"\u4e0d\u7528\u7ee7\u7eed\u4e86|\u4e0d\u8981\u7ee7\u7eed\u4e86)"
        r"[\uff01\uff1f\u3002!?\s]*$",
    ),
)

_GOAL_CHANGE_PREFIXES = (
    "change the goal",
    "change goal",
    "switch the goal",
    "replace the task",
    "do this instead",
    "instead,",
    "instead ",
    "not that",
    "\u6539\u76ee\u6807",
    "\u66f4\u6362\u76ee\u6807",
    "\u6362\u4e2a\u76ee\u6807",
    "\u6539\u6210",
    "\u6539\u4e3a",
    "\u6539\u505a",
    "\u522b\u505a",
    "\u4e0d\u662f",
)

_CONTINUATION_PREFIXES = (
    "continue",
    "keep going",
    "go on",
    "also",
    "add ",
    "additionally",
    "change ",
    "change it",
    "correct ",
    "correction",
    "make sure",
    "ensure ",
    "use the previous",
    "use this",
    "use that",
    "with that",
    "based on that",
    "instead",
    "remove ",
    "keep ",
    "retry",
    "redo",
    "not that",
    "do not ",
    "no,",
    "wait",
    "stop",
    "\u7ee7\u7eed",
    "\u63a5\u7740",
    "\u518d",
    "\u91cd\u65b0",
    "\u91cd\u8bd5",
    "\u66f4\u6b63",
    "\u7ea0\u6b63",
    "\u4fee\u6539",
    "\u6539\u6210",
    "\u6539\u4e3a",
    "\u6539\u4e00\u4e0b",
    "\u8865\u5145",
    "\u8ffd\u52a0",
    "\u53e6\u5916",
    "\u8fd8\u6709",
    "\u786e\u4fdd",
    "\u4fdd\u8bc1",
    "\u8981\u786e\u4fdd",
    "\u8981\u4fdd\u8bc1",
    "\u8bf7\u786e\u4fdd",
    "\u4e0d\u8981",
    "\u53bb\u6389",
    "\u5220\u6389",
    "\u4fdd\u7559",
    "\u6062\u590d",
    "\u7528\u521a\u624d",
    "\u6309\u521a\u624d",
    "\u6839\u636e\u521a\u624d",
    "\u4e0a\u9762",
    "\u524d\u9762",
    "\u8fd9\u4e2a",
    "\u8fd9\u5f20",
    "\u90a3\u4e2a",
    "\u628a\u5b83",
    "\u4e0d\u5bf9",
    "\u4e0d\u662f",
    "\u5148\u522b",
    "\u7b49\u7b49",
    "\u505c\u6b62",
    "\u53d6\u6d88",
)

_CONTINUATION_REFERENCES = (
    " previous ",
    " above ",
    " earlier ",
    " that ",
    " this ",
    " it ",
    " same ",
    " again",
    "\u521a\u624d",
    "\u4e0a\u4e00\u4e2a",
    "\u4e0a\u4e00\u6761",
    "\u4e0a\u9762",
    "\u524d\u9762",
    "\u539f\u6765",
    "\u8fd9\u4e2a",
    "\u8fd9\u5f20",
    "\u90a3\u4e2a",
    "\u5b83",
    "\u540c\u4e00\u4e2a",
    "\u4e00\u6837",
)

_STANDALONE_PATTERNS = (
    re.compile(r"^(?:reply|respond)\s+exactly\b", re.IGNORECASE),
    re.compile(r"^(?:hello|hi|hey)\b[.!?]*$", re.IGNORECASE),
)


def should_steer_active_turn(
    request: str,
    active_request: str = "",
    *,
    has_new_attachments: bool = False,
) -> bool:
    """Return True only when the request clearly modifies the active turn.

    Independent work is the safe default. This prevents unrelated rapid
    submissions from being merged into one Codex turn, while explicit
    corrections and references to the in-progress task remain steerable.
    """

    return classify_active_turn(
        request,
        active_request,
        has_new_attachments=has_new_attachments,
    ).disposition == ActiveTurnDisposition.STEER


def classify_active_turn(
    request: str,
    active_request: str = "",
    *,
    has_new_attachments: bool = False,
) -> ActiveTurnDecision:
    """Classify how a new message relates to the active task.

    Independent work is the default. An interrupt must be an explicit,
    standalone command so phrases such as "do not stop after the first page"
    cannot terminate a task accidentally.
    """

    clean = _normalized_request(request)
    if not clean:
        return ActiveTurnDecision(ActiveTurnDisposition.INDEPENDENT)
    if any(pattern.fullmatch(clean) for pattern in _INTERRUPT_PATTERNS):
        return ActiveTurnDecision(
            ActiveTurnDisposition.INTERRUPT,
            ActiveTurnInterventionKind.INTERRUPT,
        )
    lowered = clean.casefold()
    if lowered.startswith(_INDEPENDENT_PREFIXES):
        return ActiveTurnDecision(ActiveTurnDisposition.INDEPENDENT)
    if any(pattern.search(clean) for pattern in _STANDALONE_PATTERNS):
        return ActiveTurnDecision(ActiveTurnDisposition.INDEPENDENT)
    if lowered.startswith(_CONTINUATION_PREFIXES):
        return ActiveTurnDecision(
            ActiveTurnDisposition.STEER,
            _steer_kind(lowered),
        )

    padded = f" {lowered} "
    if not has_new_attachments and any(
        reference in padded for reference in _CONTINUATION_REFERENCES
    ):
        return ActiveTurnDecision(
            ActiveTurnDisposition.STEER,
            _steer_kind(lowered),
        )

    # A terse correction often omits a pronoun but repeats a distinctive part
    # of the current request. Only use this fallback for fragments, never for
    # complete standalone requests or a bare new attachment.
    active = _normalized_request(active_request)
    if (
        active
        and not has_new_attachments
        and _looks_like_fragment(clean)
        and _distinctive_overlap(clean, active)
    ):
        return ActiveTurnDecision(
            ActiveTurnDisposition.STEER,
            _steer_kind(lowered),
        )
    return ActiveTurnDecision(ActiveTurnDisposition.INDEPENDENT)


def superseding_prompt(
    active_request: str,
    intervention: str,
    *,
    kind: ActiveTurnInterventionKind,
) -> str:
    """Build a bounded replacement prompt for adapters without live steering."""

    active = _normalized_request(active_request)[:16_000]
    latest = _normalized_request(intervention)[:8_000]
    label = (
        "The user changed the goal of an in-progress task."
        if kind == ActiveTurnInterventionKind.GOAL_CHANGE
        else "The user added a constraint to an in-progress task."
    )
    return (
        f"{label}\n"
        "Continue as one task. The latest instruction has priority wherever it "
        "conflicts with the original request.\n\n"
        f"Original request:\n{active}\n\n"
        f"Latest instruction:\n{latest}"
    )


def _steer_kind(lowered: str) -> ActiveTurnInterventionKind:
    if lowered.startswith(_GOAL_CHANGE_PREFIXES):
        return ActiveTurnInterventionKind.GOAL_CHANGE
    return ActiveTurnInterventionKind.CONSTRAINT


def _normalized_request(value: str) -> str:
    return re.sub(r"\s+", " ", current_request(value)).strip()


def _looks_like_fragment(value: str) -> bool:
    if len(value) > 100:
        return False
    words = re.findall(r"[A-Za-z0-9_+-]+", value)
    if len(words) > 12:
        return False
    standalone_leads = (
        "write",
        "create",
        "build",
        "generate",
        "search",
        "find",
        "check",
        "tell",
        "explain",
        "summarize",
        "translate",
        "open",
        "run",
        "set",
        "\u5199",
        "\u521b\u5efa",
        "\u751f\u6210",
        "\u67e5",
        "\u641c\u7d22",
        "\u6253\u5f00",
        "\u8fd0\u884c",
        "\u8bbe\u7f6e",
        "\u89e3\u91ca",
        "\u603b\u7ed3",
        "\u7ffb\u8bd1",
    )
    return not value.casefold().startswith(standalone_leads)


def _distinctive_overlap(left: str, right: str) -> bool:
    left_tokens = _distinctive_tokens(left)
    right_tokens = _distinctive_tokens(right)
    return bool(left_tokens & right_tokens)


def _distinctive_tokens(value: str) -> set[str]:
    lowered = value.casefold()
    result = {
        token
        for token in re.findall(r"[a-z0-9][a-z0-9_+.-]{2,}", lowered)
        if token not in {"the", "and", "for", "with", "this", "that", "please"}
    }
    for sequence in re.findall(r"[\u4e00-\u9fff]{2,}", lowered):
        result.update(sequence[index:index + 2] for index in range(len(sequence) - 1))
    return result
