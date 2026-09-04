"""Shared language policy helpers for GalaxySSI Desktop."""

from __future__ import annotations

import locale
import os
import sys


AUTO = "auto"
ZH_CN = "zh-CN"
EN_US = "en-US"
ZH_HK = "zh-HK"
ZH_TW = "zh-TW"
SUPPORTED_LANGUAGES = (AUTO, ZH_CN, EN_US, ZH_HK, ZH_TW)


def normalize_language(value: object) -> str:
    candidate = str(value or "").strip()
    for supported in SUPPORTED_LANGUAGES:
        if candidate.lower() == supported.lower():
            return supported
    return AUTO


def system_language_tag() -> str:
    configured = os.environ.get("GALAXYSSI_SYSTEM_LANGUAGE", "").strip()
    if configured:
        return _normalized_system_tag(configured)
    if sys.platform == "win32":
        detected = _windows_user_locale()
        if detected:
            return _normalized_system_tag(detected)
    current = locale.getlocale()[0] or os.environ.get("LANG", "") or EN_US
    return _normalized_system_tag(current)


def resolve_language(value: object) -> str:
    normalized = normalize_language(value)
    return system_language_tag() if normalized == AUTO else normalized


def language_name(value: object) -> str:
    resolved = resolve_language(value)
    if resolved == ZH_CN:
        return "Simplified Chinese"
    if resolved in {ZH_HK, ZH_TW}:
        return "Traditional Chinese"
    return "English"


def _normalized_system_tag(value: str) -> str:
    normalized = str(value or "").replace("_", "-").split(".", 1)[0].strip()
    lower = normalized.lower()
    if lower.startswith("zh-hk") or lower.startswith("zh-mo"):
        return ZH_HK
    if lower.startswith("zh-tw") or lower.startswith("zh-hant"):
        return ZH_TW
    if lower.startswith("zh"):
        return ZH_CN
    return EN_US


def _windows_user_locale() -> str:
    try:
        import ctypes

        buffer = ctypes.create_unicode_buffer(85)
        length = ctypes.windll.kernel32.GetUserDefaultLocaleName(buffer, len(buffer))
        return buffer.value if length > 0 else ""
    except (AttributeError, OSError):
        return ""
