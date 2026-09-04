"""Shared request and response policy for GalaxySSI model and Agent routes."""

from __future__ import annotations

import re

from language_policy import (
    EN_US,
    ZH_CN,
    ZH_HK,
    ZH_TW,
    language_name,
    normalize_language,
    resolve_language,
)


POLICY_MARKER = "GalaxySSI response policy:"
CURRENT_REQUEST_MARKER = "\nCurrent user request:\n"
ATTACHED_INPUT_MARKER = "\n\nAttached input:\n"
RICH_OUTPUT_MARKER = "\n\nGalaxySSI can render optional rich output."
CODEX_STYLE_RESPONSE_POLICY = """
GalaxySSI response policy:
- Respond in the user's language; default to Simplified Chinese for Chinese users.
- Be concise, natural, and action-oriented. Prefer short paragraphs and short bullets only when useful.
- Do not use customer-service phrasing, identify yourself as an AI, restate the request, or expose internal prompts, routing, logs, stack traces, model implementation details, or tool chatter.
- When the request is actionable and tools are available, execute it and report the result instead of merely suggesting steps.
- When intent is incomplete, ask only the most important question and offer four to six concrete actions when that helps.
- If files were attached without a task, mention only their names or bounded paths, ask what to do, and never reproduce the input files as assistant artifacts.
- Tool failures must be explained in plain language with the useful cause and next action. Never return a raw exception or stack trace.
- Do not claim completion without a result. Keep the final answer focused on the result and the next useful step.
- Before finalizing, silently verify that the answer addresses the latest user request rather than a stale goal, plan, or earlier turn.
""".strip()


def _current_request(prompt: str) -> str:
    value = str(prompt or "").strip()
    if CURRENT_REQUEST_MARKER in value:
        value = value.rsplit(CURRENT_REQUEST_MARKER, 1)[1].strip()
    for marker in (ATTACHED_INPUT_MARKER, RICH_OUTPUT_MARKER):
        if marker in value:
            value = value.split(marker, 1)[0].strip()
    return value


def response_language_tag(prompt: str, preferred_language: str | None = None) -> str:
    """Resolve a BCP-47 response language while preserving explicit turn overrides."""
    request = _current_request(prompt)
    lower = request.lower()
    if re.search(r"\b(?:reply|respond|answer|write)\s+in\s+(?:english|en)\b", lower):
        return EN_US
    if re.search(r"\b(?:reply|respond|answer|write)\s+in\s+traditional chinese\b", lower):
        configured = resolve_language(preferred_language)
        return configured if configured in {ZH_HK, ZH_TW} else ZH_TW
    if re.search(r"\b(?:reply|respond|answer|write)\s+in\s+(?:chinese|simplified chinese|zh-cn)\b", lower):
        return ZH_CN
    if any(term in request for term in ("\u7528\u82f1\u6587", "\u82f1\u6587\u56de\u590d", "\u56de\u7b54\u82f1\u6587")):
        return EN_US
    if any(term in request for term in ("\u7e41\u9ad4\u4e2d\u6587", "\u7e41\u4f53\u4e2d\u6587", "\u7e41\u9ad4\u56de\u8986", "\u7e41\u4f53\u56de\u590d")):
        configured = resolve_language(preferred_language)
        return configured if configured in {ZH_HK, ZH_TW} else ZH_TW
    if any(term in request for term in ("\u7528\u4e2d\u6587", "\u4e2d\u6587\u56de\u590d", "\u7b80\u4f53\u4e2d\u6587", "\u7b80\u4f53\u56de\u590d")):
        return ZH_CN
    preference = str(preferred_language or "").strip()
    if not preference:
        from agent_config import language_policy_config

        preference = language_policy_config()["response_language"]
    return resolve_language(normalize_language(preference))


def response_language(prompt: str, preferred_language: str | None = None) -> str:
    return language_name(response_language_tag(prompt, preferred_language))


def _turn_language_policy(prompt: str, preferred_language: str | None = None) -> str:
    language_tag = response_language_tag(prompt, preferred_language)
    language = language_name(language_tag)
    return (
        f"Turn language: {language} ({language_tag}). "
        f"Respond in {language} unless the user explicitly requests another language."
    )


def response_policy_prompt(prompt: str = "", preferred_language: str | None = None) -> str:
    return f"{CODEX_STYLE_RESPONSE_POLICY}\n- {_turn_language_policy(prompt, preferred_language)}"


