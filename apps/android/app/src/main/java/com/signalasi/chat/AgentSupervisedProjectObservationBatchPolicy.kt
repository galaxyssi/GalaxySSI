package com.signalasi.chat

/** Allows one model turn to execute independent observations or workspace mutations. */
internal object AgentSupervisedProjectObservationBatchPolicy {
    const val MIN_MODEL_BATCH_ACTIONS = 3
    const val MAX_PARALLEL_ACTIONS = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY

    fun accepts(
        actions: List<AgentAction>,
        workspaceId: String = "",
        descriptorFor: (String) -> AgentNativeToolDescriptor? = { null }
    ): Boolean {
        if (actions.size == 1) return true
        if (actions.size !in 2..MAX_PARALLEL_ACTIONS) return false
        val identities = hashSetOf<String>()
        if (actions.all { action ->
            action.isIndependentReadOnlyObservation() && identities.add(action.observationIdentity())
        }) {
            return true
        }
        identities.clear()
        val resourcePlans = mutableListOf<AgentNativeResourceLockPlan>()
        return actions.all { action ->
            if (!action.isIndependentNativeAction() || !identities.add(action.observationIdentity())) {
                return@all false
            }
            val descriptor = descriptorFor(action.toolId()) ?: return@all false
            if (descriptor.concurrency != AgentNativeToolConcurrency.SERIAL) return@all false
            val resourcePlan = AgentNativeToolResourcePolicy.resolveAction(
                descriptor,
                action,
                workspaceId
            ) ?: return@all false
            if (!resourcePlan.resourceScoped || resourcePlans.any(resourcePlan::conflictsWith)) {
                return@all false
            }
            resourcePlans += resourcePlan
            true
        }
    }

    private fun AgentAction.isIndependentReadOnlyObservation(): Boolean =
        kind == AgentActionKind.CALL_NATIVE_TOOL &&
            toolId() in BATCHABLE_TOOLS &&
            dependencyIds().isEmpty() &&
            outputSourceIds().isEmpty()

    private fun AgentAction.isIndependentNativeAction(): Boolean =
        kind == AgentActionKind.CALL_NATIVE_TOOL &&
            dependencyIds().isEmpty() &&
            outputSourceIds().isEmpty()

    private fun AgentAction.observationIdentity(): String =
        "${toolId()}\u0000${parameters["input_json"].orEmpty().trim()}"

    private fun AgentAction.toolId(): String =
        parameters["tool_id"].orEmpty().ifBlank { target }.trim()

    private val BATCHABLE_TOOLS = setOf(
        AgentMobileProjectNativeTools.OBSERVE,
        AgentMobileProjectNativeTools.INSPECT,
        AgentMobileProjectNativeTools.DIFF,
        AgentMobileProjectNativeTools.LOG,
        AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
        AgentPhoneNativeToolCatalog.WORKSPACE_STAT,
        AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT_BATCH,
        AgentPhoneNativeToolCatalog.WORKSPACE_READ_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT_BATCH,
        AgentPhoneNativeToolCatalog.WORKSPACE_DIFF_SUMMARY,
        AgentPhoneNativeToolCatalog.WORKSPACE_SHA256
    )
}
