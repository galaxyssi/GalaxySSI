package com.galaxyssi.chat

import android.content.Context

/** Host-only metadata, separate from executor output and model-authored tool arguments. */
data class AgentNativeToolObservation(
    val receipt: AgentNativeJsonObject? = null,
    val recording: AgentNativeJsonObject? = null
) {
    companion object {
        fun notDurable(reason: String) = AgentNativeToolObservation(recording = mapOf(
            "status" to "not_durable", "reason" to reason,
            "tool_output_preserved" to true, "do_not_reexecute" to true
        ))
    }
}

fun interface AgentNativeToolObservationRecorder {
    fun record(input: AgentNativeJsonObject, context: AgentNativeToolInvocationContext,
               result: AgentNativeToolResult): AgentNativeToolObservation?
}

internal class CollaborationNativeEvidence(
    private val ledgerProvider: () -> CollaborationEvidenceLedger
) : AgentNativeToolObservationRecorder {
    constructor(context: Context) : this({ CollaborationEvidenceLedger(context.applicationContext) })

    override fun record(input: AgentNativeJsonObject, context: AgentNativeToolInvocationContext,
                        result: AgentNativeToolResult): AgentNativeToolObservation? {
        val source = context.collaborationSourceMessageId ?: return null
        val ledger = ledgerProvider()
        val access = ledger.binding(source, context.conversationId, context.turnId)
            ?: return AgentNativeToolObservation.notDurable("dispatch_binding_unavailable")
        val original = result.copy(collaborationObservation = null).toJson()
        // A replay is a new observation of an existing outcome, not a new execution of its effect.
        val observationId = "native:${result.receipt.invocationId}:${AgentNativeJsonCodec.sha256(original)}"
        val receipt = ledger.record(access, observationId, result.provenance.toolId,
            AgentNativeJsonCodec.stringify(input), original, result.receipt.startedAtEpochMillis,
            maxOf(result.receipt.startedAtEpochMillis, result.receipt.finishedAtEpochMillis),
            origin = CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        return AgentNativeToolObservation(receipt = receipt.toNativeObject())
    }
}
