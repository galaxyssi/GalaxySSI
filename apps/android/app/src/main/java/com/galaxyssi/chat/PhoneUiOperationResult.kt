package com.galaxyssi.chat

/** Acceptance is transport/UI evidence, not proof of the requested business outcome. */
internal object PhoneUiOperationResult {
    fun from(output: AgentNativeJsonObject, code: String, message: String): AgentNativeToolExecutionResult =
        if (output["accepted"] == true) AgentNativeToolExecutionResult.success(
            output + mapOf("business_success_verified" to false)
        ) else AgentNativeToolExecutionResult.failure(code, message,
            details = output + mapOf("observation_required" to true, "goal_terminal" to false))

    fun stale(windowId: Int, revision: String) = AgentNativeToolExecutionResult.failure(
        "ui_observation_stale", "The page changed. Inspect the current page before choosing the next action.",
        details = mapOf("current_window_id" to windowId, "current_revision" to revision,
            "executed" to false, "observation_required" to true, "goal_terminal" to false)
    )
}
