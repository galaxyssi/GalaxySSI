from __future__ import annotations


PHONE_SUPERVISED_PROJECT_PLAN = "phone_supervised_project_plan_v1"
_KNOWN_MODES = frozenset({PHONE_SUPERVISED_PROJECT_PLAN})


def normalize_connector_task_mode(value: object) -> str:
    normalized = str(value or "").strip().lower()
    return normalized if normalized in _KNOWN_MODES else ""


def is_structured_connector_task_mode(value: object) -> bool:
    return normalize_connector_task_mode(value) == PHONE_SUPERVISED_PROJECT_PLAN
