"""Read tool-free planning SSE without retaining intermediate reasoning."""
from __future__ import annotations

import json


RESPONSE_LIMIT = 2 * 1024 * 1024


class PlanningStreamError(ValueError):
    pass


def read_decision_stream(response) -> str:
    used, data, content = 0, [], []
    finished = False
    while True:
        # The connection timeout measures socket inactivity, not total generation.
        line = response.readline(RESPONSE_LIMIT - used + 1)
        used += len(line)
        if used > RESPONSE_LIMIT:
            raise PlanningStreamError("Local planning response exceeded the response envelope")
        if not line:
            raise PlanningStreamError("Local planning stream ended before completion")
        line = line.rstrip(b"\r\n")
        if line:
            if line.startswith(b"data:"):
                data.append(line[5:].removeprefix(b" "))
            continue
        if not data:
            continue
        event = b"\n".join(data)
        data.clear()
        if event == b"[DONE]":
            if not finished or not content:
                raise PlanningStreamError("Local planner did not finish a decision")
            return "".join(content)
        payload = json.loads(event)
        if not isinstance(payload, dict) or payload.get("error"):
            raise PlanningStreamError("Local planning stream returned an error")
        choices = payload.get("choices", [])
        if not isinstance(choices, list) or len(choices) > 1:
            raise PlanningStreamError("Local planning stream returned ambiguous choices")
        for choice in choices:
            if not isinstance(choice, dict) or choice.get("index", 0) != 0 or finished:
                raise PlanningStreamError("Local planning stream returned an invalid choice")
            delta = choice.get("delta", {})
            if not isinstance(delta, dict) or delta.get("tool_calls") or delta.get("function_call"):
                raise PlanningStreamError("Local planner requested tools")
            value = delta.get("content")
            if value is not None:
                if not isinstance(value, str):
                    raise PlanningStreamError("Local planner returned invalid content")
                if value:
                    content.append(value)
            reason = choice.get("finish_reason")
            if reason is not None:
                if reason != "stop":
                    raise PlanningStreamError("Local planner did not finish normally")
                finished = True