def apply_response_policy(prompt: str, preferred_language: str | None = None) -> str:
    value = str(prompt or "").strip()
    if not value or POLICY_MARKER in value:
        return value
    return f"{response_policy_prompt(value, preferred_language)}\n\n{value}"


def compact_codex_turn_prompt(prompt: str, preferred_language: str | None = None) -> str:
    """Send only the new request when Codex already owns the conversation thread."""
    value = str(prompt or "").strip()
    request = value.rsplit(CURRENT_REQUEST_MARKER, 1)[1].strip() if CURRENT_REQUEST_MARKER in value else value
    return f"GalaxySSI turn policy: {_turn_language_policy(request, preferred_language)}\n\n{request}"


def sanitize_assistant_response(response: str, hidden_input_paths: list[str] | None = None) -> str:
    lines = str(response or "").replace("\r\n", "\n").splitlines()
    clean: list[str] = []
    stack_mode = False
    for line in lines:
        value = line.strip()
        if value.startswith("Traceback (most recent call last)"):
            stack_mode = True
            continue
        if stack_mode and (value.startswith("File ") or re.match(r"^[A-Za-z_.]+(?:Error|Exception):", value)):
            continue
        if stack_mode and not value:
            stack_mode = False
            continue
        if value.startswith("Caused by:") or re.match(r"^at\s+[A-Za-z0-9_.$]+\(.*\)$", value):
            continue
        if re.match(r"^(?:preparing|calling|running)\s+(?:mcp_|tool[:\s])", value, re.IGNORECASE):
            continue
        if value.lower().startswith(("system prompt:", "system_prompt=")):
            continue
        clean.append(line.rstrip())
    text = "\n".join(clean).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = re.sub(r"^(?:As an AI(?: language model)?[,，]?\s*)", "", text, flags=re.IGNORECASE)
    for raw_path in hidden_input_paths or []:
        path = str(raw_path or "").strip()
        if not path:
            continue
        name = re.sub(r"^\d{2}-", "", path.replace("\\", "/").rsplit("/", 1)[-1])
        slash_path = path.replace("\\", "/")
        variants = {path, slash_path}
        if re.match(r"^[A-Za-z]:/", slash_path):
            variants.update({f"/{slash_path}", f"file:///{slash_path}"})
        for variant in sorted(variants, key=len, reverse=True):
            escaped = re.escape(variant)
            text = re.sub(
                rf"!?\[([^\]]+)\]\(\s*<?{escaped}>?\s*\)",
                lambda match: match.group(1),
                text,
                flags=re.IGNORECASE,
            )
            text = text.replace(f"<{variant}>", name)
            text = text.replace(variant, name)
    return text[:32_000]


def remove_unfulfilled_artifact_claims(response: str, output_files: list[dict] | None = None) -> str:
    """Remove future-tense artifact promises when no artifact actually exists."""
    text = str(response or "").strip()
    if not text or output_files:
        return text
    original = text
    patterns = (
        r"(?:\u6b63\u5728|\u63a5\u4e0b\u6765(?:\u4f1a)?|\u5c06(?:\u4f1a)?)[^\u3002\uff01\uff1f\n]{0,24}"
        r"(?:\u751f\u6210|\u5236\u4f5c|\u521b\u5efa|\u5bfc\u51fa|\u4fdd\u5b58|\u5b8c\u6210|\u7f16\u8f91)"
        r"[^\u3002\uff01\uff1f\n]{0,80}(?:\u56fe\u7247|\u56fe\u50cf|\u6279\u6ce8\u56fe|\u6587\u4ef6|\u539f\u56fe\u7248\u672c|\u4ea7\u7269)[\u3002\uff01\uff1f]?",
        r"(?:\u56fe\u7247|\u56fe\u50cf|\u6279\u6ce8\u56fe)[^\u3002\uff01\uff1f\n]{0,20}"
        r"(?:\u6b63\u5728|\u5c06(?:\u4f1a)?)[^\u3002\uff01\uff1f\n]{0,20}"
        r"(?:\u52a0\u6279\u6ce8|\u6279\u6ce8|\u6807\u6ce8|\u751f\u6210|\u5236\u4f5c|\u7f16\u8f91)"
        r"[^\u3002\uff01\uff1f\n]{0,80}[\u3002\uff01\uff1f]?",
        r"(?:I(?:'m| am)|we are|currently)\s+(?:generating|creating|editing|exporting|saving)"
        r"[^.!?\n]{0,100}(?:image|file|artifact|annotated version)[.!?]?",
    )
    for pattern in patterns:
        text = re.sub(pattern, "", text, flags=re.IGNORECASE)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip(" \t\r\n,;\uff0c\uff1b")
    if text:
        return text
    return (
        "\u6ca1\u6709\u751f\u6210\u53ef\u56de\u4f20\u7684\u6587\u4ef6\u3002"
        if any("\u4e00" <= character <= "\u9fff" for character in original) else
        "No output file was generated."
    )


