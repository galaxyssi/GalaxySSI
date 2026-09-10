package com.galaxyssi.chat

internal fun MobileNativeAgent.executeAction(
    action: AgentAction,
    screen: ScreenContext,
    userConfirmed: Boolean = false,
    conversationIdOverride: String = "",
    turnIdOverride: String = ""
): AgentActionResult = runtimeTiming.measure(runtimeTimingTaskId(action, turnIdOverride), "action_dispatch",
    ::runtimeActionOutcome) {
    executeActionUntraced(action, screen, userConfirmed, conversationIdOverride, turnIdOverride)
}

internal fun MobileNativeAgent.captureVerificationScreen(
    action: AgentAction, beforeAction: ScreenContext, actionResult: AgentActionResult?
): AgentObservationOutcome = runtimeTiming.measure(runtimeTimingTaskId(action),
    if (action.kind.mayChangeScreen()) "screen_observe" else "receipt_observe", { observation ->
        when (observation.decision) {
            AgentObservationDecision.TIMED_OUT -> "timed_out"
            AgentObservationDecision.ACTION_FAILED -> "failed"
            else -> "completed"
        }
    }) { captureVerificationScreenUntraced(action, beforeAction, actionResult) }

internal fun MobileNativeAgent.applyObservationResult(
    action: AgentAction, result: AgentActionResult?, observation: AgentObservationOutcome
): AgentActionResult? = runtimeTiming.measure(runtimeTimingTaskId(action), "result_verify", ::runtimeActionOutcome) {
    applyObservationResultUntraced(action, result, observation)
}

private fun MobileNativeAgent.runtimeTimingTaskId(action: AgentAction, turnId: String = ""): String =
    action.parameters["_galaxyssi_task_id"].orEmpty()
        .ifBlank { turnId }.ifBlank { action.parameters[INTERNAL_TURN_ID].orEmpty() }
        .ifBlank { activeConversationTurnId }.ifBlank { currentPlan?.planId.orEmpty() }.ifBlank { sessionId }

private fun runtimeActionOutcome(result: AgentActionResult?): String = when {
    result?.success == true -> "completed"
    result?.metadata?.get("native_tool_status") == "cancelled" -> "cancelled"
    result?.metadata?.get("native_tool_status") == "timed_out" -> "timed_out"
    else -> "failed"
}
