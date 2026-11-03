"""Content-free receive-stage observations; never changes message handling."""
import hashlib
import logging

RESPONSE_TYPES = frozenset({
    "collaboration_recall_result", "collaboration_publish_result", "collaboration_tool_test_result",
    "agent_task_evidence_request",
})
STAGES = frozenset({"stored", "dispatch", "finished", "failed"})
log = logging.getLogger(__name__)


def observe(payload, timings, stage, now_ns):
    if not isinstance(payload, dict):
        return
    kind = payload.get("type")
    if not isinstance(kind, str) or kind not in RESPONSE_TYPES or stage not in STAGES:
        return
    request_id = payload.get("request_id")
    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
        return
    try:
        points = dict(timings)
        def duration(start, end):
            a, b = points.get(start), points.get(end)
            return round((b - a) / 1_000_000, 3) if type(a) is int and type(b) is int and 0 <= a <= b else -1
        points["observed"] = now_ns
        token = hashlib.sha256(request_id.encode()).hexdigest()[:16]
        log.info("Collaboration receive rpc=%s stage=%s queue_ms=%s decrypt_ms=%s handler_elapsed_ms=%s",
                 token, stage, duration("desktop_request_received", "desktop_handler_started"),
                 duration("desktop_decrypt_started", "desktop_signal_decrypt_finished"),
                 duration("desktop_handler_started", "observed"))
    except Exception:
        pass
