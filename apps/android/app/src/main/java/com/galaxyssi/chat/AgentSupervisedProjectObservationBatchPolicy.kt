package com.galaxyssi.chat

/** Admits ordered tool graphs while checking every unordered pair for resource conflicts. */
internal object AgentSupervisedProjectObservationBatchPolicy {
    const val MAX_PARALLEL_ACTIONS = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY

    fun accepts(
        actions: List<AgentAction>,
        workspaceId: String = "",
        descriptorFor: (String) -> AgentNativeToolDescriptor? = { null }
    ): Boolean = rejectionReason(actions, workspaceId, descriptorFor) == null

    fun rejectionReason(
        actions: List<AgentAction>,
        workspaceId: String = "",
        descriptorFor: (String) -> AgentNativeToolDescriptor? = { null }
    ): String? {
        if (actions.size !in 1..MAX_PARALLEL_ACTIONS) return "batch_size"
        val ancestors = linkedMapOf<String, Set<String>>()
        for (action in actions) {
            if (action.id.isBlank() || action.id in ancestors) return "duplicate_or_blank_action_id"
            val dependencies = action.dependencyIds()
            if (dependencies.any { it !in ancestors }) return "missing_or_forward_dependency"
            if (actions.size > 1 && action.kind != AgentActionKind.CALL_NATIVE_TOOL) return "non_native_batch"
            if (action.kind == AgentActionKind.CALL_NATIVE_TOOL && action.outputSourceIds().isNotEmpty()) {
                return "native_output_handoff"
            }
            ancestors[action.id] = dependencies.flatMapTo(linkedSetOf()) { ancestors.getValue(it) + it }
            if (action.parameters[AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER] == "true" &&
                (action !== actions.last() || ancestors.getValue(action.id).size != actions.size - 1)) {
                return "terminal_before_dependencies"
            }
        }
        if (actions.size == 1) return null
        val descriptors = actions.associate { it.id to descriptorFor(it.toolId()) }
        if (actions.any { descriptors[it.id] == null && it.toolId() !in LEGACY_BATCHABLE_TOOLS }) {
            return "unknown_batch_tool"
        }
        val resourcePlans = actions.associate { action ->
            action.id to descriptors[action.id]?.let {
                AgentNativeToolResourcePolicy.resolveAction(it, action, workspaceId)
            }
        }
        // Comparing only adjacent layers misses a long-running sibling that overlaps a descendant.
        actions.forEachIndexed { index, action ->
            for (earlier in actions.take(index)) {
                if (earlier.id in ancestors.getValue(action.id)) continue
                if (earlier.observationIdentity() == action.observationIdentity()) return "duplicate_unordered_action"
                if (earlier.isReadOnlyObservation(descriptors[earlier.id]) &&
                    action.isReadOnlyObservation(descriptors[action.id])) continue
                val left = resourcePlans[earlier.id]
                val right = resourcePlans[action.id]
                if (left?.resourceScoped != true || right?.resourceScoped != true || left.conflictsWith(right)) {
                    return "unordered_resource_conflict"
                }
            }
        }
        return null
    }

    private fun AgentAction.isReadOnlyObservation(
        descriptor: AgentNativeToolDescriptor?
    ): Boolean {
        val toolId = toolId()
        val parallelReadOnly = descriptor?.concurrency == AgentNativeToolConcurrency.PARALLEL_READ_ONLY ||
            (descriptor == null && toolId in LEGACY_BATCHABLE_TOOLS)
        return kind == AgentActionKind.CALL_NATIVE_TOOL && parallelReadOnly
    }

    private fun AgentAction.observationIdentity(): String =
        "${toolId()}\u0000${parameters["input_json"].orEmpty().trim()}"

    private fun AgentAction.toolId(): String =
        parameters["tool_id"].orEmpty().ifBlank { target }.trim()

    private val LEGACY_BATCHABLE_TOOLS = setOf(
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
