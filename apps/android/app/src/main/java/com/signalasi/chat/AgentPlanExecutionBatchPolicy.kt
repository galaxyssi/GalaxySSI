package com.signalasi.chat

internal enum class AgentPlanExecutionParallelMode {
    NONE,
    READ_ONLY,
    RESOURCE_SCOPED_MUTATION
}

internal data class AgentPlanExecutionBatch(
    val actions: List<AgentAction>,
    val parallelMode: AgentPlanExecutionParallelMode = AgentPlanExecutionParallelMode.NONE
) {
    val parallelReadOnly: Boolean
        get() = parallelMode == AgentPlanExecutionParallelMode.READ_ONLY
    val parallelResourceScoped: Boolean
        get() = parallelMode == AgentPlanExecutionParallelMode.RESOURCE_SCOPED_MUTATION
    val parallel: Boolean
        get() = parallelMode != AgentPlanExecutionParallelMode.NONE
}

/** Selects one dependency layer without speculating about tool side effects. */
internal object AgentPlanExecutionBatchPolicy {
    fun select(
        plan: AgentPlan,
        maxParallelReads: Int = AgentAdaptiveConcurrencyRuntime.currentLimit(
            AgentConcurrencyWorkload.NATIVE_READ_IO
        ),
        maxParallelMutations: Int = AgentAdaptiveConcurrencyRuntime.currentLimit(
            AgentConcurrencyWorkload.NATIVE_MUTATION
        ),
        workspaceId: String = "",
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): AgentPlanExecutionBatch {
        val runnable = plan.runnableActions()
        val first = runnable.firstOrNull()
            ?: return AgentPlanExecutionBatch(emptyList())
        return if (first.isParallelReadOnly(descriptorFor)) {
            selectReadOnly(runnable, maxParallelReads, descriptorFor)
        } else {
            selectResourceScopedMutations(
                runnable,
                maxParallelMutations,
                workspaceId,
                descriptorFor
            )
        }
    }

    private fun selectReadOnly(
        runnable: List<AgentAction>,
        requestedLimit: Int,
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): AgentPlanExecutionBatch {
        val batchLimit = requestedLimit.validLimit()
        val identities = linkedSetOf<String>()
        val selected = mutableListOf<AgentAction>()
        for (action in runnable) {
            if (selected.size >= batchLimit || !action.isParallelReadOnly(descriptorFor)) break
            if (!identities.add(action.observationIdentity())) break
            selected += action
        }
        return AgentPlanExecutionBatch(
            actions = selected,
            parallelMode = if (selected.size > 1) {
                AgentPlanExecutionParallelMode.READ_ONLY
            } else {
                AgentPlanExecutionParallelMode.NONE
            }
        )
    }

    private fun selectResourceScopedMutations(
        runnable: List<AgentAction>,
        requestedLimit: Int,
        workspaceId: String,
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): AgentPlanExecutionBatch {
        val selected = mutableListOf<AgentAction>()
        val resourcePlans = mutableListOf<AgentNativeResourceLockPlan>()
        val identities = linkedSetOf<String>()
        for (action in runnable) {
            if (selected.size >= requestedLimit.validLimit()) break
            val descriptor = action.serialNativeDescriptor(descriptorFor) ?: break
            val resourcePlan = AgentNativeToolResourcePolicy.resolveAction(
                descriptor,
                action,
                workspaceId
            ) ?: break
            if (!resourcePlan.resourceScoped) break
            if (!identities.add(action.observationIdentity())) continue
            if (resourcePlans.any(resourcePlan::conflictsWith)) continue
            selected += action
            resourcePlans += resourcePlan
        }
        val first = runnable.first()
        if (selected.isEmpty() || selected.first().id != first.id) {
            return AgentPlanExecutionBatch(listOf(first))
        }
        return AgentPlanExecutionBatch(
            actions = selected,
            parallelMode = if (selected.size > 1) {
                AgentPlanExecutionParallelMode.RESOURCE_SCOPED_MUTATION
            } else {
                AgentPlanExecutionParallelMode.NONE
            }
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

    private fun AgentAction.serialNativeDescriptor(
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): AgentNativeToolDescriptor? {
        if (kind != AgentActionKind.CALL_NATIVE_TOOL) return null
        return descriptorFor(toolId())?.takeIf {
            it.concurrency == AgentNativeToolConcurrency.SERIAL
        }
    }

    private fun Int.validLimit(): Int = coerceIn(
        AgentAdaptiveConcurrencyPolicy.MIN_CONCURRENCY,
        AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY
    )

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
