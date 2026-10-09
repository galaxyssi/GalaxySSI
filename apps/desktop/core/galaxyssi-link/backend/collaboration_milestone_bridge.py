"""Explicit interim-publication capability, separate from read-only collaboration recall."""
import hashlib
import json
import re

from collaboration_recall_bridge import RecallBroker, task_scope
from collaboration_transport_feedback import PublicationRejected, ResponseUnconfirmed

TOOL = "collaboration_publish"
REQUEST = "collaboration_publish_request"
RESPONSE = "collaboration_publish_result"
CONTRACT = "galaxyssi.collaboration-publish/1"
MAX_BYTES = 128 * 1024
COORDINATION_INSTRUCTIONS = (
    'Optional coordination:{"mode":"record_only"} saves evidence without waking the coordinator. '
    'Use coordination:{"mode":"request","decision":"specific pending decision",'
    '"why_now":"why peer input can change the next action"} for useful team intervention, not every saved file. '
    'Continue independent work; neither mode pauses your assignment or requires approval for each action. '
    'Omitting coordination retains the existing notification behavior. ')


def tool_spec():
    return {"type": "function", "name": TOOL, "description": (
        "Publish useful interim research artifacts to your originating phone without ending your assignment. "
        "Only host-enrolled research assignments can publish; coordination/assessment dispatches return their required response instead. "
        "Use mode=status when availability is unknown; it reports the current assignment without mutation. "
        "An unavailable capability is not invalid artifact JSON and cannot be repaired by retrying publication. "
        "mode=publish requires stable milestone_id and artifact (a JSON string using galaxyssi.research-artifact.v1 "
        "with versioned workspace evidence). Include format, nonblank summary and workspace; empty top-level candidates/findings "
        "may be omitted and decode as []. Supplied arrays and typed workspace bodies remain validated; defaults do not supply evidence. "
        + COORDINATION_INSTRUCTIONS +
        "Put coordination inside the artifact JSON. An explicit request may include milestones:[your saved IDs] "
        "to share exact originals without copying them, even with an empty workspace array. "
        "Retry the identical ID and artifact after an uncertain response; accepted IDs are immutable. "
        "For a substantive revision use a new milestone ID and exact object_id/base_revision. "
        "mode=list with optional cursor recovers this assignment's committed IDs; follow next_cursor. "
        "mode=receipt with milestone_id and artifact_sha256 (SHA-256 of the exact artifact UTF-8 string, not the journal raw_sha256) reads its original receipt without republishing. "
        "Only explicit not_recorded permits resending the saved artifact; a failed lookup leaves the outcome uncertain. "
        "Final research-artifact output may use milestones:[saved IDs] instead of recreating already published objects. "
        "This records authorship, not verification, peer consumption or task completion. "
        "For an actual local UTF-8 file, use collaboration_text_artifact when available instead of publishing only its path or a description. "
        "Specialized host candidate-transition assignments use their final publication contract. "
        "One request is limited to 131072 UTF-8 bytes. Split larger independent deliveries, never truncate evidence. "
        "Do not supply group/member/task authority fields."),
        "inputSchema": {"type": "object", "properties": {
            "mode": {"type": "string", "enum": ["publish", "list", "status", "receipt"]},
            "milestone_id": {"type": "string", "maxLength": 160},
            "artifact": {"type": "string"},
            "artifact_sha256": {"type": "string", "pattern": "^[a-f0-9]{64}$"},
            "cursor": {"type": "string", "maxLength": 512}},
            "required": ["mode"], "additionalProperties": False}}


