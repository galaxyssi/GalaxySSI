package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Uses the same host-bound publication contract as cloud and remote members. */
internal object CollaborationMilestoneNativeTool {
    const val ID = "galaxyssi.phone.collaboration.publish"

    fun definitions(context: Context): List<AgentNativeToolDefinition> = listOf(AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = ID, version = "1.0.0", title = context.getString(R.string.collaboration_publish_title),
            description = CollaborationMilestoneTool.DESCRIPTION,
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema(CollaborationMilestoneTool.schema().toNativeObject()),
            outputSchema = AgentNativeJsonSchema.objectSchema(additionalProperties = true),
            risk = AgentNativeToolRisk.LOW, capabilities = setOf("collaboration.publish"),
            timeoutMillis = 20_000, idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            effect = AgentNativeToolEffect.MUTATION),
        executor = AgentNativeToolExecutor { call ->
            val source = call.context.collaborationSourceMessageId
            val access = source?.let { CollaborationEvidenceLedger(context).binding(
                it, call.context.conversationId, call.context.turnId) }
                ?: return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "dispatch_unavailable", "Interim publication requires the exact host member binding.")
            if (CollaborationGroupStore(context).load(access.groupId)?.members?.none { it.id == access.personId } != false) {
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "dispatch_unavailable", "The member's group access was removed.")
            }
            val workspace = CollaborationResearchWorkspace(context)
            if (workspace.publicationCheckpoint(access)?.optJSONObject("receipt")?.optString("status") == "rejected") {
                return@AgentNativeToolExecutor AgentNativeToolExecutionResult.failure(
                    "publication_repair_only", "Correct the saved final draft or recall its originals; do not publish new work while repairing it.")
            }
            val result = JSONObject(CollaborationMilestoneTool.execute(context, access, JSONObject(call.input)))
            AgentNativeToolExecutionResult(output = result.toNativeObject(), error =
                if (result.optBoolean("success")) null else AgentNativeToolError("publication_rejected",
                    result.optString("reason").ifBlank { result.optString("error") }.ifBlank { "Interim publication was rejected." }))
        }
    ))
}
