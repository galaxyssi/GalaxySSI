package com.galaxyssi.chat

import android.content.Context
import java.util.UUID
import org.json.JSONObject

/** A scoped goal survives the model context and process, independently of recurring schedules. */
internal data class AgentDeviceOperation(
    val conversationId: String,
    val id: String = UUID.randomUUID().toString(),
    val kind: String = "timer",
    val seconds: Int = 0,
    val desired: String = "start",
    val status: String = "prepared",
    val dispatched: Boolean = false,
    val evidence: String = "",
    val updatedAt: Long = System.currentTimeMillis(),
    val goal: String = "",
    val completionJson: String = "",
    val replacementSeconds: Int? = null,
    val dispatchedAt: Long = 0,
    val durationVerified: Boolean = false,
    val sourceTurnId: String = "",
    val sourceSessionId: String = ""
) {
    val label: String get() = "GalaxySSI-${id.take(8)}"
    fun context(): String = if (kind != "timer") "Scoped executable goal: $goal\n" +
        "operation_id=$id; source_turn_id=$sourceTurnId; source_session_id=$sourceSessionId; status=$status; completion_requirements=$completionJson; latest_evidence=$evidence. " +
        "This is prior state, not an instruction to replay completed work. Apply the latest user request, inspect current state when needed, and do not repeat prior side effects." else
        "Phone operation: kind=$kind; id=$id; duration_seconds=$seconds; " +
        "desired=$desired; status=$status; dispatch_accepted=$dispatched; evidence=$evidence. " +
        "This is a single phone operation, not a recurring schedule. Observe before retrying; do not create duplicates."
}

internal class AgentDeviceOperationStore(
    private val ledger: AgentRunEventStore,
    private val sessionLookup: ((String) -> AgentSessionSnapshot?)? = null
) {
    constructor(context: Context) : this(AgentRunEventStore(context.applicationContext), { turnId ->
        SharedPreferencesAgentSessionStore(context.applicationContext, "task:$turnId").load()
    })
    fun get(conversationId: String): AgentDeviceOperation? {
        val saved = checkpoint(conversationId) ?: return null
        val lookup = sessionLookup ?: return saved
        if (saved.kind != "agent" || saved.sourceTurnId.isBlank()) return saved
        return AgentOperationRuntimeProjection.project(saved, runCatching { lookup(saved.sourceTurnId) }.getOrNull())
    }

    private fun checkpoint(conversationId: String): AgentDeviceOperation? {
        if (conversationId.isBlank()) return null
        val p = ledger.latestEvent(runId(conversationId))
            ?.takeIf(AgentDeviceOperationCheckpoint::isSnapshot)?.payload ?: return null
        return AgentDeviceOperation(conversationId, p["operation_id"] as? String ?: return null,
            p["kind"] as? String ?: return null, (p["seconds"] as? Number)?.toInt() ?: return null,
            p["desired"] as? String ?: "start", p["status"] as? String ?: "unknown",
            p["dispatched"] == true, p["evidence"] as? String ?: "",
            (p["updated_at"] as? Number)?.toLong() ?: 0,
            p["goal"] as? String ?: "", p["completion_json"] as? String ?: "",
            (p["replacement_seconds"] as? Number)?.toInt()?.takeIf { it > 0 },
            (p["dispatched_at"] as? Number)?.toLong() ?: 0, p["duration_verified"] == true,
            p["source_turn_id"] as? String ?: "", p["source_session_id"] as? String ?: "")
    }

    fun save(value: AgentDeviceOperation): AgentDeviceOperation {
        require(value.conversationId.isNotBlank() && (value.kind != "timer" || value.seconds > 0))
        val record = value.copy(updatedAt = System.currentTimeMillis())
        val prior = ledger.latestEvent(runId(record.conversationId))
        check(ledger.appendNext(AgentRunControlEvent(
            conversationId = record.conversationId, messageId = "", taskId = runId(record.conversationId),
            runId = runId(record.conversationId), agentId = "phone-operation", deviceId = "local",
            // Repair only the old generic recovery misclassification, never an actual task cancellation.
            type = if (prior?.let(AgentDeviceOperationCheckpoint::isMisclassifiedFailure) == true)
                AgentRunControlEventType.RUN_RECOVERED else AgentRunControlEventType.CHECKPOINT_SAVED,
            sequence = 0,
            payload = mapOf("snapshot_kind" to "device_operation", "recovery_mode" to "observation_only",
                "operation_id" to record.id,
                "kind" to record.kind, "seconds" to record.seconds, "desired" to record.desired,
                "status" to record.status, "dispatched" to record.dispatched,
                "evidence" to record.evidence, "updated_at" to record.updatedAt,
                "goal" to record.goal, "completion_json" to record.completionJson,
                "replacement_seconds" to (record.replacementSeconds ?: 0),
                "dispatched_at" to record.dispatchedAt, "duration_verified" to record.durationVerified,
                "source_turn_id" to record.sourceTurnId, "source_session_id" to record.sourceSessionId)
        )) != null) { "The phone operation checkpoint could not be saved" }
        return record
    }

    fun claimContinuation(value: AgentDeviceOperation): Boolean {
        val event = ledger.latestEvent(runId(value.conversationId)) ?: return false
        if (event.payload["operation_id"] != value.id || event.payload["status"] != "waiting_accessibility") return false
        return ledger.appendRecoveryIfCurrent(event.copy(eventId = UUID.randomUUID().toString(),
            idempotencyKey = "", actionId = "", sequence = 0, timestampMillis = System.currentTimeMillis(),
            payload = event.payload + mapOf("status" to "resuming", "updated_at" to System.currentTimeMillis())),
            event.sequence) != null
    }

    fun recordPlan(conversationId: String, goal: String, requirements: AgentCompletionRequirements?,
        sourceTurnId: String = "", sourceSessionId: String = "") {
        if (conversationId.isBlank()) return
        val prior = checkpoint(conversationId)
        val current = if (prior?.kind == "timer" && AgentDeviceIntent.needsOperationContext(goal)) prior else
            prior?.takeIf { it.kind == "agent" && it.goal == goal && it.sourceTurnId == sourceTurnId &&
                it.sourceSessionId == sourceSessionId } ?: AgentDeviceOperation(conversationId, kind = "agent", goal = goal)
        save(current.copy(completionJson = requirements?.toJson()?.toString().orEmpty(),
            sourceTurnId = sourceTurnId.ifBlank { current.sourceTurnId },
            sourceSessionId = sourceSessionId.ifBlank { current.sourceSessionId },
            status = if (current.kind == "agent") "prepared" else current.status))
    }

    private fun runId(conversationId: String) = AgentDeviceOperationCheckpoint.runId(conversationId)
}

