package com.galaxyssi.chat

/** Process-wide adaptive admission and resource locking shared by every Agent runtime. */
internal object AgentNativeToolExecutionGate {
    private val readPermits = AgentAdaptiveBlockingPermitGate(
        limitProvider = {
            AgentAdaptiveConcurrencyRuntime.currentLimit(AgentConcurrencyWorkload.NATIVE_READ_IO)
        }
    )
    private val mutationPermits = AgentAdaptiveBlockingPermitGate(
        limitProvider = {
            AgentAdaptiveConcurrencyRuntime.currentLimit(AgentConcurrencyWorkload.NATIVE_MUTATION)
        }
    )

    fun <T> execute(
        descriptor: AgentNativeToolDescriptor,
        invocation: AgentNativeToolInvocation,
        block: () -> T
    ): T {
        val parallelRead = descriptor.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY
        val permits = if (parallelRead) readPermits else mutationPermits
        permits.acquire(invocation::checkpoint)
        val resourcePlan = AgentNativeToolResourcePolicy.resolve(
            descriptor = descriptor,
            input = invocation.input,
            fallbackWorkspaceId = invocation.context.attributes["workspace_id"].orEmpty()
                .ifBlank { invocation.context.conversationId }
                .ifBlank { invocation.context.sessionId }
                .ifBlank { invocation.context.turnId }
        )
        try {
            return AgentNativeToolResourceLockTable.execute(
                plan = resourcePlan,
                checkpoint = invocation::checkpoint,
                block = block
            )
        } finally {
            permits.release()
        }
    }
}
