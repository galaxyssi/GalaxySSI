"""Host-only capture/query boundary; evidence failure never repeats a tool."""
import logging
import time

log = logging.getLogger(__name__)


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
        log.info("Read-only evidence lookup outcome=%s elapsed_ms=%.1f", outcome, (time.monotonic() - started) * 1000)
        return response
    except Exception as error:
        log.warning("Task evidence lookup failed (%s); no task was started or resumed", type(error).__name__)
        return None
