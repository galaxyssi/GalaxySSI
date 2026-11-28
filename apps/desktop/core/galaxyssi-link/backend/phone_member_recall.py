"""Local eligibility hints are not grants. Only the originating phone authorizes a read."""
from dataclasses import dataclass
import re

from agent_execution_harness import COLLABORATION_WORKSPACE_RESULT
from agent_task_recovery_query import TASK_FIELDS
from collaboration_recall_bridge import task_scope
from mqtt_delivery_envelope import receipt_binding


OPTION = "scoped_member_recall_v1"
MARKER = "member_recall_candidate_v1"


def candidate(payload, *, agent_id, wire):
    team, member = payload.get("team_id"), payload.get("agent_instance_id")
    follow_up = payload.get("agent_team_message", False)
    # Android emits boolean true and accepts case-insensitive "true" in actions.
    # Only absent or an explicit false can describe an original assignment.
    original = follow_up is False or isinstance(follow_up, str) and follow_up.lower() == "false"
    if (payload.get(OPTION) is not True or agent_id != "codex" or wire.get("scheme") != "signal"
            or not original
            or not wire.get("_client_route_id") or wire["_client_route_id"] != payload.get("client_route_id")
            or payload.get("result_contract") != COLLABORATION_WORKSPACE_RESULT
            or payload.get("connector_task_mode") or payload.get("request_kind")
            or payload.get("execution_mode") == "plan_only"
            or payload.get("_backend_conversation_id") or payload.get("_recovered_task")
            or not isinstance(team, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", team)
            or not isinstance(member, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,95}", member)):
        return None
    return {"team": team, "member": member, "original_assignment": True}


@dataclass(frozen=True)
class MemberBinding:
    scope: tuple
    conversation: str
    team: str
    member: str
    peer: str
    transport: str


def scope_snapshot(task):
    """Do not project task prompts, results, events or timeline for a membership check."""
    if task is None:
        return None
    return {key: getattr(task, key, None) for key in (*TASK_FIELDS, "execution_generation", "status",
                                                       "cancel_requested", "pause_requested", "delegate_agent_id")}


def current_binding(task, conversation, get_peer):
    if (task is None or not conversation.startswith("client:") or conversation != task.conversation_id
            or getattr(task, "storage_fenced", False) or getattr(task, "worker_execution_location", {})):
        return None
    request = getattr(task, "request_snapshot", {})
    marker, options = request.get(MARKER), request.get("options")
    if (not isinstance(marker, dict) or marker.get("original_assignment") is not True
            or not marker.get("member") or not marker.get("team")
            or not isinstance(options, dict) or options.get("agent_instance_id") != marker["member"]
            or options.get("result_contract") != COLLABORATION_WORKSPACE_RESULT
            or options.get("execution_mode") != "auto_complete"):
        return None
    try:
        snapshot = scope_snapshot(task)
        if (any(not isinstance(snapshot[key], str) or not snapshot[key].strip() for key in TASK_FIELDS)
                or type(snapshot["execution_generation"]) is not int or snapshot["delegate_agent_id"] not in (None, "", "codex")):
            return None
        scope = task_scope(snapshot)
    except ValueError:
        return None
    peer = get_peer(scope["client_route_id"])
    if (not peer or peer.get("revoked") or peer.get("revoked_at")
            or peer.get("client_route_id") != scope["client_route_id"]):
        return None
    fingerprint = str(peer.get("identity_fingerprint") or "").strip().lower()
    if not fingerprint or conversation != f"client:identity:{fingerprint}:{scope['conversation_id']}:agent-instance:{marker['member']}":
        return None
    try:
        transport = receipt_binding(scope["client_route_id"], peer.get("local_identity_fingerprint"),
                                    peer.get("identity_fingerprint"), peer.get("link_secret"))
    except ValueError:
        return None
    return MemberBinding(tuple(sorted(scope.items())), conversation, marker["team"], marker["member"], fingerprint, transport)
