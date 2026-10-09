"""Scope APK delivery checks to positive Android installation requests.

This is a conservative delivery classifier, not an authorization mechanism.
"""

import re


_CLAUSE = re.compile(r"[;!?\n\u3002\uff1b\uff01\uff1f]|\.(?=\s|$)|\b(?:but|however|instead)\b|\u4f46\u662f|\u4f46|\u4e0d\u8fc7", re.I)
_ACTION = re.compile(r"\b(?:install|reinstall|deploy)\b|\u5b89\u88c5|\u5b89\u88dd", re.I)
_NEGATIVE = re.compile(
    r"\b(?:do not|don't|must not|mustn't|never|without|no need to|cannot|can't)\b"
    r"|\u4e0d\u8981|\u4e0d\u5f97|\u4e0d\u80fd|\u4e0d\u5fc5|\u65e0\u9700|\u7121\u9700|\u4e0d\u7528|\u7981\u6b62|\u52ff", re.I,
)
_PREFIX = r"\s*(?:(?:the|this|that|an?|latest|new|signed|local)\s+|\u8fd9\u4e2a|\u9019\u500b|\u8be5|\u8a72|\u6700\u65b0|\u65b0\u7684)*"
_APK = r"(?:apk\b|[`\"']?[^\s,;!?\u3002\uff0c]+\.apk(?:[`\"']|\b))"
_ANDROID = re.compile(_PREFIX + r"(?:android\b|\u5b89\u5353|" + _APK + r")", re.I)
_APP = re.compile(_PREFIX + r"(?:app(?:lication)?\b|package\b|it\b|\u5e94\u7528|\u61c9\u7528|\u5b89\u88c5\u5305|\u5b89\u88dd\u5305)", re.I)
_PHONE_DESTINATION = re.compile(
    r"\b(?:on|onto|to)\s+(?:(?:the|my|this|an?|android)\s+)*(?:phone|android)\b"
    r"|(?:\u5230|\u81f3)(?:\u8fd9\u53f0|\u9019\u53f0|\u6211\u7684)?(?:\u624b\u673a|\u624b\u6a5f|\u5b89\u5353)", re.I,
)
_PREPOSED_APK = re.compile(r"(?:\bapk|\.apk)[`\"']?\s*$", re.I)


def installation_request(text: str) -> tuple[bool, bool]:
    """Return (positive install action, explicit Android package target).

    A negated list stays negative until a sentence or contrast boundary. An
    Android mention elsewhere must not turn an arbitrary object into an APK.
    """
    requested = android = False
    for clause in _CLAUSE.split(str(text or "")):
        for action in _ACTION.finditer(clause):
            before = clause[:action.start()]
            after = clause[action.end():]
            if _NEGATIVE.search(before):
                continue
            if before.endswith(('"', "'")) and re.match(r"[\"']\s*:", after):
                continue
            requested = True
            # Limit the object to this verb, not a later action in the clause.
            following = _ACTION.search(after)
            tail = after[:following.start()] if following else after
            destination = _PHONE_DESTINATION.search(tail)
            android |= bool(
                _ANDROID.match(tail)
                or _PREPOSED_APK.search(before)
                or (destination and (_APP.match(tail) or not tail[:destination.start()].strip()))
            )
    return requested, android