/** Device-operation snapshots are context, not executable Runs for the generic recovery coordinator. */
internal object AgentDeviceOperationCheckpoint {
    fun runId(conversationId: String) = "device-operation:" + AgentNativeJsonCodec.sha256(conversationId)

    fun isSnapshot(event: AgentRunControlEvent): Boolean =
        event.payload["snapshot_kind"] == "device_operation" &&
            event.agentId == "phone-operation" && event.deviceId == "local" &&
            event.conversationId.isNotBlank() && event.runId == runId(event.conversationId) &&
            event.taskId == event.runId && event.messageId.isBlank() &&
            (event.payload["operation_id"] as? String)?.isNotBlank() == true

    fun isMisclassifiedFailure(event: AgentRunControlEvent): Boolean = isSnapshot(event) &&
        event.type == AgentRunControlEventType.RUN_FAILED && event.payload["replay_safe"] == false &&
        event.payload["reason"] == "interrupted_run_cannot_be_replayed_safely"
}

internal enum class AgentGoalEvidenceStatus { VERIFIED, DISPATCHED, BLOCKED, UNKNOWN, FAILED }

/** Transport/API acceptance and business completion are deliberately separate. */
internal object AgentGoalEvidence {
    data class PendingReceipt(val message: String, val requiredCapability: String, val nextAction: String,
        val actionId: String = "", val toolId: String = "") {
        val canInspect: Boolean get() = requiredCapability.isBlank()
    }

    fun permitsSuccess(result: AgentActionResult?): Boolean {
        if (result?.success != true || result.metadata["business_success_verified"] == "false") return false
        if (result.metadata["goal_status"] in setOf("dispatched", "blocked", "unknown", "failed")) return false
        // Durable receipts may predate normalized goal metadata; retain their explicit delivery caveat.
        val raw = runCatching { JSONObject(result.metadata["native_tool_output"].orEmpty()) }.getOrNull()
        val output = raw?.optJSONObject("output") ?: raw
        if (result.metadata["native_tool_id"] in AgentDeviceStateEvidence.tools && output?.opt("state_verified") != true) return false
        return output?.opt("state_verified") != false && output?.opt("delivery_verified") != false &&
            output?.optJSONObject("metadata")?.optString("business_success_verified") != "false"
    }

    fun notificationReply(action: AgentAction, reply: AgentNotificationReplyResult, zh: Boolean): AgentActionResult {
        val identity = mapOf("notification_key_sha256" to AgentNativeJsonCodec.sha256(action.parameters["notification_key"].orEmpty()),
            "notification_package" to reply.notificationPackage.ifBlank { action.parameters["notification_package"].orEmpty() },
            "reply_length" to action.parameters["reply_text"].orEmpty().length.toString())
        if (!reply.success) return result(action, AgentGoalEvidenceStatus.FAILED, reply.message,
            extra = identity + ("error_code" to reply.code))
        val output = withDeliveryEvidence(mapOf("dispatch_accepted" to true, "delivery_verified" to false),
            mapOf("handoff_only" to true, "delivery_receipt_available" to false), zh)
        return AgentActionResult(action.id, true, output["message"] as String, identity + metadata(output))
    }

