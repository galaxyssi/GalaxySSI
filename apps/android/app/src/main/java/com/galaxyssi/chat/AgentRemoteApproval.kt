package com.galaxyssi.chat

import org.json.JSONObject

private val AGENT_REMOTE_APPROVAL_ID = Regex("[A-Za-z0-9._:-]{8,128}")
private val AGENT_REMOTE_APPROVAL_HASH = Regex("[0-9a-f]{64}")

data class AgentRemoteApprovalRequest(
    val taskId: String,
    val clientRouteId: String,
    val conversationId: String,
    val turnId: String,
    val contactId: String,
    val sourceMessageId: Long,
    val approvalId: String,
    val actionHash: String,
    val kind: String,
    val title: String,
    val detail: String,
    val target: String,
    val reason: String,
    val requestedAtMillis: Long,
    val expiresAtMillis: Long,
    val parametersJson: String
) {
    val dedupeKey: String
        get() = "remote-approval:$taskId:$approvalId"

    val compactActionHash: String
        get() = "${actionHash.take(8)}...${actionHash.takeLast(8)}"

    fun decision(choice: AgentPermissionChoice): AgentRemoteApprovalDecision =
        AgentRemoteApprovalDecision(
            taskId = taskId,
            clientRouteId = clientRouteId,
            conversationId = conversationId,
            turnId = turnId,
            contactId = contactId,
            sourceMessageId = sourceMessageId,
            approvalId = approvalId,
            actionHash = actionHash,
            choice = choice
        )

    companion object {
        fun fromTaskEvent(
            envelope: JSONObject?,
            nowMillis: Long = System.currentTimeMillis()
        ): AgentRemoteApprovalRequest? {
            if (envelope?.optString("type") != "agent_task_event" ||
                envelope.optString("task_status") != "waiting_approval"
            ) {
                return null
            }
            val approval = envelope.optJSONObject("approval_request") ?: return null
            val taskId = envelope.optString("task_id").trim().take(160)
            val clientRouteId = envelope.optString("client_route_id").trim().take(200)
            val conversationId = envelope.optString("conversation_id").trim().take(200)
            val turnId = envelope.optString("turn_id").trim().take(200)
            val contactId = envelope.optString("contact_id").trim().take(160)
            val sourceMessageId = envelope.optString("source_message_id").toLongOrNull()
                ?: envelope.optLong("source_message_id", 0L)
            val approvalId = approval.optString("approval_id").trim()
            val actionHash = approval.optString("action_hash").trim().lowercase()
            val requestedAt = approval.optLong("requested_at_ms", 0L)
            val expiresAt = approval.optLong("expires_at_ms", 0L)
            if (taskId.isBlank() ||
                clientRouteId.isBlank() ||
                conversationId.isBlank() ||
                turnId.isBlank() ||
                contactId.isBlank() ||
                sourceMessageId <= 0L ||
                !AGENT_REMOTE_APPROVAL_ID.matches(approvalId) ||
                !AGENT_REMOTE_APPROVAL_HASH.matches(actionHash) ||
                requestedAt <= 0L ||
                expiresAt <= nowMillis ||
                expiresAt <= requestedAt ||
                expiresAt - requestedAt > 24L * 60L * 60L * 1_000L
            ) {
                return null
            }
            return AgentRemoteApprovalRequest(
                taskId = taskId,
                clientRouteId = clientRouteId,
                conversationId = conversationId,
                turnId = turnId,
                contactId = contactId,
                sourceMessageId = sourceMessageId,
                approvalId = approvalId,
                actionHash = actionHash,
                kind = approval.optString("kind").trim().take(80),
                title = approval.optString("title").trim().take(500),
                detail = approval.optString("detail").trim().take(4_000),
                target = approval.optString("target").trim().take(2_000),
                reason = approval.optString("reason").trim().take(2_000),
                requestedAtMillis = requestedAt,
                expiresAtMillis = expiresAt,
                parametersJson = approval.optJSONObject("parameters")?.toString().orEmpty()
                    .take(16_384)
            )
        }
    }
}

data class AgentRemoteApprovalDecision(
    val taskId: String,
    val clientRouteId: String,
    val conversationId: String,
    val turnId: String,
    val contactId: String,
    val sourceMessageId: Long,
    val approvalId: String,
    val actionHash: String,
    val choice: AgentPermissionChoice
) {
    val approved: Boolean
        get() = choice.approved

    fun encode(): String = JSONObject()
        .put("task_id", taskId)
        .put("client_route_id", clientRouteId)
        .put("conversation_id", conversationId)
        .put("turn_id", turnId)
        .put("contact_id", contactId)
        .put("source_message_id", sourceMessageId)
        .put("approval_id", approvalId)
        .put("action_hash", actionHash)
        .put("decision_scope", choice.wireValue)
        .put("approved", approved)
        .toString()

    companion object {
        fun decode(raw: String): AgentRemoteApprovalDecision? {
            val value = runCatching { JSONObject(raw) }.getOrNull() ?: return null
            val taskId = value.optString("task_id").trim().take(160)
            val clientRouteId = value.optString("client_route_id").trim().take(200)
            val conversationId = value.optString("conversation_id").trim().take(200)
            val turnId = value.optString("turn_id").trim().take(200)
            val contactId = value.optString("contact_id").trim().take(160)
            val sourceMessageId = value.optLong("source_message_id", 0L)
            val approvalId = value.optString("approval_id").trim()
            val actionHash = value.optString("action_hash").trim().lowercase()
            val choice = AgentPermissionChoice.fromWireValue(
                value.optString("decision_scope")
            ) ?: return null
            if (taskId.isBlank() ||
                clientRouteId.isBlank() ||
                conversationId.isBlank() ||
                turnId.isBlank() ||
                contactId.isBlank() ||
                sourceMessageId <= 0L ||
                !AGENT_REMOTE_APPROVAL_ID.matches(approvalId) ||
                !AGENT_REMOTE_APPROVAL_HASH.matches(actionHash)
            ) {
                return null
            }
            return AgentRemoteApprovalDecision(
                taskId = taskId,
                clientRouteId = clientRouteId,
                conversationId = conversationId,
                turnId = turnId,
                contactId = contactId,
                sourceMessageId = sourceMessageId,
                approvalId = approvalId,
                actionHash = actionHash,
                choice = choice
            )
        }
    }
}
