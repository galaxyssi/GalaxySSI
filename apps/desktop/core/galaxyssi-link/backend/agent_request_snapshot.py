"""Bounded private request options for restarting admitted, unstarted work."""
import json

MAX_SNAPSHOT_BYTES = 512 * 1024
OPTION_FIELDS = frozenset({
    "response_language", "response_language_preference", "connector_task_mode",
    "execution_policy_prompt", "execution_mode", "agent_instance_id",
})
ATTACHMENT_FIELDS = frozenset({
    "id", "transfer_id", "name", "mime_type", "type", "size", "transport_size",
    "sha256", "transport_status", "attachment_request_id", "data_b64",
})


def never_dispatched(task) -> bool:
    return (getattr(task, "execution_checkpoint", {}).get("dispatch_started") is False
            and not getattr(task, "started_at", 0) and not getattr(task, "thread_id", "")
            and not getattr(task, "turn_id", "")
            and getattr(task, "status", "") in {"accepted", "queued", "recovering"})


def snapshot_copy(value: dict | None) -> dict:
    if not value:
        return {}
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("options"), dict):
        raise ValueError("Unsupported Agent request snapshot")
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    if len(encoded.encode("utf-8")) > MAX_SNAPSHOT_BYTES:
        raise ValueError("Agent request snapshot exceeds size limit")
    return json.loads(encoded)


def build_request_snapshot(payload: dict, *, model_id: str, reasoning_effort: str, policy: dict) -> dict:
    options = {key: payload[key] for key in OPTION_FIELDS if key in payload and isinstance(payload[key], str)}
    attachments = payload.get("attachments") or []
    if not isinstance(attachments, list) or len(attachments) > 12:
        raise ValueError("Invalid Agent request attachment list")
    options["attachments"] = []
    for attachment in attachments:
        if not isinstance(attachment, dict):
            raise ValueError("Invalid Agent request attachment")
        options["attachments"].append({
            key: value for key, value in attachment.items()
            if key in ATTACHMENT_FIELDS and isinstance(value, (str, int, float, bool))
        })
    options["agent_invocation"] = {"model_id": model_id, "reasoning_effort": reasoning_effort}
    options["execution_mode"] = policy.get("execution_mode", options.get("execution_mode", "auto_complete"))
    options["task_budget"] = policy.get("task_budget", {})
    return snapshot_copy({"version": 1, "options": options})


def restore_request_options(snapshot: dict) -> dict:
    value = snapshot_copy(snapshot)
    options = value.get("options", {})
    # Identity and security grants are deliberately not restorable options.
    return {key: item for key, item in options.items()
            if key in OPTION_FIELDS or key in {"attachments", "agent_invocation", "task_budget"}}
