"""Shared execution policy, recovery budget, checkpoints, and artifact finalization."""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import shutil
import subprocess
import threading
import time
import zipfile
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Iterable


log = logging.getLogger("signalasi.execution")
_CHECKPOINT_WRITE_LOCK = threading.RLock()


class AgentTaskKind(str, Enum):
    CHAT = "chat"
    RESEARCH = "research"
    ARTIFACT = "artifact"
    BUILD = "build"
    INSTALL = "install"
    DEVICE = "device"


class AgentTaskIntent(str, Enum):
    CHAT = "chat"
    CODE = "code"
    PHONE_CONTROL = "phone_control"
    DESKTOP_CONTROL = "desktop_control"
    RESEARCH = "research"
    FILE = "file"
    MEMORY = "memory"
    AUTOMATION = "automation"


class AgentClarificationMode(str, Enum):
    EXECUTE = "execute"
    ASK_LOCALLY = "ask_locally"
    ASK_WITH_MODEL = "ask_with_model"


class AgentClarificationQuestion(str, Enum):
    NONE = "none"
    TASK_GOAL = "task_goal"
    CODE_OUTCOME = "code_outcome"
    CONTROL_ACTION = "control_action"
    RESEARCH_TOPIC = "research_topic"
    FILE_ACTION = "file_action"
    MEMORY_CONTENT = "memory_content"
    AUTOMATION_DETAILS = "automation_details"


