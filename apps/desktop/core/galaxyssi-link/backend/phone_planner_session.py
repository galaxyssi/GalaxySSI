"""Provider history scoped to one authenticated phone goal, never a whole device."""

import hashlib
import json


def phone_planner_session(*, mode, client_route, conversation, turn, model, instance=""):
    if mode != "phone_supervised_project_plan_v1":
        return ""
    if not all(isinstance(value, str) and value.strip() for value in (client_route, conversation, turn)):
        return ""
    identity = [client_route, conversation, turn, model, instance]
    digest = hashlib.sha256(json.dumps(identity, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()
    return f"phone-planner-v1:{digest}"
