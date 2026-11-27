"""Small, content-free observations for the phone's per-turn details."""
import re


def _id(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:/+@-]{0,119}", value) else ""


def attach(payload: dict, task: dict) -> None:
    generation = task.get("execution_generation", 1)
    task_id = task.get("task_id")
    if type(generation) is not int or not isinstance(task_id, str) or not task_id:
        return
    receipt = {}
    for e in task.get("delivery_trace") or ():
        if isinstance(e, dict) and e.get("stage") == "desktop_mqtt_received":
            if type(e.get("at")) is int and e["at"] > 0:
                receipt["desktop_received_at"] = e["at"]
                break
    best = 0
    for e in task.get("events") or ():
        if not isinstance(e, dict) or e.get("kind") not in ("agent", "model"):
            continue
        m = e.get("metadata")
        if not isinstance(m, dict) or m.get("execution_generation", 1) != generation:
            continue
        attempt = m.get("attempt")
        if (type(attempt) is not int or attempt < 1 or attempt < best or not _id(m.get("provider")) or
                e.get("event_id") != f"provider:{task_id}:{attempt - 1}"):
            continue
        best = attempt
        receipt["submission"] = {"attempt": attempt, "provider": _id(m["provider"]),
                                 "model": _id(m.get("model")), "effort": _id(m.get("reasoning_effort"))}
    if receipt:
        payload["turn_receipt"] = {**receipt, "generation": generation}
