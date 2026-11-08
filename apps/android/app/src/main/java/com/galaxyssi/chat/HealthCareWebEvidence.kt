package com.galaxyssi.chat

import android.content.Context

/** Capture only native tool output; model-supplied hashes and snippets are not receipts. */
internal object HealthCareWebEvidence {
    fun wrap(definitions: List<AgentNativeToolDefinition>, observe: (AgentNativeToolInvocationContext, AgentNativeJsonObject) -> AgentNativeJsonObject) =
        definitions.map { definition ->
            if (definition.descriptor.id !in setOf(AgentWebIntelligenceNativeTools.SEARCH, AgentWebIntelligenceNativeTools.FETCH)) definition
            else AgentNativeToolDefinition(definition.descriptor, AgentNativeToolExecutor { call ->
                val result = definition.executor.execute(call)
                if (!result.isSuccess) result else {
                    call.checkpoint()
                    try { result.copy(output = observe(call.context, result.output)) }
                    catch (_: HealthCareConflict) { AgentNativeToolExecutionResult.failure("health_scope_changed",
                        "Health approval or source data changed during research. Review the concern before continuing.") }
                }
            }, definition.verifier, definition.validator, definition.executorId, definition.provenanceMetadata,
                definition.effectRecoveryProvider, definition.availabilityProvider)
        }

    fun observe(context: Context, invocation: AgentNativeToolInvocationContext, output: AgentNativeJsonObject): AgentNativeJsonObject {
        if (!HealthCareDiscussion.bound(context, invocation.conversationId)) return output
        if (HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        val receipts = HealthCareStore(context).use { store ->
            val grant = store.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            val values = HealthCareEvidencePolicy.read(output, grant, invocation.invocationId, System.currentTimeMillis())
            store.recordEvidence(values)
            values
        }
        return output + ("health_evidence" to receipts.map { it.output() })
    }
}
