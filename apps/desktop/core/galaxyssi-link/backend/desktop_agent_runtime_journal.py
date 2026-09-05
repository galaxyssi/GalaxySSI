"""Runtime checkpoint projection without loading complete Run histories."""

from __future__ import annotations

from agent_run_kernel import AgentRunEventLedger, AgentRunIdentityConflict, runtime_projection_event


def runtime_checkpoint(row: dict, event_type: str, timestamp: int, payload: dict) -> dict:
    data = {key: value for key, value in row.items() if key != "events"}
    data["updated_at"] = timestamp
    data["cursor"] = int(row.get("cursor") or 0) + 1
    state = event_type.removeprefix("run_")
    if state == "started":
        data["state"] = "running"
        data["started_at"] = timestamp
    elif state in {"queued", "completed", "observed", "ignored", "failed", "cancelled", "interrupted"}:
        data["state"] = state
        if state != "queued":
            data["finished_at"] = timestamp
    for key in ("error", "adapter_result"):
        if key in payload:
            data[key] = payload[key]
    return data


def restore_checkpoint_rows(
    ledger: AgentRunEventLedger,
    kind: str,
    runs: dict,
    *,
    recent_limit: int,
    event_limit: int,
) -> bool:
    changed = False
    seen: set[str] = set()
    # Recent completed runs are a bounded UI cache; no live run is evicted.
    for recoverable_only in (False, True):
        before = None
        remaining = recent_limit
        while recoverable_only or remaining > 0:
            page = ledger.checkpoints(
                kind, before=before, limit=256 if recoverable_only else min(256, remaining),
                recoverable_only=recoverable_only,
            )
            if not page:
                break
            for checkpoint in page:
                run_id = checkpoint["run_id"]
                if run_id in seen:
                    continue
                seen.add(run_id)
                row = checkpoint["data"]
                sequence = checkpoint["sequence"]
                identity = runtime_projection_event(row, "run_started", sequence, 0).root_identity
                if any(identity.public()[key] != checkpoint[key] for key in identity.public()):
                    raise AgentRunIdentityConflict("Runtime checkpoint changed the Run root identity")
                existing = runs.get(run_id)
                if isinstance(existing, dict):
                    cursor = int(existing.get("cursor") or 0)
                    if cursor > sequence:
                        continue
                    if cursor == sequence and {
                        key: value for key, value in existing.items() if key != "events"
                    } == row:
                        continue
                row["cursor"] = sequence
                row["events"] = [
                    {"cursor": event.sequence, "type": event.type.lower(),
                     "timestamp": event.timestamp_millis}
                    for event in ledger.events(
                        run_id, after_sequence=max(0, sequence - event_limit), limit=event_limit,
                    )
                ]
                runs[run_id] = row
                changed = True
            last = page[-1]
            before = (last["updated_at_millis"], last["run_id"])
            remaining -= len(page)
    return changed
