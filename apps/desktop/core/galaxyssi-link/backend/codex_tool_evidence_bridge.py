"""Host-only capture/query boundary; evidence failure never repeats a tool."""
import logging

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
    try:
        return manager.tool_evidence.query(request, client_route_id=client_route_id, phone_import=True)
    except Exception:
        log.warning("Task evidence lookup failed; no task was started or resumed")
        return None
