"""Bounded request matching for artifact routing, not an authorization policy."""

import re
from pathlib import PurePosixPath


_NEGATIVE_PREFIX = re.compile(
    r"(?:(?:\u4e0d\u8981|\u4e0d\u80fd|\u4e0d\u5fc5|\u65e0\u9700|\u4e0d\u7528|\u52ff)(?:\u53ea)?"
    r"(?:\u7ed9\u51fa|\u63d0\u4f9b|\u8fd4\u56de|\u8f93\u51fa|\u5c55\u793a|\u663e\u793a|\u9644\u4e0a|\u5305\u542b|\u7ed9|\u5199|\u7f16\u5199|\u751f\u6210|\u6267\u884c|\u8fd0\u884c)"
    r"[^\u3002\uff01\uff1f;\uff1b,\uff0c\n]{0,40}|"
    r"(?:\u4e0d\u8981|\u65e0\u9700|\u4e0d\u7528|\u4e0d\u9700\u8981)\s*|"
    r"\b(?:do not|don't|never|no need to)\s+(?:only\s+|just\s+)?"
    r"(?:(?:give|return|provide|show|output|include|write|generate|run|execute)"
    r"[^.!?;,\n]{0,40})?)$",
    re.IGNORECASE,
)
_ASCII_WORD = re.compile(r"[a-z0-9_]", re.IGNORECASE)
_OFFICE_REQUEST = re.compile(
    r"(?:\b(?:create|generate|export|produce)\b|\u751f\u6210|\u5236\u4f5c|\u521b\u5efa|\u5bfc\u51fa)"
    r"[^\u3002\uff01\uff1f.!?;\uff1b\n]{0,60}?"
    r"(?<![a-z0-9_])(?:docx|word|xlsx|excel|pptx|ppt|powerpoint)(?![a-z0-9_])",
    re.IGNORECASE,
)


def positive_term(text: str, term: str) -> bool:
    """Ignore quoted record keys, embedded English words and local negations."""
    text, term = text.lower(), term.lower()
    for match in re.finditer(re.escape(term), text):
        start, end = match.span()
        if term.isascii() and (
            (start > 0 and _ASCII_WORD.fullmatch(text[start - 1]))
            or (end < len(text) and _ASCII_WORD.fullmatch(text[end]))
        ):
            continue
        quote = text[start - 1] if start else ""
        if quote in ('"', "'") and text[end:end + 1] == quote and text[end + 1:].lstrip().startswith(":"):
            continue
        if not _NEGATIVE_PREFIX.search(text[max(0, start - 80):start]):
            return True
    return False


def office_artifact_requested(text: str) -> bool:
    return any(not _NEGATIVE_PREFIX.search(text[max(0, m.start() - 80):m.start()])
               for m in _OFFICE_REQUEST.finditer(text))


def keep_office_outputs_separate(prompt: str, artifacts: list[dict]) -> bool:
    if not office_artifact_requested(prompt) or any(positive_term(prompt, term) for term in (
        "zip", "archive", "\u6253\u5305", "\u538b\u7f29\u5305",
    )):
        return False
    return any(item.get("category") == "outputs" and
               PurePosixPath(str(item.get("relative_path", ""))).suffix.lower() in {".docx", ".xlsx", ".pptx"}
               for item in artifacts)
