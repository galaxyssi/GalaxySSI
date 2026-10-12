package com.galaxyssi.chat

import android.content.Context

internal fun Context.modelToolTimelineText(
    projection: AgentModelToolTimelineProjection,
    round: Int,
    toolTitle: String
): String? = when (projection.text) {
    AgentModelToolTimelineText.MODEL_REASONING -> getString(R.string.agent_model_loop_reasoning_format, round)
    AgentModelToolTimelineText.MODEL_SELECTED_TOOLS -> getString(R.string.agent_model_loop_selected_tools_format, projection.count)
    AgentModelToolTimelineText.MODEL_PREPARED_STEP -> getString(R.string.agent_model_loop_prepared_step)
    AgentModelToolTimelineText.TOOL_RUNNING -> getString(R.string.agent_loop_action_format, toolTitle)
    AgentModelToolTimelineText.TOOL_PROGRESS -> if (projection.detail.isBlank()) {
        getString(R.string.agent_loop_action_format, toolTitle)
    } else getString(R.string.agent_model_loop_tool_progress_format, toolTitle, projection.detail)
    AgentModelToolTimelineText.TOOL_SUCCEEDED -> getString(R.string.agent_loop_observation_format, toolTitle)
    AgentModelToolTimelineText.TOOL_FAILED -> getString(R.string.agent_loop_observation_failed_format,
        toolTitle, projection.detail.ifBlank { getString(R.string.agent_model_loop_unknown_failure) })
    AgentModelToolTimelineText.TOOL_RETRYING -> getString(R.string.agent_model_loop_retrying_format, toolTitle)
    AgentModelToolTimelineText.TOOL_WAITING -> getString(R.string.agent_model_loop_waiting_format, toolTitle)
    AgentModelToolTimelineText.MODEL_LOOP_STOPPED -> getString(R.string.agent_model_loop_stopped_format,
        projection.detail.ifBlank { getString(R.string.agent_model_loop_unknown_failure) })
    null -> null
}
