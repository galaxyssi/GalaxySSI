package com.galaxyssi.chat

internal fun finalizeAgentExecution(
    runtime: MobileNativeAgent,
    turnId: String,
    state: AgentUiState,
    recordAgentRunFromState: (String, AgentUiState) -> Unit
): AgentUiState = synchronized(runtime) {
    // Foreground restoration must not replace the loop between FINALIZE and LEARN.
    if (runtime.phaseSnapshot() != state.phase) {
        return@synchronized runtime.snapshot().also { recordAgentRunFromState(turnId, it) }
    }
    if (runtime.executionLoopSnapshot()?.phase == AgentExecutionLoopPhase.COMPLETED) {
        recordAgentRunFromState(turnId, state)
        return@synchronized state
    }
    if (state.phase != AgentPhase.COMPLETED) {
        recordAgentRunFromState(turnId, state)
        return@synchronized state
    }
    val loopPhase = runtime.executionLoopSnapshot()?.phase
    if (loopPhase !in setOf(
            AgentExecutionLoopPhase.FINALIZE,
            AgentExecutionLoopPhase.LEARN
        ) &&
        !runtime.beginExecutionFinalization()
    ) {
        return@synchronized runtime.snapshot().also { recordAgentRunFromState(turnId, it) }
    }
    if (runtime.executionLoopSnapshot()?.phase != AgentExecutionLoopPhase.LEARN &&
        !runtime.beginExecutionLearning()
    ) {
        return@synchronized runtime.snapshot().also { recordAgentRunFromState(turnId, it) }
    }
    runCatching {
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
