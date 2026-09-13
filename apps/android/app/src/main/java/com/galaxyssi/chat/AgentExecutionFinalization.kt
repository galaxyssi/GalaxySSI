package com.galaxyssi.chat

internal fun finalizeAgentExecution(
    runtime: MobileNativeAgent,
    turnId: String,
    state: AgentUiState,
    recordAgentRunFromState: (String, AgentUiState) -> Unit
): AgentUiState {
    if (runtime.executionLoopSnapshot()?.phase == AgentExecutionLoopPhase.COMPLETED) {
        recordAgentRunFromState(turnId, state)
        return state
    }
    if (state.phase != AgentPhase.COMPLETED) {
        recordAgentRunFromState(turnId, state)
        return state
    }
    val loopPhase = runtime.executionLoopSnapshot()?.phase
    if (loopPhase !in setOf(
            AgentExecutionLoopPhase.FINALIZE,
            AgentExecutionLoopPhase.LEARN
        ) &&
        !runtime.beginExecutionFinalization()
    ) {
        return runtime.snapshot().also { recordAgentRunFromState(turnId, it) }
    }
    if (runtime.executionLoopSnapshot()?.phase != AgentExecutionLoopPhase.LEARN &&
        !runtime.beginExecutionLearning()
    ) {
        return runtime.snapshot().also { recordAgentRunFromState(turnId, it) }
    }
    return runCatching {
        recordAgentRunFromState(turnId, state)
        runtime.completeExecutionLoop()
        runtime.snapshot()
    }.getOrElse { failure ->
        runtime.failExecutionLoop(
            failure.message.orEmpty().ifBlank { "Task finalization failed" }
        )
        runtime.snapshot()
    }
}
