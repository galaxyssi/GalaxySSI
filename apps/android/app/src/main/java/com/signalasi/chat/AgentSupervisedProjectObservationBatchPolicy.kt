package com.signalasi.chat

/**
 * Allows one model turn to collect several independent, read-only observations.
 * Mutations and long-running runtime work stay single-step so the model observes
 * their real outcome before deciding what to do next.
 */
internal object AgentSupervisedProjectObservationBatchPolicy {
    const val MAX_ACTIONS = 4

    fun accepts(actions: List<AgentAction>): Boolean {
        if (actions.size == 1) return true
        if (actions.size !in 2..MAX_ACTIONS) return false
        val identities = hashSetOf<String>()
        return actions.all { action ->
            action.isIndependentReadOnlyObservation() && identities.add(action.observationIdentity())
        }
    }

    private fun AgentAction.isIndependentReadOnlyObservation(): Boolean =
        kind == AgentActionKind.CALL_NATIVE_TOOL &&
            toolId() in BATCHABLE_TOOLS &&
            dependencyIds().isEmpty() &&
            outputSourceIds().isEmpty()

    private fun AgentAction.observationIdentity(): String =
        "${toolId()}\u0000${parameters["input_json"].orEmpty().trim()}"

    private fun AgentAction.toolId(): String =
        parameters["tool_id"].orEmpty().ifBlank { target }.trim()

    private val BATCHABLE_TOOLS = setOf(
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