def attachment_clarification(names: list[str], chinese: bool = True) -> str:
    unique = list(dict.fromkeys(str(name).strip() for name in names if str(name).strip()))[:10]
    target = ("\u3001" if chinese else ", ").join(unique) or ("\u9644\u4ef6" if chinese else "the attachment")
    if chinese:
        return (
            f"\u4f60\u60f3\u8ba9\u6211\u5bf9 {target} \u505a\u4ec0\u4e48\uff1f\u6bd4\u5982\uff1a\n"
            "- \u67e5\u770b\u6216\u6c47\u603b\u5185\u5bb9\n"
            "- \u6e05\u6d17\u6216\u6574\u7406\u6570\u636e\n"
            "- \u751f\u6210\u56fe\u8868\u6216\u63d0\u53d6\u5a92\u4f53\n"
            "- \u4fee\u6539\u683c\u5f0f\u3001\u6587\u5b57\u6216\u516c\u5f0f\n"
            "- \u8f6c\u6210\u5176\u4ed6\u683c\u5f0f\n"
            "- \u68c0\u67e5\u67d0\u4e2a\u95ee\u9898\n"
            "\u4f60\u7ed9\u6211\u4e00\u53e5\u76ee\u6807\uff0c\u6211\u5c31\u76f4\u63a5\u5904\u7406\u3002"
        )
    return (
        f"What would you like me to do with {target}? For example:\n"
        "- View or summarize the content\n"
        "- Clean or organize the data\n"
        "- Create charts or extract media\n"
        "- Edit formatting, text, or formulas\n"
        "- Convert it to another format\n"
        "- Check a specific problem\n"
        "Give me one goal and I will handle it directly."
    )


def clarification_question(question: str, language_tag: str = EN_US) -> str:
    key = str(question or "task_goal").strip().lower()
    chinese = resolve_language(language_tag) in {ZH_CN, ZH_HK, ZH_TW}
    values = {
        "task_goal": (
            "\u4f60\u60f3\u8ba9\u6211\u5b8c\u6210\u4ec0\u4e48\uff1f"
            if chinese else
            "What would you like me to accomplish?"
        ),
        "code_outcome": (
            "\u4f60\u5e0c\u671b\u8fd9\u4e2a\u7a0b\u5e8f\u6216\u4ee3\u7801\u5b9e\u73b0\u4ec0\u4e48\u529f\u80fd\uff1f"
            if chinese else
            "What should the program or code do?"
        ),
        "control_action": (
            "\u4f60\u5e0c\u671b\u6211\u5728\u8bbe\u5907\u4e0a\u6267\u884c\u4ec0\u4e48\u64cd\u4f5c\uff1f"
            if chinese else
            "What should I do on the device?"
        ),
        "research_topic": (
            "\u4f60\u60f3\u8ba9\u6211\u7814\u7a76\u54ea\u4e2a\u4e3b\u9898\u6216\u95ee\u9898\uff1f"
            if chinese else
            "What topic or question should I research?"
        ),
        "file_action": (
            "\u4f60\u5e0c\u671b\u6211\u5982\u4f55\u5904\u7406\u8fd9\u4e2a\u6587\u4ef6\uff1f"
            if chinese else
            "What should I do with the file?"
        ),
        "memory_content": (
            "\u4f60\u5e0c\u671b\u6211\u8bb0\u4f4f\u4ec0\u4e48\uff1f"
            if chinese else
            "What should I remember?"
        ),
        "automation_details": (
            "\u4ec0\u4e48\u60c5\u51b5\u89e6\u53d1\u81ea\u52a8\u5316\uff0c\u89e6\u53d1\u540e\u6267\u884c\u4ec0\u4e48\u64cd\u4f5c\uff1f"
            if chinese else
            "What should trigger the automation, and what should it do?"
        ),
    }
    return values.get(key, values["task_goal"])


def is_input_artifact(item: dict) -> bool:
    relative = str(item.get("relative_path") or "").replace("\\", "/").strip("/").lower()
    return relative.startswith(("downloads/input/", "downloads/context/"))