class AgentReasoningEffort(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class AgentExecutionMode(str, Enum):
    PLAN_ONLY = "plan_only"
    AUTO_COMPLETE = "auto_complete"


@dataclass(frozen=True)
class AgentExecutionPolicy:
    task_kind: AgentTaskKind
    reasoning_effort: AgentReasoningEffort
    no_progress_timeout_seconds: float
    max_replans: int
    max_same_failure_attempts: int
    requires_artifact: bool = False
    target_platform: str = ""
    verify_installation: bool = False
    task_intent: AgentTaskIntent = AgentTaskIntent.CHAT
    task_intent_confidence: int = 100
    task_intent_signals: tuple[str, ...] = ()
    execution_mode: AgentExecutionMode = AgentExecutionMode.AUTO_COMPLETE

    def public(self) -> dict:
        return {
            "task_kind": self.task_kind.value,
            "task_intent": self.task_intent.value,
            "task_intent_confidence": self.task_intent_confidence,
            "task_intent_signals": list(self.task_intent_signals),
            "execution_mode": self.execution_mode.value,
            "reasoning_effort": self.reasoning_effort.value,
            "no_progress_timeout_seconds": self.no_progress_timeout_seconds,
            "max_replans": self.max_replans,
            "max_same_failure_attempts": self.max_same_failure_attempts,
            "requires_artifact": self.requires_artifact,
            "target_platform": self.target_platform,
            "verify_installation": self.verify_installation,
            "absolute_timeout_seconds": None,
        }

    @classmethod
    def from_public(cls, value: dict | None) -> "AgentExecutionPolicy":
        value = value or {}
        try:
            task_kind = AgentTaskKind(str(value.get("task_kind") or "chat"))
        except ValueError:
            task_kind = AgentTaskKind.CHAT
        try:
            effort = AgentReasoningEffort(str(value.get("reasoning_effort") or "low"))
        except ValueError:
            effort = AgentReasoningEffort.LOW
        try:
            task_intent = AgentTaskIntent(str(value.get("task_intent") or "chat"))
        except ValueError:
            task_intent = AgentTaskIntent.CHAT
        try:
            execution_mode = AgentExecutionMode(
                str(value.get("execution_mode") or AgentExecutionMode.AUTO_COMPLETE.value)
            )
        except ValueError:
            execution_mode = AgentExecutionMode.AUTO_COMPLETE
        try:
            task_intent_confidence = int(value.get("task_intent_confidence", 100))
        except (TypeError, ValueError):
            task_intent_confidence = 100
        raw_intent_signals = value.get("task_intent_signals")
        if not isinstance(raw_intent_signals, (list, tuple, set)):
            raw_intent_signals = ()
        return cls(
            task_kind=task_kind,
            reasoning_effort=effort,
            no_progress_timeout_seconds=max(
                30.0,
                float(value.get("no_progress_timeout_seconds") or 180.0),
            ),
            max_replans=max(0, int(value.get("max_replans") or 0)),
            max_same_failure_attempts=max(
                1,
                int(value.get("max_same_failure_attempts") or 2),
            ),
            requires_artifact=bool(value.get("requires_artifact")),
            target_platform=str(value.get("target_platform") or ""),
            verify_installation=bool(value.get("verify_installation")),
            task_intent=task_intent,
            task_intent_confidence=min(
                100,
                max(0, task_intent_confidence),
            ),
            task_intent_signals=tuple(
                dict.fromkeys(
                    str(item).strip()
                    for item in raw_intent_signals
                    if str(item).strip()
                )
            )[:6],
            execution_mode=execution_mode,
        )


@dataclass(frozen=True)
class AgentTaskIntentClassification:
    intent: AgentTaskIntent
    confidence: int
    matched_signals: tuple[str, ...] = ()


@dataclass(frozen=True)
class AgentClarificationDecision:
    mode: AgentClarificationMode
    question: AgentClarificationQuestion = AgentClarificationQuestion.NONE

    @property
    def should_ask(self) -> bool:
        return self.mode != AgentClarificationMode.EXECUTE


_INTENT_PRIORITY = (
    AgentTaskIntent.AUTOMATION,
    AgentTaskIntent.MEMORY,
    AgentTaskIntent.DESKTOP_CONTROL,
    AgentTaskIntent.PHONE_CONTROL,
    AgentTaskIntent.CODE,
    AgentTaskIntent.FILE,
    AgentTaskIntent.RESEARCH,
    AgentTaskIntent.CHAT,
)
_INTENT_RULES = (
    (AgentTaskIntent.CODE, 3, (
        "build", "compile", "implement", "develop", "code", "program",
        "fix bug", "repository", "pull request", "unit test", "apk",
        "\u7f16\u8bd1", "\u6784\u5efa", "\u5f00\u53d1", "\u5b9e\u73b0",
        "\u4ee3\u7801", "\u7a0b\u5e8f", "\u4fee\u590d bug", "\u9879\u76ee",
        "\u4ed3\u5e93", "\u5355\u5143\u6d4b\u8bd5",
    )),
    (AgentTaskIntent.PHONE_CONTROL, 3, (
        "on my phone", "phone setting", "mobile device", "open phone app",
        "launch the app on my phone",
        "battery", "flashlight", "camera", "take a photo", "sms",
        "text message", "make a call", "timer", "alarm", "volume",
        "\u624b\u673a", "\u624b\u673a\u8bbe\u7f6e",
        "\u5728\u624b\u673a\u4e0a\u6253\u5f00",
        "\u6253\u5f00\u624b\u673a app",
        "\u7535\u91cf", "\u624b\u7535\u7b52", "\u6444\u50cf\u5934",
        "\u62cd\u7167", "\u77ed\u4fe1", "\u6253\u7535\u8bdd",
        "\u8ba1\u65f6\u5668", "\u95f9\u949f", "\u97f3\u91cf",
    )),
    (AgentTaskIntent.DESKTOP_CONTROL, 3, (
        "on my computer", "on the computer", "desktop control",
        "remote desktop", "windows desktop", "open on desktop",
        "computer screen", "mouse click", "keyboard shortcut",
        "\u7535\u8111", "\u8fdc\u7a0b\u684c\u9762", "\u63a7\u5236\u7535\u8111",
        "\u7535\u8111\u5c4f\u5e55", "\u9f20\u6807", "\u952e\u76d8\u5feb\u6377\u952e",
    )),
    (AgentTaskIntent.RESEARCH, 2, (
        "research", "search the web", "look up", "latest", "today's news",
        "current news", "weather", "find sources", "compare sources",
        "\u8c03\u67e5", "\u641c\u7d22", "\u67e5\u8d44\u6599", "\u6700\u65b0",
        "\u4eca\u5929\u7684\u65b0\u95fb", "\u65b0\u95fb", "\u5929\u6c14",
        "\u67e5\u627e\u6765\u6e90",
    )),
    (AgentTaskIntent.FILE, 2, (
        "file", "pdf", "spreadsheet", "xlsx", "csv", "docx", "image",
        "screenshot", "audio", "video", "archive", "zip", "extract text",
        "convert this", "summarize this document",
        "\u6587\u4ef6", "\u8868\u683c", "\u56fe\u7247", "\u622a\u56fe",
        "\u97f3\u9891", "\u89c6\u9891", "\u538b\u7f29\u5305",
        "\u63d0\u53d6\u6587\u5b57", "\u8f6c\u6362\u8fd9\u4e2a",
        "\u603b\u7ed3\u8fd9\u4efd\u6587\u6863",
    )),
    (AgentTaskIntent.MEMORY, 4, (
        "remember that", "remember my", "forget that", "my preference",
        "memory", "knowledge base", "what did i say", "what do you know about me",
        "\u8bb0\u4f4f", "\u5fd8\u8bb0", "\u6211\u7684\u504f\u597d",
        "\u8bb0\u5fc6", "\u77e5\u8bc6\u5e93", "\u6211\u4e4b\u524d\u8bf4",
        "\u4f60\u8bb0\u5f97",
    )),
    (AgentTaskIntent.AUTOMATION, 7, (
        "automate", "schedule", "recurring", "every day", "every hour",
        "workflow", "when this happens", "trigger", "monitor continuously",
        "cron", "remind me",
        "\u81ea\u52a8\u5316", "\u5b9a\u65f6", "\u6bcf\u5929",
        "\u6bcf\u5c0f\u65f6", "\u5de5\u4f5c\u6d41", "\u89e6\u53d1",
        "\u6301\u7eed\u76d1\u63a7", "\u63d0\u9192\u6211",
    )),
)


_CLARIFICATION_GREETINGS = {
    "hello", "hi", "hey", "good morning", "good afternoon", "good evening",
    "\u4f60\u597d", "\u55e8", "\u65e9\u4e0a\u597d", "\u4e0b\u5348\u597d", "\u665a\u4e0a\u597d",
}
_CLARIFICATION_QUESTION_PREFIXES = (
    "what ", "why ", "how ", "when ", "where ", "which ", "who ",
    "can ", "could ", "would ", "is ", "are ", "do ", "does ",
    "\u4ec0\u4e48", "\u4e3a\u4ec0\u4e48", "\u600e\u4e48", "\u5982\u4f55",
    "\u54ea\u4e2a", "\u54ea\u4e9b", "\u8c01", "\u80fd\u4e0d\u80fd", "\u53ef\u4ee5",
)
_CLARIFICATION_QUESTION_SUFFIXES = (
    "\u5417", "\u5462", "\u4e48", "\u600e\u4e48\u6837", "\u5982\u4f55",
)
_CONTEXTUAL_FOLLOW_UPS = {
    "continue", "go ahead", "do it", "try again", "retry", "keep going",
    "use this", "use that", "same as before", "make it better",
    "\u7ee7\u7eed", "\u6267\u884c", "\u5c31\u8fd9\u6837", "\u6309\u8fd9\u4e2a",
    "\u518d\u8bd5\u8bd5", "\u91cd\u8bd5", "\u4fdd\u8bc1\u6b63\u786e", "\u7528\u8fd9\u4e2a",
    "\u548c\u4e4b\u524d\u4e00\u6837", "\u6309\u4e0a\u9762\u7684\u505a",
}
_CONTEXTUAL_REFERENCES = (
    " this", " that", " it", " above", " previous",
    "\u8fd9\u4e2a", "\u90a3\u4e2a", "\u5b83", "\u4e0a\u9762", "\u4e4b\u524d",
    "\u521a\u624d", "\u524d\u9762", "\u8be5\u6587\u4ef6", "\u8fd9\u5f20\u56fe",
)
_VAGUE_REQUESTS = {
    "help me", "handle this", "do something", "take a look", "fix it",
    "improve it", "optimize it", "work on this", "please help",
    "\u5e2e\u6211", "\u5e2e\u6211\u5f04\u4e00\u4e0b", "\u5904\u7406\u4e00\u4e0b",
    "\u5f04\u4e00\u4e0b", "\u770b\u770b", "\u5e2e\u6211\u770b\u770b", "\u4fee\u4e00\u4e0b",
    "\u4f18\u5316\u4e00\u4e0b", "\u6539\u8fdb\u4e00\u4e0b", "\u4f60\u770b\u7740\u529e",
    "\u7ed9\u6211\u7ed3\u679c", "\u5feb\u70b9", "\u4e0d\u884c",
}
_MISSING_CODE_OUTCOME = {
    "write code", "write a program", "build an app", "create an app", "fix the code",
    "\u5199\u4ee3\u7801", "\u5199\u4e2a\u7a0b\u5e8f", "\u5f00\u53d1\u4e00\u4e2a app",
    "\u505a\u4e00\u4e2a app", "\u4fee\u4ee3\u7801",
}
_MISSING_CONTROL_ACTION = {
    "control my phone", "control the phone", "control my computer",
    "control the computer", "remote desktop",
    "\u63a7\u5236\u624b\u673a", "\u64cd\u4f5c\u624b\u673a",
    "\u63a7\u5236\u7535\u8111", "\u64cd\u4f5c\u7535\u8111", "\u8fdc\u7a0b\u684c\u9762",
}
_MISSING_RESEARCH_TOPIC = {
    "research", "research this", "search", "search the web", "look it up",
    "\u7814\u7a76\u4e00\u4e0b", "\u641c\u7d22", "\u641c\u4e00\u4e0b",
    "\u67e5\u4e00\u4e0b", "\u67e5\u8d44\u6599",
}
_MISSING_FILE_ACTION = {
    "process the file", "handle the file", "work on the document",
    "\u5904\u7406\u6587\u4ef6", "\u5904\u7406\u8fd9\u4e2a\u6587\u4ef6", "\u770b\u4e0b\u6587\u4ef6",
}
_MISSING_MEMORY_CONTENT = {
    "remember this", "remember that", "save this to memory",
    "\u8bb0\u4f4f\u8fd9\u4e2a", "\u8bb0\u4f4f\u8fd9\u4ef6\u4e8b", "\u5b58\u5230\u8bb0\u5fc6",
}
_MISSING_AUTOMATION_DETAILS = {
    "create an automation", "make a workflow", "schedule a task", "remind me",
    "\u521b\u5efa\u81ea\u52a8\u5316", "\u5efa\u4e00\u4e2a\u5de5\u4f5c\u6d41",
    "\u8bbe\u7f6e\u5b9a\u65f6\u4efb\u52a1", "\u63d0\u9192\u6211",
}


def clarification_decision_for(
    prompt: str,
    *,
    has_attachments: bool = False,
    has_conversation_context: bool = False,
) -> AgentClarificationDecision:
    normalized = re.sub(
        r"[^\w\u4e00-\u9fff]+",
        " ",
        str(prompt or "").lower(),
        flags=re.UNICODE,
    )
    normalized = " ".join(normalized.split())
    if not normalized:
        if has_attachments:
            return AgentClarificationDecision(
                AgentClarificationMode.ASK_WITH_MODEL,
                AgentClarificationQuestion.FILE_ACTION,
            )
        return AgentClarificationDecision(
            AgentClarificationMode.ASK_LOCALLY,
            AgentClarificationQuestion.TASK_GOAL,
        )
    if has_conversation_context and (
        normalized in _CONTEXTUAL_FOLLOW_UPS
        or any(reference in normalized for reference in _CONTEXTUAL_REFERENCES)
    ):
        return AgentClarificationDecision(AgentClarificationMode.EXECUTE)
    if has_attachments and normalized in _VAGUE_REQUESTS:
        return AgentClarificationDecision(
            AgentClarificationMode.ASK_WITH_MODEL,
            AgentClarificationQuestion.FILE_ACTION,
        )
    if normalized in _VAGUE_REQUESTS:
        return (
            AgentClarificationDecision(AgentClarificationMode.EXECUTE)
            if has_conversation_context
            else AgentClarificationDecision(
                AgentClarificationMode.ASK_LOCALLY,
                AgentClarificationQuestion.TASK_GOAL,
            )
        )
    if (
        normalized in _CLARIFICATION_GREETINGS
        or normalized.startswith(_CLARIFICATION_QUESTION_PREFIXES)
        or normalized.endswith(_CLARIFICATION_QUESTION_SUFFIXES)
    ):
        return AgentClarificationDecision(AgentClarificationMode.EXECUTE)

    question = (
        AgentClarificationQuestion.CODE_OUTCOME
        if normalized in _MISSING_CODE_OUTCOME else
        AgentClarificationQuestion.CONTROL_ACTION
        if normalized in _MISSING_CONTROL_ACTION else
        AgentClarificationQuestion.RESEARCH_TOPIC
        if normalized in _MISSING_RESEARCH_TOPIC else
        AgentClarificationQuestion.FILE_ACTION
        if normalized in _MISSING_FILE_ACTION else
        AgentClarificationQuestion.MEMORY_CONTENT
        if normalized in _MISSING_MEMORY_CONTENT else
        AgentClarificationQuestion.AUTOMATION_DETAILS
        if normalized in _MISSING_AUTOMATION_DETAILS else
        None
    )
    if question is not None and not has_conversation_context:
        return AgentClarificationDecision(
            AgentClarificationMode.ASK_LOCALLY,
            question,
        )
    return AgentClarificationDecision(AgentClarificationMode.EXECUTE)


def classify_task_intent(
    prompt: str,
    *,
    has_attachments: bool = False,
) -> AgentTaskIntentClassification:
    normalized = " ".join(str(prompt or "").lower().split())
    scores: dict[AgentTaskIntent, int] = {}
    signals: dict[AgentTaskIntent, list[str]] = {}
    for intent, weight, terms in _INTENT_RULES:
        for term in terms:
            if term in normalized:
                scores[intent] = scores.get(intent, 0) + weight
                signals.setdefault(intent, []).append(term)
    if has_attachments:
        scores[AgentTaskIntent.FILE] = scores.get(AgentTaskIntent.FILE, 0) + 3
        signals.setdefault(AgentTaskIntent.FILE, []).append("attachment")
    if not scores:
        return AgentTaskIntentClassification(AgentTaskIntent.CHAT, 100)
    ranked = sorted(
        scores.items(),
        key=lambda item: (-item[1], _INTENT_PRIORITY.index(item[0])),
    )
    winner, winning_score = ranked[0]
    runner_up_score = ranked[1][1] if len(ranked) > 1 else 0
    margin = winning_score - runner_up_score
    confidence = min(98, max(55, 55 + winning_score * 4 + margin * 5))
    return AgentTaskIntentClassification(
        intent=winner,
        confidence=confidence,
        matched_signals=tuple(dict.fromkeys(signals.get(winner, ())))[:6],
    )


_BUILD_TERMS = (
    "build", "compile", "implement", "develop", "create an app", "create a game",
    "write a program", "make an app", "make a game", "fix bug", "run tests",
    "\u7f16\u8bd1", "\u6784\u5efa", "\u5f00\u53d1", "\u5b9e\u73b0",
    "\u5199\u4e00\u4e2a\u7a0b\u5e8f", "\u505a\u4e00\u4e2a\u6e38\u620f",
    "\u751f\u6210\u7a0b\u5e8f", "\u4fee\u590d bug", "\u8fd0\u884c\u6d4b\u8bd5",
)
_INSTALL_TERMS = (
    "install", "install and open", "install apk", "deploy to phone", "launch the app",
    "\u5b89\u88c5", "\u5b89\u88c5\u5e76\u6253\u5f00", "\u5b89\u88c5 apk",
    "\u5b89\u88c5\u5230\u624b\u673a", "\u7f16\u8bd1\u5e76\u5b89\u88c5",
)
_ARTIFACT_TERMS = (
    "return the file", "send the file", "export", "generate image", "create file",
    "downloadable", "zip project", "apk",
    "\u53d1\u56de\u6587\u4ef6", "\u8fd4\u56de\u6587\u4ef6", "\u5bfc\u51fa",
    "\u751f\u6210\u56fe\u7247", "\u6253\u5305", "\u538b\u7f29\u5305",
)
_RESEARCH_TERMS = (
    "latest", "today", "news", "weather", "research", "search the web",
    "\u6700\u65b0", "\u4eca\u5929", "\u65b0\u95fb", "\u5929\u6c14",
    "\u8c03\u67e5", "\u641c\u7d22", "\u8054\u7f51",
)
_DEVICE_TERMS = (
    "battery", "flashlight", "camera", "alarm", "timer", "phone setting",
    "\u7535\u91cf", "\u624b\u7535\u7b52", "\u6444\u50cf\u5934", "\u62cd\u7167",
    "\u95f9\u949f", "\u8ba1\u65f6\u5668", "\u624b\u673a\u8bbe\u7f6e",
)
_ANDROID_TERMS = (
    "android", "apk", "mobile app", "phone game", "on the phone",
    "\u5b89\u5353", "\u624b\u673a app", "\u624b\u673a\u4e0a\u73a9",
    "\u624b\u673a\u6e38\u620f", "\u5b89\u88c5\u5230\u624b\u673a",
)
_PLAN_ONLY_SIGNALS = (
    "\u5148\u7ed9\u65b9\u6848", "\u5148\u7ed9\u6211\u65b9\u6848",
    "\u53ea\u7ed9\u65b9\u6848", "\u4ec5\u7ed9\u65b9\u6848",
    "\u4ec5\u63d0\u4f9b\u65b9\u6848", "\u53ea\u5236\u5b9a\u8ba1\u5212",
    "\u5148\u5236\u5b9a\u8ba1\u5212", "\u5148\u5217\u51fa\u8ba1\u5212",
    "\u6682\u4e0d\u6267\u884c", "\u5148\u4e0d\u8981\u6267\u884c",
    "\u4e0d\u8981\u5b9e\u9645\u6267\u884c",
    "\u4e0d\u8981\u6267\u884c\u4efb\u4f55\u64cd\u4f5c",
    "\u4e0d\u8981\u6267\u884c\u4efb\u4f55\u52a8\u4f5c",
    "plan only", "proposal only", "show me the plan first",
    "give me a plan first", "do not execute", "don't execute",
    "without executing", "without making changes",
)
_AUTO_COMPLETE_SIGNALS = (
    "\u81ea\u52a8\u6267\u884c\u5230\u5b8c\u6210",
    "\u76f4\u63a5\u6267\u884c\u5230\u5b8c\u6210",
    "\u4e00\u76f4\u6267\u884c\u5230\u5b8c\u6210",
    "\u6267\u884c\u8fd9\u4e2a\u65b9\u6848",
    "\u6309\u8fd9\u4e2a\u65b9\u6848\u6267\u884c",
    "\u7ee7\u7eed\u6267\u884c\u5230\u5b8c\u6210",
    "go ahead and execute",
    "execute until complete", "carry this through to completion",
    "implement this plan", "proceed with the plan",
)


def resolve_execution_mode(
    prompt: str,
    requested: str | AgentExecutionMode = AgentExecutionMode.AUTO_COMPLETE,
) -> tuple[AgentExecutionMode, str]:
    normalized = " ".join(str(prompt or "").lower().split())
    for signal in _PLAN_ONLY_SIGNALS:
        if signal in normalized:
            return AgentExecutionMode.PLAN_ONLY, signal
    for signal in _AUTO_COMPLETE_SIGNALS:
        if signal in normalized:
            return AgentExecutionMode.AUTO_COMPLETE, signal
    try:
        configured = (
            requested
            if isinstance(requested, AgentExecutionMode)
            else AgentExecutionMode(str(requested or AgentExecutionMode.AUTO_COMPLETE.value))
        )
    except ValueError:
        configured = AgentExecutionMode.AUTO_COMPLETE
    return configured, ""


def execution_policy_for(
    prompt: str,
    *,
    attachments: Iterable[str] = (),
    requested_execution_mode: str | AgentExecutionMode = AgentExecutionMode.AUTO_COMPLETE,
) -> AgentExecutionPolicy:
    normalized = " ".join(str(prompt or "").lower().split())
    has_attachment_context = bool(tuple(attachments))
    intent = classify_task_intent(
        normalized,
        has_attachments=has_attachment_context,
    )
    has_install = _contains_any(normalized, _INSTALL_TERMS)
    has_build = _contains_any(normalized, _BUILD_TERMS)
    has_artifact_request = _contains_any(normalized, _ARTIFACT_TERMS)
    has_research = _contains_any(normalized, _RESEARCH_TERMS)
    has_device = _contains_any(normalized, _DEVICE_TERMS)
    target_platform = "android" if _contains_any(normalized, _ANDROID_TERMS) else ""
    execution_mode, _execution_mode_signal = resolve_execution_mode(
        normalized,
        requested_execution_mode,
    )

    if has_install:
        kind = AgentTaskKind.INSTALL
    elif has_build:
        kind = AgentTaskKind.BUILD
    elif has_artifact_request or has_attachment_context:
        kind = AgentTaskKind.ARTIFACT
    elif has_research:
        kind = AgentTaskKind.RESEARCH
    elif has_device:
        kind = AgentTaskKind.DEVICE
    else:
        kind = AgentTaskKind.CHAT

    complex_task = kind in {
        AgentTaskKind.RESEARCH,
        AgentTaskKind.ARTIFACT,
        AgentTaskKind.BUILD,
        AgentTaskKind.INSTALL,
    }
    no_progress_timeout = {
        AgentTaskKind.CHAT: 180.0,
        AgentTaskKind.DEVICE: 120.0,
        AgentTaskKind.RESEARCH: 300.0,
        AgentTaskKind.ARTIFACT: 360.0,
        AgentTaskKind.BUILD: 420.0,
        AgentTaskKind.INSTALL: 420.0,
    }[kind]
    return AgentExecutionPolicy(
        task_kind=kind,
        reasoning_effort=(
            AgentReasoningEffort.MEDIUM if complex_task else AgentReasoningEffort.LOW
        ),
        no_progress_timeout_seconds=no_progress_timeout,
        max_replans=3 if complex_task else 2,
        max_same_failure_attempts=2,
        requires_artifact=execution_mode != AgentExecutionMode.PLAN_ONLY and (
            has_artifact_request
            or kind in {AgentTaskKind.BUILD, AgentTaskKind.INSTALL}
        ),
        target_platform=target_platform,
        verify_installation=(
            execution_mode != AgentExecutionMode.PLAN_ONLY
            and kind == AgentTaskKind.INSTALL
        ),
        task_intent=intent.intent,
        task_intent_confidence=intent.confidence,
        task_intent_signals=intent.matched_signals,
        execution_mode=execution_mode,
    )


def execution_contract(policy: AgentExecutionPolicy) -> str:
    if policy.execution_mode == AgentExecutionMode.PLAN_ONLY:
        return "\n".join((
            "SignalASI execution contract:",
            f"- Task class: {policy.task_kind.value}; intent: {policy.task_intent.value}; "
            f"reasoning effort: {policy.reasoning_effort.value}; mode: plan_only.",
            "- Inspect only the context needed to produce a concrete, actionable plan.",
            "- Read-only file, repository, device-state, and web inspection is allowed.",
            "- Do not create, edit, delete, install, launch, send, publish, or mutate anything.",
            "- Do not claim that a command, tool, action, verification, or installation was executed.",
            "- Return the proposed steps, important assumptions, risks, and the first approval needed to begin.",
        ))
    target = policy.target_platform or "the requested platform"
    artifact_line = (
        "- Put every final deliverable in the task workspace outputs directory. "
        "A single deliverable stays as its native file; a directory or multi-file project must be packaged as ZIP."
        if policy.requires_artifact else
        "- Only create files when they are useful to the requested result."
    )
    install_line = (
        f"- The target is {target}. Build the native installable artifact, verify its format, "
        "and only claim installation or launch after an execution receipt confirms it."
        if policy.verify_installation else
        "- Verify the requested result before reporting success."
    )
    return "\n".join((
        "SignalASI execution contract:",
        f"- Task class: {policy.task_kind.value}; intent: {policy.task_intent.value}; "
        f"reasoning effort: {policy.reasoning_effort.value}; mode: auto_complete.",
        "- Work through Plan -> Act -> Observe -> Replan -> Verify -> Finalize.",
        "- Preserve useful work in the task workspace before risky or long-running steps.",
        "- Do not repeat the same failed approach. Diagnose the observed failure and choose a materially different path.",
        artifact_line,
        install_line,
        "- Keep user-facing progress concise, but preserve readable reasoning summaries and concrete tool progress.",
    ))


def replan_instruction(
    policy: AgentExecutionPolicy,
    *,
    failure: str,
    attempt: int,
) -> str:
    return "\n\n".join((
        "The previous execution path did not complete.",
        f"Observed failure class (attempt {attempt}/{policy.max_same_failure_attempts}): {failure[:1_000]}",
        "Inspect the current workspace checkpoint. Preserve valid work, choose a materially different approach, "
        "and continue from the latest verified state. Do not restart the same failing command unchanged.",
        execution_contract(policy),
    ))


def failure_fingerprint(kind: str, message: str) -> str:
    normalized = re.sub(r"\b\d+(?:\.\d+)?\b", "#", str(message or "").lower())
    normalized = re.sub(r"[a-f0-9]{16,}", "<id>", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()[:500]
    return hashlib.sha256(f"{kind.strip().lower()}\0{normalized}".encode("utf-8")).hexdigest()[:24]


@dataclass
class AgentExecutionCheckpoint:
    task_id: str
    agent_id: str
    policy: AgentExecutionPolicy
    phase: str = "plan"
    last_progress_at: float = field(default_factory=time.time)
    replans: int = 0
    attempts: int = 0
    failure_counts: dict[str, int] = field(default_factory=dict)
    last_failure: str = ""
    verification: dict = field(default_factory=dict)

    def public(self) -> dict:
        return {
            "version": 1,
            "task_id": self.task_id,
            "agent_id": self.agent_id,
            "policy": self.policy.public(),
            "phase": self.phase,
            "last_progress_at": self.last_progress_at,
            "replans": self.replans,
            "attempts": self.attempts,
            "failure_counts": dict(self.failure_counts),
            "last_failure": self.last_failure,
            "verification": dict(self.verification),
        }


class AgentExecutionHarness:
    def __init__(
        self,
        task_id: str,
        agent_id: str,
        prompt: str,
        *,
        attachments: Iterable[str] = (),
        policy: AgentExecutionPolicy | None = None,
    ) -> None:
        self._state_lock = threading.RLock()
        self.policy = policy or execution_policy_for(prompt, attachments=attachments)
        initial = AgentExecutionCheckpoint(
            task_id=str(task_id or "").strip(),
            agent_id=str(agent_id or "").strip(),
            policy=self.policy,
        )
        self.checkpoint = initial
        self.checkpoint = self._load(initial) or initial
        self.checkpoint.policy = self.policy
        self._save()

    def progress(self, phase: str, **verification: object) -> None:
        with self._state_lock:
            self.checkpoint.phase = str(phase or "act")
            self.checkpoint.last_progress_at = time.time()
            if verification:
                self.checkpoint.verification.update(verification)
            self._save()

    def begin_attempt(self) -> int:
        with self._state_lock:
            self.checkpoint.attempts += 1
            self.progress("act")
            return self.checkpoint.attempts

    def record_failure(self, kind: str, message: str) -> tuple[bool, int]:
        with self._state_lock:
            signature = failure_fingerprint(kind, message)
            count = self.checkpoint.failure_counts.get(signature, 0) + 1
            self.checkpoint.failure_counts[signature] = count
            self.checkpoint.last_failure = str(message or "")[:2_000]
            can_replan = (
                count < self.policy.max_same_failure_attempts
                and self.checkpoint.replans < self.policy.max_replans
            )
            if can_replan:
                self.checkpoint.replans += 1
                self.progress("replan")
            else:
                self.progress("failed")
            return can_replan, count

    def _save(self) -> None:
        with self._state_lock:
            if not self.checkpoint.task_id:
                return
            encoded = json.dumps(
                self.checkpoint.public(),
                ensure_ascii=False,
                separators=(",", ":"),
            )
            targets = self._checkpoint_paths()
        with _CHECKPOINT_WRITE_LOCK:
            for target in targets:
                self._write_checkpoint(target, encoded)

    @staticmethod
    def _write_checkpoint(target: Path, encoded: str) -> bool:
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.parent / (
            f".{target.name}.{os.getpid()}.{threading.get_ident()}."
            f"{time.time_ns()}.tmp"
        )
        try:
            temporary.write_text(encoded, encoding="utf-8")
            for attempt in range(5):
                try:
                    os.replace(temporary, target)
                    return True
                except PermissionError:
                    if attempt == 4:
                        break
                    time.sleep(0.01 * (2 ** attempt))
        except OSError as exc:
            log.warning("Execution checkpoint write failed target=%s: %s", target, exc)
            return False
        finally:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        log.warning("Execution checkpoint replace remained locked target=%s", target)
        return False

    def _load(
        self,
        initial: AgentExecutionCheckpoint,
    ) -> AgentExecutionCheckpoint | None:
        for target in reversed(self._checkpoint_paths()):
            try:
                value = json.loads(target.read_text(encoding="utf-8"))
            except (OSError, ValueError, TypeError):
                continue
            if (
                str(value.get("task_id") or "") != initial.task_id
                or str(value.get("agent_id") or "") != initial.agent_id
            ):
                continue
            return AgentExecutionCheckpoint(
                task_id=initial.task_id,
                agent_id=initial.agent_id,
                policy=self.policy,
                phase=str(value.get("phase") or "plan"),
                last_progress_at=float(value.get("last_progress_at") or time.time()),
                replans=max(0, int(value.get("replans") or 0)),
                attempts=max(0, int(value.get("attempts") or 0)),
                failure_counts={
                    str(key): max(0, int(count))
                    for key, count in dict(value.get("failure_counts") or {}).items()
                },
                last_failure=str(value.get("last_failure") or "")[:2_000],
                verification=dict(value.get("verification") or {}),
            )
        return None

    def _checkpoint_paths(self) -> tuple[Path, Path]:
        from task_workspace import task_workspace

        root = task_workspace(self.checkpoint.task_id, self.checkpoint.agent_id)
        common = root / ".signalasi" / "execution-checkpoint.json"
        clean_agent = re.sub(
            r"[^A-Za-z0-9._-]+",
            "-",
            self.checkpoint.agent_id,
        ).strip(".-")[:48] or "agent"
        digest = hashlib.sha256(
            self.checkpoint.agent_id.encode("utf-8")
        ).hexdigest()[:8]
        actor = (
            root
            / ".signalasi"
            / "execution-checkpoints"
            / f"{clean_agent}-{digest}.json"
        )
        return common, actor


@dataclass(frozen=True)
class ArtifactFinalization:
    output_files: tuple[dict, ...]
    verification: dict
    packaged: bool = False


def finalize_task_artifacts(
    task_id: str,
    prompt: str,
    agent_id: str,
    *,
    allow_device_install: bool = False,
) -> ArtifactFinalization:
    from task_workspace import task_artifacts, task_workspace

    policy = execution_policy_for(prompt)
    root = task_workspace(task_id, agent_id)
    output_root = root / "outputs"
    output_root.mkdir(parents=True, exist_ok=True)
    packaged = False

    current = task_artifacts(task_id)
    if policy.requires_artifact:
        candidates = _workspace_candidates(root)
        selected_apk = _newest_file(candidates, ".apk")
        if selected_apk is not None:
            delivered = _copy_to_outputs(selected_apk, output_root)
            current = [_artifact_descriptor(root, delivered)]
        else:
            existing_archive = _newest_artifact(current, {".zip", ".apk"})
            if existing_archive is not None:
                current = [existing_archive]
            elif len(candidates) == 1 and candidates[0].is_file():
                delivered = _copy_to_outputs(candidates[0], output_root)
                current = [_artifact_descriptor(root, delivered)]
            elif candidates:
                archive_name = _safe_archive_name(prompt, policy)
                archive = output_root / archive_name
                _package_candidates(root, candidates, archive)
                current = [_artifact_descriptor(root, archive)]
                packaged = True
            elif (
                policy.task_kind in {AgentTaskKind.BUILD, AgentTaskKind.INSTALL}
                and len(current) > 1
            ):
                archive_name = _safe_archive_name(prompt, policy)
                archive = output_root / archive_name
                _package_artifacts(root, current, archive)
                current = [_artifact_descriptor(root, archive)]
                packaged = True

    verification = _verify_outputs(
        root,
        current,
        policy,
        allow_device_install=allow_device_install,
    )
    return ArtifactFinalization(tuple(current), verification, packaged)


def looks_failed_reply(value: str) -> bool:
    text = str(value or "").strip()
    if not text:
        return True
    if not text.startswith("["):
        return False
    normalized = text.lower()
    return any(marker in normalized for marker in (
        "failed", "failure", "timeout", "timed out", "no response",
        "not configured", "not detected", "unavailable",
        "\u5931\u8d25", "\u8d85\u65f6", "\u65e0\u54cd\u5e94",
        "\u672a\u914d\u7f6e", "\u672a\u68c0\u6d4b", "\u4e0d\u53ef\u7528",
    ))


def _contains_any(value: str, terms: Iterable[str]) -> bool:
    return any(term in value for term in terms)


def _workspace_candidates(root: Path) -> list[Path]:
    excluded_parts = {
        ".git", ".gradle", ".idea", ".signalasi", "__pycache__", "node_modules",
        "downloads", "outputs", "temp", "build", "dist",
    }
    candidates: list[Path] = []
    for item in root.iterdir():
        if item.name in {"downloads", "outputs", "temp", "logs", "screenshots", ".signalasi"}:
            continue
        if item.is_file() and not item.name.startswith("."):
            candidates.append(item)
            continue
        if (
            item.is_dir()
            and item.name not in excluded_parts
            and any(source.is_file() and not source.is_symlink() for source in item.rglob("*"))
        ):
            candidates.append(item)
    # Build outputs may contain the requested APK even though caches stay excluded.
    for apk in root.rglob("*.apk"):
        if apk.is_file() and not any(part in {".gradle", ".git"} for part in apk.parts):
            candidates.append(apk)
    unique = {str(item.resolve()).casefold(): item for item in candidates}
    return sorted(unique.values(), key=lambda item: str(item).casefold())


def _newest_file(candidates: Iterable[Path], suffix: str) -> Path | None:
    files = [
        item for item in candidates
        if item.is_file() and item.suffix.lower() == suffix.lower()
    ]
    return max(files, key=lambda item: item.stat().st_mtime, default=None)


def _copy_to_outputs(source: Path, output_root: Path) -> Path:
    target = output_root / source.name
    if source.resolve() != target.resolve():
        shutil.copy2(source, target)
    return target


def _artifact_descriptor(root: Path, source: Path) -> dict:
    return {
        "name": source.name,
        "relative_path": source.relative_to(root).as_posix(),
        "category": source.relative_to(root).parts[0],
        "size": source.stat().st_size,
    }


def _newest_artifact(
    artifacts: Iterable[dict],
    suffixes: set[str],
) -> dict | None:
    matches = [
        dict(item)
        for item in artifacts
        if Path(str(item.get("name") or "")).suffix.lower() in suffixes
    ]
    return max(matches, key=lambda item: int(item.get("size") or 0), default=None)


def _safe_archive_name(prompt: str, policy: AgentExecutionPolicy) -> str:
    target = "android-project" if policy.target_platform == "android" else "project"
    digest = hashlib.sha256(str(prompt or "").encode("utf-8")).hexdigest()[:8]
    return f"{target}-{digest}.zip"


def _package_candidates(root: Path, candidates: list[Path], archive: Path) -> None:
    temporary = archive.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for candidate in candidates:
            if candidate.is_file():
                bundle.write(candidate, candidate.relative_to(root).as_posix())
                continue
            for source in candidate.rglob("*"):
                if not source.is_file() or source.is_symlink():
                    continue
                relative = source.relative_to(root)
                if any(part in {
                    ".git", ".gradle", ".idea", ".signalasi", "__pycache__",
                    "node_modules", "outputs", "temp",
                } for part in relative.parts):
                    continue
                bundle.write(source, relative.as_posix())
    os.replace(temporary, archive)


def _package_artifacts(root: Path, artifacts: Iterable[dict], archive: Path) -> None:
    temporary = archive.with_suffix(".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for item in artifacts:
            relative = str(item.get("relative_path") or "").replace("\\", "/")
            source = (root / relative).resolve()
            if source == archive.resolve() or not source.is_file() or source.is_symlink():
                continue
            bundle.write(source, Path(relative).as_posix())
    os.replace(temporary, archive)


def _verify_outputs(
    root: Path,
    output_files: list[dict],
    policy: AgentExecutionPolicy,
    *,
    allow_device_install: bool,
) -> dict:
    results: list[dict] = []
    all_valid = True
    for item in output_files:
        relative = str(item.get("relative_path") or "")
        source = (root / relative).resolve()
        valid = source.is_file() and source.stat().st_size > 0
        detail = "non-empty file"
        if valid and source.suffix.lower() in {".zip", ".apk", ".docx", ".xlsx", ".pptx"}:
            try:
                with zipfile.ZipFile(source) as bundle:
                    invalid_member = bundle.testzip()
                    valid = invalid_member is None
                    detail = "archive integrity passed" if valid else f"damaged member: {invalid_member}"
                    if valid and source.suffix.lower() == ".apk":
                        valid = "AndroidManifest.xml" in bundle.namelist()
                        detail = "APK structure passed" if valid else "AndroidManifest.xml is missing"
            except (OSError, zipfile.BadZipFile) as exc:
                valid = False
                detail = str(exc)[:200]
        all_valid = all_valid and valid
        results.append({
            "relative_path": relative,
            "valid": valid,
            "detail": detail,
            "sha256": _sha256(source) if valid else "",
        })

    installation = {"requested": policy.verify_installation, "status": "not_requested"}
    apk = next((
        (root / str(item.get("relative_path") or "")).resolve()
        for item in output_files
        if str(item.get("relative_path") or "").lower().endswith(".apk")
    ), None)
    if policy.verify_installation:
        if apk is None or not apk.is_file():
            installation = {"requested": True, "status": "missing_apk"}
            all_valid = False
        elif not allow_device_install:
            installation = {"requested": True, "status": "phone_handoff_required"}
        else:
            installation = _verify_android_install(apk)
            all_valid = all_valid and installation["status"] in {
                "installed",
                "phone_handoff_required",
            }

    return {
        "status": "passed" if all_valid and (output_files or not policy.requires_artifact) else "failed",
        "required_artifact": policy.requires_artifact,
        "outputs": results,
        "installation": installation,
    }


def _verify_android_install(apk: Path) -> dict:
    adb = shutil.which("adb")
    if not adb:
        return {"requested": True, "status": "phone_handoff_required", "detail": "adb unavailable"}
    try:
        devices = subprocess.run(
            [adb, "devices"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        connected = [
            line.split()[0]
            for line in devices.stdout.splitlines()[1:]
            if line.strip().endswith("\tdevice")
        ]
        if not connected:
            return {
                "requested": True,
                "status": "phone_handoff_required",
                "detail": "no authorized Android device",
            }
        installed = subprocess.run(
            [adb, "-s", connected[0], "install", "-r", str(apk)],
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )
        output = "\n".join((installed.stdout, installed.stderr)).strip()
        return {
            "requested": True,
            "status": "installed" if installed.returncode == 0 and "Success" in output else "install_failed",
            "device": connected[0],
            "detail": output[-500:],
        }
    except Exception as exc:
        return {"requested": True, "status": "install_failed", "detail": str(exc)[:300]}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
