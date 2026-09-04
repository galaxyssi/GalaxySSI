from agent_connector_modes import (
    PHONE_SUPERVISED_PROJECT_PLAN,
    is_structured_connector_task_mode,
    normalize_connector_task_mode,
)


def test_phone_supervised_project_mode_is_normalized_and_recognized():
    assert normalize_connector_task_mode(" PHONE_SUPERVISED_PROJECT_PLAN_V1 ") == (
        PHONE_SUPERVISED_PROJECT_PLAN
    )
    assert is_structured_connector_task_mode(PHONE_SUPERVISED_PROJECT_PLAN)


def test_unknown_connector_mode_fails_closed_to_normal_processing():
    assert normalize_connector_task_mode("desktop_execute_everything") == ""
    assert not is_structured_connector_task_mode("desktop_execute_everything")
