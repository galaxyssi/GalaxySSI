package com.galaxyssi.chat

/** One dispatch owns one loop; replays, foreign identities and post-stop activity cannot advance it. */
internal class AgentLocalModelProgressFence(
    private val identity: AgentLocalDispatchIdentity,
    private val cancellation: AgentNativeToolCancellationToken,
    private val persist: (AgentModelToolLoopEvent) -> Unit
) : AgentModelToolLoopEventSink {
    private var loopId = ""
    private var sequence = -1L
    private var terminal = false

    @Synchronized
    override fun onEvent(event: AgentModelToolLoopEvent) {
        if (terminal || cancellation.isCancellationRequested ||
            event.sessionId != identity.taskId || event.taskId != identity.taskId || event.turnId != identity.turnId ||
            event.sequence <= sequence) return
        val observedLoop = event.details["model_loop_id"] as? String ?: return
        if (observedLoop.isBlank() || loopId.isNotBlank() && loopId != observedLoop) return
        persist(event)
        loopId = observedLoop
        sequence = event.sequence
        terminal = event.type in TERMINAL
    }

    private companion object {
        val TERMINAL = setOf(AgentModelToolLoopEventType.LOOP_COMPLETED,
            AgentModelToolLoopEventType.LOOP_CANCELLED, AgentModelToolLoopEventType.LOOP_FAILED,
            AgentModelToolLoopEventType.BUDGET_EXCEEDED, AgentModelToolLoopEventType.LOOP_DETECTED)
    }
}