def validate_arguments(arguments):
    if not isinstance(arguments, dict):
        raise ValueError("Publication arguments must be an object")
    if arguments.get("mode") == "status":
        if set(arguments) != {"mode"}:
            raise ValueError("Status accepts only mode; authority comes from the host assignment")
    elif arguments.get("mode") == "publish":
        identifier, artifact = arguments.get("milestone_id"), arguments.get("artifact")
        if (set(arguments) != {"mode", "milestone_id", "artifact"}
                or not isinstance(identifier, str) or not 1 <= len(identifier.encode("utf-16-le")) // 2 <= 160
                or identifier != identifier.strip() or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in identifier)
                or not isinstance(artifact, str) or not artifact.strip()):
            raise ValueError("Publish requires only mode, stable milestone_id and nonblank artifact string")
    elif arguments.get("mode") == "receipt":
        if (set(arguments) != {"mode", "milestone_id", "artifact_sha256"}
                or not isinstance(arguments.get("artifact_sha256"), str)
                or re.fullmatch(r"[a-f0-9]{64}", arguments["artifact_sha256"]) is None):
            raise ValueError("Receipt requires only mode, milestone_id and lowercase artifact_sha256")
        validate_arguments({"mode": "publish", "milestone_id": arguments.get("milestone_id"), "artifact": "{}"})
    elif arguments.get("mode") == "list":
        if (set(arguments) - {"mode", "cursor"} or not isinstance(arguments.get("cursor", ""), str)
                or len(arguments.get("cursor", "")) > 512):
            raise ValueError("List accepts only mode and an optional cursor")
    else:
        raise ValueError("Publication mode must be publish, list, status or receipt")
    if len(json.dumps(arguments, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")) > MAX_BYTES:
        raise ValueError("Publication exceeds 131072 UTF-8 bytes; split independent artifacts, do not truncate")
    return dict(arguments)


def publish_snapshot(request, publish, active, *, recover):
    """Recover only the exact saved publication; unavailable is never treated as absent."""
    if not active():
        raise ValueError("Artifact assignment changed before publication")
    if recover:
        query = validate_arguments({"mode": "receipt", "milestone_id": request["milestone_id"],
                                    "artifact_sha256": hashlib.sha256(request["artifact"].encode("utf-8")).hexdigest()})
        result = publish(query)
        if not active():
            raise ValueError("Artifact assignment changed during receipt recovery")
        if not isinstance(result, dict):
            raise ValueError("Invalid publication receipt response; original outcome remains uncertain")
        if result.get("success") is not True:
            return result
        if any(result.get(key) != query[key] for key in ("milestone_id", "artifact_sha256")):
            raise ValueError("Publication receipt identity changed; original outcome remains uncertain")
        if result.get("status") == "recorded":
            return result
        if result.get("status") != "not_recorded":
            raise ValueError("Publication receipt outcome is uncertain; retry the exact lookup")
    if not active():
        raise ValueError("Artifact assignment changed before publication")
    result = publish(request)
    if not active():
        raise ValueError("Artifact assignment changed during publication")
    return result


class MilestoneBroker(RecallBroker):
    def __init__(self):
        super().__init__(request_type=REQUEST, response_type=RESPONSE, contract=CONTRACT)

    def query(self, snapshot, arguments, publish, *, active=lambda: True, timeout=20.0):
        arguments = validate_arguments(arguments)
        # The durable phone milestone ID owns idempotency across transport nonces and restarts.
        try:
            return self._exchange(task_scope(snapshot()), snapshot, arguments, publish, active, timeout, arguments["mode"])
        except (PublicationRejected, ResponseUnconfirmed) as error:
            raise type(error)(error.observation, guidance=failure_guidance(arguments["mode"])) from error
        except (TimeoutError, ConnectionError) as error:
            raise type(error)(failure_guidance(arguments["mode"])) from error


def failure_guidance(mode):
    if mode == "receipt":
        return ("Saved publication receipt unavailable; this read submitted no artifact. Retry the exact receipt lookup after reconnecting. "
                "The original publication outcome remains uncertain; do not repeat completed effects.")
    if mode == "status":
        return ("Publication capability status unavailable; no artifact was submitted. "
                "Continue the required assignment response; a transport failure does not grant publication.")
    if mode == "list":
        return ("Saved milestone list unavailable; this read submitted no artifact. Retry listing after reconnecting. "
                "Do not infer that an earlier publication failed or repeat completed effects.")
    return ("Publication response unavailable; outcome is uncertain. Retry the SAME milestone_id and artifact "
            "or list saved milestones after reconnecting. Do not repeat completed effects.")


broker = MilestoneBroker()
