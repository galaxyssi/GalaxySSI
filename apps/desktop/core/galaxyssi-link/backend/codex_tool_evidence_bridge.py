"""Host-only capture/query boundary; evidence failure never repeats a tool."""
import logging
import time
import hashlib

log = logging.getLogger(__name__)


def observe(request, stage, started, *, accepted=None):
    """Correlate transport stages without logging request identity or evidence."""
    request_id = request.get("request_id") if isinstance(request, dict) else None
    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128:
        return
    if stage not in {"lookup_ready", "lookup_unavailable", "lookup_rejected", "publish_started", "publish_finished"}:
        return
    try:
        token = hashlib.sha256(request_id.encode()).hexdigest()[:16]
        log.info("Evidence exchange rpc=%s stage=%s elapsed_ms=%.1f accepted=%s at_ms=%s",
                 token, stage, (time.monotonic() - started) * 1000, accepted, time.time_ns() // 1_000_000)
    except Exception:
        pass


def publish_response(request, publish):
    started = time.monotonic()
    observe(request, "publish_started", started)
    accepted = publish()
    observe(request, "publish_finished", started, accepted=bool(accepted))
    return accepted


def capture(mutations, event: dict) -> dict | None:
    observation = event.get("tool_observation")
    if not isinstance(observation, dict):
        return None
    try:
        snapshot = mutations.snapshot()
        if snapshot is None:
            return None
        return mutations.manager.tool_evidence.record(snapshot, observation)
    except Exception:
        # Do not log tool inputs/results or turn bookkeeping failure into re-execution.
        log.warning("Codex tool evidence was not durably recorded; operation will not be repeated")
        return None


def query(manager, request: dict, *, client_route_id: str) -> dict | None:
    started = time.monotonic()
    try:
        response = manager.tool_evidence.query(request, client_route_id=client_route_id, phone_import=True)
        outcome = response.get("status") if response is not None else "rejected"
        observe(request, f"lookup_{outcome}", started)
        return response
    except Exception as error:
        log.warning("Task evidence lookup failed (%s); no task was started or resumed", type(error).__name__)
        return None
