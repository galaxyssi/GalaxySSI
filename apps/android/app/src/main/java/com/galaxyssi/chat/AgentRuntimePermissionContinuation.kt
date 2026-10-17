package com.galaxyssi.chat

internal data class AgentRuntimePermissionContinuation(
    val sessionId: String,
    val conversationId: String,
    val turnId: String,
    val planId: String,
    val revision: Int,
    val actionId: String,
    val permissions: List<String>
) {
    val key get() = listOf(sessionId, planId, revision.toString(), actionId).joinToString(":")

    fun result(zh: Boolean) = AgentActionResult(actionId, false,
        if (zh) "\u9700\u8981\u5f00\u542f\u7cfb\u7edf\u6743\u9650\uff0c\u6388\u6743\u540e\u5c06\u7ee7\u7eed\u539f\u4efb\u52a1\uff1b\u5c1a\u672a\u6267\u884c\u6b64\u64cd\u4f5c\u3002"
        else "Android permission is required. The original task will continue after access is granted; this action has not run.",
        mapOf("permission_gate" to "android_before_dispatch", "dispatch_accepted" to "false",
            "business_success_verified" to "false", "goal_status" to "waiting_permission",
            "permission_session_id" to sessionId, "permission_conversation_id" to conversationId,
            "permission_turn_id" to turnId, "permission_plan_id" to planId,
            "permission_plan_revision" to revision.toString(), "android_permissions" to permissions.joinToString(",")))

    fun matches(session: String, conversation: String, turn: String, phase: AgentPhase, plan: AgentPlan?): Boolean =
        sessionId == session && conversationId == conversation && turnId == turn &&
            phase in setOf(AgentPhase.BLOCKED, AgentPhase.PAUSED) && plan?.planId == planId &&
            plan.revision == revision && plan.actions.any {
                it.id == actionId && it.status in setOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION)
            }

    companion object {
        val runtimePermissions = setOf(
            "android.permission.READ_PHONE_STATE", "android.permission.READ_SMS", "android.permission.SEND_SMS",
            "android.permission.READ_CONTACTS", "android.permission.WRITE_CONTACTS",
            "android.permission.READ_CALENDAR", "android.permission.WRITE_CALENDAR",
            "android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN",
            "android.permission.CAMERA", "android.permission.RECORD_AUDIO", "android.permission.POST_NOTIFICATIONS")

        fun parse(result: AgentActionResult?): AgentRuntimePermissionContinuation? {
            val metadata = result?.metadata ?: return null
            if (metadata["permission_gate"] != "android_before_dispatch" || metadata["dispatch_accepted"] != "false") return null
            val ids = listOf("permission_session_id", "permission_conversation_id", "permission_turn_id", "permission_plan_id")
                .map { metadata[it].orEmpty() }
            if (ids.any(String::isBlank) || result.actionId.isBlank()) return null
            val permissions = metadata["android_permissions"].orEmpty().split(',').distinct()
            if (permissions.isEmpty() || permissions.any { it !in runtimePermissions }) return null
            val revision = metadata["permission_plan_revision"]?.toIntOrNull()?.takeIf { it > 0 } ?: return null
            return AgentRuntimePermissionContinuation(ids[0], ids[1], ids[2], ids[3], revision, result.actionId, permissions)
        }
    }
}
