package com.galaxyssi.chat

/** Host-owned external events, never inferred from model text or page content. */
interface AgentModelToolEventWaitResolver {
    fun supports(toolId: String): Boolean
    fun resolve(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
        result: AgentNativeToolResult): AgentModelToolEventWait?

    /** Called only after a resolved observation is saved or validated in the original loop journal. */
    fun observationCommitted(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
        result: AgentNativeToolResult) = Unit
}

sealed class AgentModelToolEventWait {
    data class Pending(val eventId: String, val message: String) : AgentModelToolEventWait()
    data class Resolved(val result: AgentNativeToolResult) : AgentModelToolEventWait()
}

internal class AgentModelLoopEventWaitException(val eventId: String, message: String) :
    IllegalStateException(message)

internal fun MobileNativeAgent.waitForModelToolEvent(wait: AgentModelLoopEventWaitException): AgentUiState {
    if (phase in setOf(AgentPhase.CANCELLED, AgentPhase.FAILED) ||
        lastActionResult?.actionId == "agent-paused" || PhoneExecutionAuthority.isCancelled(sessionId)) return snapshot()
    check(pendingPlanning != null) { "An external wait requires its original planning checkpoint" }
    phase = AgentPhase.PAUSED
    lastActionResult = AgentActionResult("agent-event-wait", true, wait.message.orEmpty(),
        metadata = mapOf("model_loop_wait_event" to wait.eventId))
    if (executionLoop.snapshot?.phase?.isTerminal == false &&
        executionLoop.snapshot?.phase != AgentExecutionLoopPhase.PAUSED) {
        persistExecutionLoopEvent(executionLoop.pause(wait.message.orEmpty()))
    }
    persistSession()
    return snapshot()
}
