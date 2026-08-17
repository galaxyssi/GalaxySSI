from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

from desktop_agent_adapters import AgentAdapterRequest
from agent_gateway import AgentSpec, _execute_agent_adapter_request
from response_self_check import (
    ResponseSelfCheckStatus,
    evaluate_response,
    response_repair_prompt,
    response_self_check_contract,
)


def test_substantive_answer_to_actionable_request_passes():
    result = evaluate_response(
        "Summarize the release report",
        "The report identifies three launch risks and recommends delaying rollout by one day.",
    )

    assert result.accepted is True
    assert result.status == ResponseSelfCheckStatus.PASSED


def test_actionable_request_rejects_acknowledgement_only_draft():
    result = evaluate_response(
        "Build and verify the Android app",
        "Got it. I will handle this now.",
    )

    assert result.status == ResponseSelfCheckStatus.REPAIR
    assert result.reasons == ("acknowledgement_only",)


def test_available_attachment_cannot_be_reported_as_missing():
    result = evaluate_response(
        "Review this worksheet",
        "I cannot see any attachment. Please upload the file.",
        attachment_names=["quarterly.xlsx"],
    )

    assert result.status == ResponseSelfCheckStatus.REPAIR
    assert "available_attachment_ignored" in result.reasons


def test_attachment_without_a_task_can_receive_one_clarifying_question():
    result = evaluate_response(
        "Attached files",
        "What would you like me to do with quarterly.xlsx?",
        attachment_names=["quarterly.xlsx"],
    )

    assert result.accepted is True


def test_specific_task_cannot_be_replaced_by_a_request_for_the_task():
    result = evaluate_response(
        "Translate the document into English",
        "What would you like me to do?",
        attachment_names=["brief.docx"],
    )

    assert result.status == ResponseSelfCheckStatus.REPAIR
    assert "latest_request_ignored" in result.reasons


def test_verified_output_artifact_allows_a_short_completion_message():
    result = evaluate_response(
        "Create a ZIP archive",
        "Done.",
        output_artifacts=["project.zip"],
    )

    assert result.accepted is True


def test_rich_artifact_can_be_the_entire_response():
    result = evaluate_response(
        "Create and return the annotated image",
        "",
        output_artifacts=["annotated.jpg"],
    )

    assert result.accepted is True


def test_chinese_acknowledgement_only_draft_requests_repair():
    result = evaluate_response(
        "\u5206\u6790\u8fd9\u4efd\u62a5\u544a",
        "\u6536\u5230\uff0c\u6211\u4f1a\u9a6c\u4e0a\u5904\u7406\u3002",
    )

    assert result.status == ResponseSelfCheckStatus.REPAIR
    assert result.reasons == ("acknowledgement_only",)


def test_greeting_cannot_receive_a_future_only_acknowledgement():
    result = evaluate_response("hello", "Got it. I will handle this now.")

    assert result.status == ResponseSelfCheckStatus.REPAIR
    assert result.reasons == ("acknowledgement_only",)


def test_user_acknowledgement_can_receive_a_short_acknowledgement():
    result = evaluate_response("thank you", "Okay")

    assert result.accepted is True


def test_response_identity_must_match_the_bound_turn():
    result = evaluate_response(
        "Explain the error",
        "The error is caused by an expired token.",
        expected_identity={"task_id": "task-1", "turn_id": "turn-2"},
        response_identity={"task_id": "task-1", "turn_id": "turn-1"},
    )

    assert result.status == ResponseSelfCheckStatus.REJECTED
    assert result.reasons == ("identity_mismatch",)


def test_contract_and_repair_prompt_are_bounded_and_request_specific():
    result = evaluate_response("Run the tests", "Working on it")
    contract = response_self_check_contract("Run the tests", ["report.txt"])
    repair = response_repair_prompt(
        "Run the tests",
        "Working on it",
        result,
        ["report.txt"],
    )

    assert result.request_digest in contract
    assert result.request_digest in repair
    assert "report.txt" in contract
    assert "acknowledgement_only" in repair


def test_common_agent_adapter_repairs_acknowledgement_before_returning():
    spec = AgentSpec(
        id="hermes",
        name="Hermes Agent",
        kind="local-cli",
        command=["hermes"],
        timeout=10,
    )
    drafts = iter([
        "Got it. I will handle this now.",
        "The report contains three launch risks and one blocking dependency.",
    ])
    prompts: list[str] = []

    def ask(*_args, **kwargs):
        prompts.append(str(_args[1] if len(_args) > 1 else kwargs.get("prompt") or ""))
        return next(drafts)

    with patch("agent_gateway.all_agent_specs", return_value={"hermes": spec}), patch(
        "agent_gateway._ask_agent_sync_inner",
        side_effect=ask,
    ), patch(
        "acp_runtime.acp_runtime",
        return_value=SimpleNamespace(execute=lambda *_args, **_kwargs: None),
    ):
        reply = _execute_agent_adapter_request(
            "hermes",
            AgentAdapterRequest(
                agent_id="hermes",
                prompt="Analyze the release report",
                checkpoint={"execution_prompt": "Analyze the release report"},
            ),
        )

    assert reply.startswith("The report contains")
    assert len(prompts) == 2
    assert "Repair the final answer" in prompts[1]


def test_structured_phone_planner_returns_raw_json_without_generic_contracts():
    spec = AgentSpec(
        id="hermes",
        name="Hermes Agent",
        kind="local-cli",
        command=["hermes"],
        timeout=10,
    )
    raw_plan = '{"summary":"Inspect the phone workspace","actions":[]}'
    prompts: list[str] = []

    def ask(*args, **kwargs):
        prompts.append(str(args[1] if len(args) > 1 else kwargs.get("prompt") or ""))
        return raw_plan

    with patch("agent_gateway.all_agent_specs", return_value={"hermes": spec}), patch(
        "agent_gateway._ask_agent_sync_inner",
        side_effect=ask,
    ):
        reply = _execute_agent_adapter_request(
            "hermes",
            AgentAdapterRequest(
                agent_id="hermes",
                prompt="Return exactly one JSON ActionPlan",
                checkpoint={
                    "execution_prompt": "Plan a phone-local project task",
                    "execution_policy": {"execution_mode": "plan_only"},
                    "connector_task_mode": "phone_supervised_project_plan_v1",
                },
            ),
        )

    assert reply == raw_plan
    assert len(prompts) == 1
    assert "SignalASI execution contract:" not in prompts[0]
    assert "SignalASI final response self-check:" not in prompts[0]