    /** Preserve native delivery caveats in both planner evidence and UI verification. */
    fun withDeliveryEvidence(output: AgentNativeJsonObject, nativeMetadata: AgentNativeJsonObject,
        zh: Boolean): AgentNativeJsonObject {
        if (output["delivery_verified"] != false && nativeMetadata["delivery_receipt_available"] != false) return output
        val prior = output["metadata"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val accepted = output["dispatch_accepted"] == true || nativeMetadata["handoff_only"] == true
        val message = if (zh) {
            if (accepted) "\u5df2\u63d0\u4ea4\u53d1\u9001\u8bf7\u6c42\uff0c\u5c1a\u672a\u786e\u8ba4\u5bf9\u65b9\u6536\u5230\u3002"
            else "\u5c1a\u672a\u786e\u8ba4\u6d88\u606f\u9001\u8fbe\u3002"
        } else if (accepted) "The send request was submitted; recipient delivery is not confirmed."
        else "Message delivery is not confirmed."
        val unavailable = nativeMetadata["delivery_receipt_available"] == false || output["delivery_receipt_available"] == false
        return output + mapOf("message" to message, "metadata" to (prior + mapOf(
            "goal_status" to if (accepted) "dispatched" else "unknown",
            "business_success_verified" to "false", "goal_evidence" to "recipient_delivery_unverified",
            "next_action" to "inspect_delivery_receipt_before_retrying") +
            if (unavailable) mapOf("required_capability" to "recipient_delivery_receipt") else emptyMap<String, String>()))
    }

    fun hasVerifiedOutcome(history: List<AgentAction>): Boolean = history.lastOrNull {
        it.kind == AgentActionKind.CALL_NATIVE_TOOL
    }?.let { action ->
        if (action.status != AgentActionStatus.COMPLETED) false else {
            val raw = runCatching { JSONObject(action.evidence) }.getOrNull()
            val output = raw?.optJSONObject("output") ?: raw
            output?.opt("state_verified") != false && output?.optJSONObject("metadata")?.optString("goal_status") == "verified"
        }
    } == true

    fun metadata(output: AgentNativeJsonObject): Map<String, String> {
        val source = output["metadata"] as? Map<*, *> ?: return emptyMap()
        return source.entries.filter { it.key in setOf("goal_status", "business_success_verified", "goal_evidence",
            "required_capability", "operation_id", "error_code", "next_action") && it.value is String }
            .associate { it.key as String to it.value as String }
    }

    fun unverifiedOutcome(history: List<AgentAction>): String? = pendingReceipt(history)?.message

    fun pendingReceipt(history: List<AgentAction>): PendingReceipt? = pendingReceipts(history).lastOrNull()

    fun pendingReceipts(history: List<AgentAction>): List<PendingReceipt> =
        AgentProjectHistoryRetentionPolicy.latestSnapshots(history).mapNotNull { action ->
            if (action.kind != AgentActionKind.CALL_NATIVE_TOOL || AgentObservedOutcomeEvidence.isUndispatched(action))
                return@mapNotNull null
            val raw = runCatching { JSONObject(action.evidence) }.getOrNull() ?: return@mapNotNull null
            val output = raw.optJSONObject("output") ?: raw
            val metadata = output.optJSONObject("metadata") ?: JSONObject()
            val unknown = AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(action)
            if (!unknown && action.status in setOf(AgentActionStatus.FAILED, AgentActionStatus.BLOCKED) &&
                metadata.optString("goal_status") in setOf("failed", "blocked")) return@mapNotNull null
            val uncertain = unknown ||
                metadata.opt("business_success_verified")?.toString() == "false"
            val status = if (uncertain) "unknown" else metadata.optString("goal_status")
            if (status.isEmpty() || status == "verified" && action.status == AgentActionStatus.COMPLETED)
                return@mapNotNull null
            PendingReceipt(output.optString("message").ifBlank { "The requested outcome has not been verified." },
                metadata.optString("required_capability"), metadata.optString("next_action"),
                action.id, action.parameters["tool_id"].orEmpty().ifBlank { action.target })
        }

    fun result(action: AgentAction, status: AgentGoalEvidenceStatus, message: String,
        evidence: String = "", extra: Map<String, String> = emptyMap()): AgentActionResult = AgentActionResult(
        action.id, status == AgentGoalEvidenceStatus.VERIFIED || status == AgentGoalEvidenceStatus.DISPATCHED,
        message, extra + mapOf("goal_status" to status.name.lowercase(),
            "business_success_verified" to (status == AgentGoalEvidenceStatus.VERIFIED).toString(),
            "goal_evidence" to evidence))
}
