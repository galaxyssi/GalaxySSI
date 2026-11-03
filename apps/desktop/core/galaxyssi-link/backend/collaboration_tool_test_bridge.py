"""Explicit App-owned saved-tool execution, separate from read-only recall."""
import json
import re

from collaboration_recall_bridge import RecallBroker, task_scope
from collaboration_transport_feedback import PublicationRejected, ResponseUnconfirmed

TOOL = "collaboration_test_tool"
RUN_TOOL = "collaboration_run_tool"
RUN_RECORDS = {"tool_release", "capability_channel"}
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
        "First publish workspace.kind=executable_tool with body.executable_tool, then kind=tool_test_plan with body.tool_test_plan; "
        "generic artifact or experiment_plan records are not executable registrations. Copy the exact plan reference. "
        "Inspect record_validation for the precise rejected field, expected/actual values and exact reference; "
        "recall evolution_rules topic=tools for the full contract. Saved records are never automatically relabeled. "
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


def run_tool_spec():
    spec = tool_spec()
    spec["name"] = RUN_TOOL
    spec["description"] = (
        "Execute an exact independently released tool, or an exact selected capability_channel, on NEW parameters "
        "through the originating App's existing native Python runtime. Discover releases with collaboration_recall "
        "mode=capabilities and read original source, tests, review and applicability before choosing reuse. "
        "mode=start takes execution_id, exactly one tool_release or capability_channel reference, parameters object, and timeout_ms. "
        "Copy only object_id, integer revision and sha256 from the selected record. No source/code override or new test answers. "
        "The App rechecks current source/test/release lineage, input schema, runtime identity, active member and permissions. "
        "Network remains disabled. A release does not grant authority or certify arbitrary inputs. "
        "Returns queued, not completed. Use mode=status with the SAME execution_id; read the returned original evidence receipt "
        "for the output. execution_mode=run and passed=true mean valid native execution, not scientific or goal success. "
        "mode=cancel cancels only this invocation. Status/cancel accept only mode and execution_id. "
        "A timeout is uncertain: recover the SAME ID, never repeat effects by minting a new ID. "
        "Changing parameters, version or timeout under an existing ID is rejected. After App restart unfinished work is interrupted, "
        "not automatically reexecuted. Inspect original evidence before choosing recovery. "
        "Unavailable runtime is a setup issue; no installation or silent Desktop fallback occurs. "
        "The Linux runtime is not a security sandbox. Test new candidates with collaboration_test_tool instead.")
    properties = spec["inputSchema"]["properties"]
    reference = properties.pop("tool_test_plan")
    properties.update({key: reference for key in sorted(RUN_RECORDS)})
    properties["parameters"] = {"type": "object", "additionalProperties": True}
    return spec


def validate_arguments(arguments, *, tool=TOOL):
    if not isinstance(arguments, dict):
        raise ValueError("Saved tool arguments must be an object")
    if tool not in {TOOL, RUN_TOOL}:
        raise ValueError("Unknown saved tool operation")
    identifier = arguments.get("execution_id")
    if not isinstance(identifier, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", identifier) is None:
        raise ValueError("Use a stable ASCII execution_id, 1..128 characters")
    mode = arguments.get("mode")
    if mode == "start":
        selected = RUN_RECORDS.intersection(arguments) if tool == RUN_TOOL else {"tool_test_plan"}
        if len(selected) != 1:
            raise ValueError("Start requires exactly one tool_release or capability_channel")
        record = next(iter(selected))
        ref = arguments.get(record)
        timeout = arguments.get("timeout_ms")
        fields = {"mode", "execution_id", record, "timeout_ms"}
        if tool == RUN_TOOL:
            fields.add("parameters")
            if not isinstance(arguments.get("parameters"), dict):
                raise ValueError("Run parameters must be a JSON object")
            try:
                json.dumps(arguments["parameters"], allow_nan=False)
            except (TypeError, ValueError, RecursionError) as error:
                raise ValueError("Run parameters must contain finite JSON values") from error
        if (set(arguments) != fields
                or not isinstance(ref, dict) or set(ref) != {"object_id", "revision", "sha256"}
                or any(not isinstance(ref.get(key), str) or re.fullmatch(r"[a-f0-9]{64}", ref[key]) is None
                       for key in ("object_id", "sha256"))
                or type(ref.get("revision")) is not int or not 1 <= ref["revision"] <= 2147483647
                or type(timeout) is not int or not 100 <= timeout <= 1800000):
            raise ValueError("Start requires an exact saved record, operation-specific fields and integer timeout_ms in the native runtime range")
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
        operation = RUN_TOOL if isinstance(arguments, dict) and RUN_RECORDS.intersection(arguments) else TOOL
        arguments = validate_arguments(arguments, tool=operation)
        try:
            return self._exchange(task_scope(snapshot()), snapshot, arguments, publish, active, timeout, arguments["mode"])
        except (PublicationRejected, ResponseUnconfirmed) as error:
            raise type(error)(error.observation, guidance=(
                "Saved tool response unavailable. Query mode=status with the SAME execution_id; "
                "do not repeat execution or change its inputs. Transport failure does not establish execution failure.")) from error


broker = ToolTestBroker()
