package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Bounded upgrade recovery. Original execution events and scientific acceptance remain unchanged. */
internal class CollaborationHistoricalDeliveryRecovery(context: Context) {
    private val progress = AgentEncryptedDatabase(context, "galaxyssi_collaboration_delivery_recovery_v1")
    private val finalizer = CollaborationResultFinalizer(context)
    private val lock = Any()

    fun recoverPage(store: AgentTeamExecutionStore, runId: String): Int = synchronized(lock) {
        val key = "recovery:${AgentNativeJsonCodec.sha256(runId)}"
        val saved = JSONObject(progress.readString(key, "{}"))
        if (saved.optBoolean("done")) return@synchronized 0
        val page = store.historicalDeliveryPage(runId, saved.optString("after"), 2)
        page.forEach { (cursor, checkpoint) ->
            recover(checkpoint, finalizer)
            progress.writeString(key, JSONObject().put("after", cursor).put("done", false).toString())
        }
        if (page.isEmpty()) progress.writeString(key, saved.put("done", true).toString())
        page.size
    }

    companion object {
        fun recover(checkpoint: AgentTeamExecutionCheckpoint, finalizer: CollaborationResultFinalizer): Int {
            var count = 0
            checkpoint.definition.members.forEach { member ->
                val result = checkpoint.completed[member.memberId] ?: return@forEach
                if (member.context["collaboration_group_id"].orEmpty().isBlank() ||
                    member.context["collaboration_group_id"] != checkpoint.request.conversationId ||
                    CollaborationResearchWorkflow.stage(member) in setOf(null, CollaborationResearchStage.DELIVER) ||
                    member.context[CollaborationCandidateEvolution.TASK] != null ||
                    result.status != AgentSubagentStatus.SUCCEEDED || result.outputTruncated ||
                    result.collaborationDelivery != null || result.provenance.source != "late-managed-response" ||
                    CollaborationResearchArtifact.decode(result.output) == null) return@forEach
                val owner = stableAgentTeamMemberRunId(checkpoint.request.runId, member.memberId)
                if (result.provenance.metadata["owner_run_id"] != owner) return@forEach
                val managed = AgentManagedResponseRecord(owner, checkpoint.request.runId, member.agentId,
                    member.deliveryMode, 0L, "", conversationId = checkpoint.request.conversationId)
                val execution = CollaborationLateResult.execution(checkpoint, managed) ?: return@forEach
                val delivery = finalizer.finish(execution, AgentSubagentOutput(result.output)).collaborationDelivery
                if (delivery?.status == "recorded") count++
            }
            return count
        }
    }
}
