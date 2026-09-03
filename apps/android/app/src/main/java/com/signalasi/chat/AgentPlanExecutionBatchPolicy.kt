package com.signalasi.chat

internal data class AgentPlanExecutionBatch(
    val actions: List<AgentAction>,
    val parallelReadOnly: Boolean
)

/** Selects one dependency layer without speculating about tool side effects. */
internal object AgentPlanExecutionBatchPolicy {
    fun select(
        plan: AgentPlan,
        maxParallelReads: Int = AgentAdaptiveConcurrencyRuntime.currentLimit(
            AgentConcurrencyWorkload.NATIVE_READ_IO
        ),
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): AgentPlanExecutionBatch {
        val batchLimit = maxParallelReads.coerceIn(
            AgentAdaptiveConcurrencyPolicy.MIN_CONCURRENCY,
            AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY
        )
        val runnable = plan.runnableActions()
        val first = runnable.firstOrNull()
            ?: return AgentPlanExecutionBatch(emptyList(), parallelReadOnly = false)
        if (!first.isParallelReadOnly(descriptorFor)) {
            return AgentPlanExecutionBatch(listOf(first), parallelReadOnly = false)
        }

        val identities = linkedSetOf<String>()
        val selected = mutableListOf<AgentAction>()
        for (action in runnable) {
            if (selected.size >= batchLimit || !action.isParallelReadOnly(descriptorFor)) break
            if (!identities.add(action.observationIdentity())) break
            selected += action
        }
        return AgentPlanExecutionBatch(
            actions = selected,
            parallelReadOnly = selected.size > 1
        )
    }

    private fun AgentAction.isParallelReadOnly(
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): Boolean {
        if (kind != AgentActionKind.CALL_NATIVE_TOOL) return false
        val descriptor = descriptorFor(toolId()) ?: return false
        return descriptor.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY &&
            descriptor.risk == AgentNativeToolRisk.LOW &&
            descriptor.idempotency == AgentNativeToolIdempotency.IDEMPOTENT
    }

    private fun AgentAction.toolId(): String =
        parameters["tool_id"].orEmpty().ifBlank { target }.trim()

    private fun AgentAction.observationIdentity(): String =
        "${toolId()}\u0000${parameters["input_json"].orEmpty().trim()}"
}

internal fun AgentPlan.runnableActions(): List<AgentAction> {
    val known = (actionHistory + actions).associateBy { it.id }
    return actions.filter { action ->
        action.status in setOf(AgentActionStatus.PENDING_CONFIRMATION, AgentActionStatus.PROPOSED) &&
            action.dependencyIds().all { dependencyId ->
                known[dependencyId]?.status == AgentActionStatus.COMPLETED
            }
    }
}
