"""Project only answer text from the mobile planner's cumulative JSON, never a plan."""
import json
import re


_PREFIX = re.compile(r'\s*\{\s*"disposition"\s*:\s*"respond"\s*,\s*"final_response"\s*:\s*')
_STRING = re.compile(r'"((?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[\da-fA-F]{4}))*)')


def supervised_answer_preview(raw):
    if not isinstance(raw, str) or len(raw) > 64_000:
        return ""
    value = raw.strip()
    if value.startswith("```json"):
        value = value[7:].strip().removesuffix("```").rstrip()
    prefix = _PREFIX.match(value)
    if not prefix:
        return ""
    part = _STRING.match(value, prefix.end())
    if not part:
        return ""
    tail = value[part.end():]
    if tail.startswith('"'):
        if tail[1:].lstrip()[:1] not in {"", ",", "}"}:
            return ""
    elif tail and not re.fullmatch(r'\\(?:u[\da-fA-F]{0,3})?', tail):
        return ""
    try:
        answer = json.loads('"' + part[1] + '"')
    except ValueError:
        return ""
    # A high surrogate may precede its low surrogate in the next delta.
    if answer and 0xD800 <= ord(answer[-1]) <= 0xDBFF:
        answer = answer[:-1]
    if any(0xD800 <= ord(char) <= 0xDFFF for char in answer):
        return ""
    return answer if tail.startswith('"') or len(answer.strip()) >= 24 else ""
