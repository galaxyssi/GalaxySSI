"""Explicit App-owned saved-tool testing, not a read-only recall operation."""
import re

from collaboration_recall_bridge import RecallBroker, task_scope
from collaboration_transport_feedback import PublicationRejected, ResponseUnconfirmed

TOOL = "collaboration_test_tool"
REQUEST = "collaboration_tool_test_request"
RESPONSE = "collaboration_tool_test_result"
CONTRACT = "galaxyssi.collaboration-tool-test/1"


def tool_spec():
    reference = {"type": "object", "properties": {
        "object_id": {"type": "string", "pattern": "^[a-f0-9]{64}$"},
        "revision": {"type": "integer", "minimum": 1, "maximum": 2147483647},
        "sha256": {"type": "string", "pattern": "^[a-f0-9]{64}$"}},
        "required": ["object_id", "revision", "sha256"], "additionalProperties": False}
    return {"type": "function", "name": TOOL, "description": (
        "Run an exact saved tool_test_plan through the originating App's existing native Python runtime. "
        "First publish executable_tool and tool_test_plan; copy the exact plan reference. "
        "mode=start requires a stable execution_id, tool_test_plan and timeout_ms (100..1800000, the native per-process range). "
        "Returns queued, not passed. Use mode=status with the SAME execution_id to recover progress and the original evidence receipt; "
        "read its full evidence with collaboration_recall before diagnosing, repairing or comparing. "
        "Finished means the invocation ended, not that tests passed; inspect passed and native_status. "
        "mode=cancel requests cancellation of this execution only, not the member or research goal. "
        "A transport timeout is an uncertain outcome: query the SAME ID; do not mint another ID or repeat effects. "
        "App restart marks unfinished outcomes interrupted, never silently reruns them. "
        "Unavailable runtime is a setup issue, not invalid tool code. This tool does not install an environment or switch to Desktop execution. "
        "No arbitrary source, command, network grant, group/member authority or answer override is accepted. "
        "The existing Linux runtime is not a security sandbox; saved candidate code keeps the existing native execution policy. "
        "Tests are disclosed functional checks, not proof of general correctness or scientific novelty."),
        "inputSchema": {"type": "object", "properties": {
            "mode": {"type": "string", "enum": ["start", "status", "cancel"]},
            "execution_id": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"},
            "tool_test_plan": reference,
            "timeout_ms": {"type": "integer", "minimum": 100, "maximum": 1800000}},
            "required": ["mode", "execution_id"], "additionalProperties": False}}


def validate_arguments(arguments):
    if not isinstance(arguments, dict):
        raise ValueError("Saved test arguments must be an object")
    identifier = arguments.get("execution_id")
    if not isinstance(identifier, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", identifier) is None:
        raise ValueError("Use a stable ASCII execution_id, 1..128 characters")
    mode = arguments.get("mode")
    if mode == "start":
        ref = arguments.get("tool_test_plan")
        timeout = arguments.get("timeout_ms")
        if (set(arguments) != {"mode", "execution_id", "tool_test_plan", "timeout_ms"}
                or not isinstance(ref, dict) or set(ref) != {"object_id", "revision", "sha256"}
                or any(not isinstance(ref.get(key), str) or re.fullmatch(r"[a-f0-9]{64}", ref[key]) is None
                       for key in ("object_id", "sha256"))
                or type(ref.get("revision")) is not int or not 1 <= ref["revision"] <= 2147483647
                or type(timeout) is not int or not 100 <= timeout <= 1800000):
            raise ValueError("Start requires only exact tool_test_plan and integer timeout_ms in the native runtime range")
    elif mode in {"status", "cancel"}:
        if set(arguments) != {"mode", "execution_id"}:
            raise ValueError("Status/cancel accepts only execution_id")
    else:
        raise ValueError("Mode must be start, status or cancel")
    return dict(arguments)


class ToolTestBroker(RecallBroker):
    def __init__(self):
        super().__init__(request_type=REQUEST, response_type=RESPONSE, contract=CONTRACT)

    def query(self, snapshot, arguments, publish, *, active=lambda: True, timeout=20.0):
        arguments = validate_arguments(arguments)
        try:
            return self._exchange(task_scope(snapshot()), snapshot, arguments, publish, active, timeout, arguments["mode"])
        except (PublicationRejected, ResponseUnconfirmed) as error:
            raise type(error)(error.observation, guidance=(
                "Saved test response unavailable. Query mode=status with the SAME execution_id; "
                "do not repeat the test or change its code. Transport failure does not establish execution failure.")) from error


broker = ToolTestBroker()
