"""Source-grounded literal constraints compiled without viewing candidate contents."""
from __future__ import annotations

import json
import re

from .common import model_context_json, sha256_text, stable_json
from .legacy import EvolutionError
from .local_planning import LocalPlannerUnavailable
from .literal_contract_prompt import contract_messages


KINDS = {"contains", "absent", "markdown_heading"}
COMPILER_VERSION = 4


def contract_input(evidence):
    parent = next((row["text"] for row in evidence["requirements"] if row["id"] == "parent-intent"), None)
    if parent is None:
        return None
    return {"original_goal": parent, "child_task": next(row["text"] for row in evidence["requirements"] if row["id"] == "task"),
            "scope": evidence["scope"], "paths": list(evidence["files"])}


def contract_schema(paths):
    text = {"type": "string", "minLength": 1}
    return {"type": "object", "properties": {"checks": {"type": "array", "items": {
        "type": "object", "properties": {"kind": {"enum": sorted(KINDS)}, "path": {"enum": paths},
        "text": text, "case_sensitive": {"type": "boolean"}},
        "required": ["kind", "path", "text", "case_sensitive"], "additionalProperties": False}}},
        "required": ["checks"], "additionalProperties": False}


def validate_contract(value, source):
    if not isinstance(value, dict) or set(value) != {"checks"} or not isinstance(value["checks"], list):
        raise ValueError("Literal contract must contain a checks array")
    seen = set()
    for index, check in enumerate(value["checks"]):
        if not isinstance(check, dict) or set(check) != {"kind", "path", "text", "source_quote", "case_sensitive"}:
            raise ValueError("Invalid literal check fields")
        if (not isinstance(check["kind"], str) or check["kind"] not in KINDS or check["path"] not in source["paths"]
                or type(check["case_sensitive"]) is not bool):
            raise ValueError("Unsupported literal check kind, path or case mode")
        text, quote = check["text"], check["source_quote"]
        if not isinstance(quote, str) or not quote.strip() or quote not in source["original_goal"]:
            raise ValueError(f"Check {index}: source_quote must be copied exactly from original_goal, without translation or paraphrase")
        if not isinstance(text, str) or not text.strip() or text.casefold() not in quote.casefold():
            raise ValueError(f"Check {index}: text must occur literally in source_quote. Semantic instructions are reviewed separately; do not invent output text")
        key = stable_json(check)
        if key in seen:
            raise ValueError("Duplicate literal constraint")
        seen.add(key)
    return value["checks"]


def ground_contract(value, source):
    if not isinstance(value, dict) or set(value) != {"checks"} or not isinstance(value["checks"], list):
        raise ValueError("Literal contract must contain a checks array")
    grounded = []
    goal = source["original_goal"]
    for index, check in enumerate(value["checks"]):
        if not isinstance(check, dict) or set(check) != {"kind", "path", "text", "case_sensitive"}:
            raise ValueError("Return only kind, path, text and case_sensitive; the host attaches source quotes")
        text = check["text"]
        match = re.search(re.escape(text), goal, re.IGNORECASE) if isinstance(text, str) and text.strip() else None
        if match is None or match.group().casefold() != text.casefold():
            raise ValueError(f"Check {index} ({str(text)[:160]!r}): text must occur literally in original_goal; do not translate or invent output text")
        quote = goal[max(0, match.start() - 96):min(len(goal), match.end() + 96)]
        grounded.append({**check, "source_quote": quote})
    return validate_contract({"checks": grounded}, source)


def inspect_partial_contract(value, source):
    if not isinstance(value, dict) or set(value) != {"checks"} or not isinstance(value["checks"], list):
        raise ValueError("Literal contract must contain a checks array")
    checks, issues, seen = [], [], set()
    for index, check in enumerate(value["checks"]):
        try:
            grounded = ground_contract({"checks": [check]}, source)[0]
            key = stable_json(grounded)
            if key in seen:
                raise ValueError("Duplicate literal constraint")
            seen.add(key)
            checks.append(grounded)
        except ValueError as error:
            issues.append(f"Check {index}: {error}")
    if issues and not checks:
        raise ValueError("; ".join(issues)[:500])
    return checks, issues


def compile_contract(evidence, infer, previous=None):
    source = contract_input(evidence)
    if source is None:
        return None
    source_hash = sha256_text(stable_json(source))
    if (isinstance(previous, dict) and previous.get("version") == COMPILER_VERSION
            and previous.get("source_hash") == source_hash and previous.get("issues") == []):
        try:
            validate_contract({"checks": previous["checks"]}, source)
            return previous
        except (KeyError, TypeError, ValueError):
            pass
    messages = contract_messages(source)
    try:
        schema = contract_schema(source["paths"])
        response = infer(messages, response_schema=schema)
        issues = []
        try:
            checks = ground_contract(json.loads(response), source)
        except ValueError as error:
            # One protocol correction, not a retry of implementation or the parent goal.
            messages.append({"role": "assistant", "content": response})
            messages.append({"role": "user", "content": model_context_json({
                "validation_error": str(error),
                "action": "Correct the contract using the unchanged original goal. Keep valid applicable literal checks; remove invented semantic literals. Do not omit an explicit named heading."})})
            checks, issues = inspect_partial_contract(json.loads(infer(messages, response_schema=schema)), source)
    except Exception as error:
        detail = str(error)[:500] if isinstance(error, (ValueError, LocalPlannerUnavailable)) else type(error).__name__
        raise EvolutionError("acceptance_review_unavailable", "Original-goal literal contract is unavailable: " + detail) from error
    return {"version": COMPILER_VERSION, "source_hash": source_hash, "checks": checks, "issues": issues}


def headings(text):
    from markdown_it import MarkdownIt
    tokens = MarkdownIt("commonmark").parse(text)
    result = []
    for index, token in enumerate(tokens[:-1]):
        if token.type == "heading_open" and token.level == 0 and tokens[index + 1].type == "inline":
            children = tokens[index + 1].children or []
            result.append("".join(child.content if child.type in {"text", "code_inline"} else " "
                                  if child.type in {"softbreak", "hardbreak"} else "" for child in children))
    return result


def evaluate_contract(contract, files):
    results = []
    for check in contract["checks"] if contract else []:
        content = files[check["path"]]["after"] or ""
        normalize = (lambda value: value) if check["case_sensitive"] else str.casefold
        needle = normalize(check["text"])
        if check["kind"] == "markdown_heading":
            passed = any(normalize(value) == needle for value in headings(content))
        else:
            found = needle in normalize(content)
            passed = not found if check["kind"] == "absent" else found
        results.append({"check": check, "passed": passed})
    return results
