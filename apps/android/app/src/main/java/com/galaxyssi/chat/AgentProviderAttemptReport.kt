package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/** Transport facts only. Never contains credentials, prompts, or generated text. */
data class AgentProviderAttemptRecord(
    val ordinal: Int,
    val requestId: String,
    val resourceId: String,
    val providerId: String,
    val modelId: String,
    val startedAtMillis: Long,
    val elapsedMillis: Long = 0L,
    val state: String = "started",
    val failureClass: String = "",
    val retryable: Boolean = false,
    val httpStatus: Int? = null
) {
    internal fun failure(): AgentProviderFailure? = AgentProviderFailureClass.entries
        .firstOrNull { it.name.equals(failureClass, ignoreCase = true) }
        ?.let { AgentProviderFailure(it, retryable) }
}

data class AgentProviderAttemptReport(
    val sourceMessageId: Long,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val actionId: String,
    val attempts: List<AgentProviderAttemptRecord> = emptyList()
) {
    internal fun matches(source: Long, conversation: String, turn: String, task: String, action: String) =
        sourceMessageId == source && conversationId == conversation && turnId == turn &&
            taskId == task && actionId == action

    internal fun mergeMetadata(previous: Map<String, String>): Map<String, String> {
        if (attempts.isEmpty()) return previous
        val finished = attempts.filter { it.state == "failed" || it.state == "completed" }
        val tried = attempts.map { it.resourceId }.filter(String::isNotBlank).toSet()
        val attempted = AgentConnectorFallbackAction.attempted(previous) + tried
        val exhausted = finished.filter { it.state == "failed" }.map { it.resourceId }.toSet()
        val last = attempts.last()
        return previous + mapOf(
            AgentConnectorFallbackAction.ATTEMPTED_RESULT to AgentConnectorFallbackTrail.encode(attempted),
            "remaining_fallback_ids" to AgentConnectorFallbackTrail.encode(
                AgentConnectorFallbackTrail.parse(previous["remaining_fallback_ids"].orEmpty()) - tried),
            "deferred_retry_ids" to AgentConnectorFallbackTrail.encode(
                AgentConnectorFallbackTrail.parse(previous["deferred_retry_ids"].orEmpty()) - exhausted),
            // The inner transport already applied its retry policy. Do not reset it in the outer loop.
            "retried_resource_ids" to AgentConnectorFallbackTrail.encode(
                AgentConnectorFallbackTrail.parse(previous["retried_resource_ids"].orEmpty()) + exhausted),
            "resource_id" to last.resourceId,
            "resolved_model_id" to last.modelId,
            "resolved_provider_id" to last.providerId,
            "failure_domain" to "cloud:${last.providerId.ifBlank { last.resourceId }}",
            "provider_attempt_count" to attempts.size.toString(),
            "provider_attempt_state" to last.state,
            "provider_failure_class" to last.failureClass,
            "non_retriable" to (last.failure()?.permanent == true).toString(),
            "provider_attempt_report" to AgentProviderAttemptCodec.encode(this).toString()
        )
    }
}

internal object AgentProviderAttemptCodec {
    fun encode(report: AgentProviderAttemptReport): JSONObject = JSONObject()
        .put("source_message_id", report.sourceMessageId)
        .put("conversation_id", report.conversationId).put("turn_id", report.turnId)
        .put("task_id", report.taskId).put("action_id", report.actionId)
        .put("attempts", JSONArray().apply {
            report.attempts.forEach { put(encodeAttempt(it)) }
        })

    fun decode(value: JSONObject): AgentProviderAttemptReport = AgentProviderAttemptReport(
        value.getLong("source_message_id"), value.getString("conversation_id"), value.getString("turn_id"),
        value.getString("task_id"), value.getString("action_id"),
        value.getJSONArray("attempts").let { items -> List(items.length()) { index ->
            decodeAttempt(items.getJSONObject(index)).also { require(it.ordinal == index + 1) }
        } }
    )

    fun encodeAttempt(attempt: AgentProviderAttemptRecord): JSONObject = JSONObject()
        .put("ordinal", attempt.ordinal).put("request_id", attempt.requestId)
        .put("resource_id", attempt.resourceId).put("provider_id", attempt.providerId)
        .put("model_id", attempt.modelId).put("started_at", attempt.startedAtMillis)
        .put("elapsed_ms", attempt.elapsedMillis).put("state", attempt.state)
        .put("failure_class", attempt.failureClass).put("retryable", attempt.retryable)
        .put("http_status", attempt.httpStatus)

    fun decodeAttempt(item: JSONObject): AgentProviderAttemptRecord = AgentProviderAttemptRecord(
        item.getInt("ordinal"), item.getString("request_id"), item.getString("resource_id"),
        item.getString("provider_id"), item.getString("model_id"), item.getLong("started_at"),
        item.getLong("elapsed_ms"), item.getString("state"), item.optString("failure_class"),
        item.optBoolean("retryable"), item.optInt("http_status").takeIf { it in 100..599 }
    ).also {
        require(it.ordinal > 0 && it.requestId.isNotBlank() && it.resourceId.isNotBlank())
        require(it.elapsedMillis >= 0 && it.state in setOf("started", "connected", "first_output", "completed", "failed", "cancelled"))
    }
}

internal class AgentProviderAttemptTracker(
    initial: AgentProviderAttemptReport,
    private val checkpoint: (AgentProviderAttemptReport) -> Unit = {}
) {
    var report = initial
        private set

    fun start(requestId: String, resourceId: String, providerId: String, modelId: String, now: Long) {
        require(report.attempts.lastOrNull()?.state !in setOf("started", "connected", "first_output"))
        update(report.copy(attempts = report.attempts + AgentProviderAttemptRecord(
            report.attempts.size + 1, requestId, resourceId, providerId, modelId, now)))
    }

    fun progress(state: String, elapsed: Long) {
        require(state in setOf("connected", "first_output"))
        val last = report.attempts.last()
        if (last.state in setOf("failed", "completed", "cancelled", "first_output") || last.state == state) return
        update(report.copy(attempts = report.attempts.dropLast(1) + last.copy(state = state, elapsedMillis = elapsed)))
    }

    fun finish(elapsed: Long, failure: AgentProviderFailure? = null, httpStatus: Int? = null) {
        val last = report.attempts.last()
        require(last.state !in setOf("failed", "completed", "cancelled"))
        update(report.copy(attempts = report.attempts.dropLast(1) + last.copy(
            state = if (failure == null) "completed" else "failed", elapsedMillis = elapsed,
            failureClass = failure?.failureClass?.name?.lowercase(Locale.ROOT).orEmpty(),
            retryable = failure?.retryable == true, httpStatus = httpStatus)))
    }

    fun cancel(now: Long) {
        val last = report.attempts.lastOrNull() ?: return
        if (last.state !in setOf("started", "connected", "first_output")) return
        update(report.copy(attempts = report.attempts.dropLast(1) + last.copy(
            state = "cancelled", elapsedMillis = (now - last.startedAtMillis).coerceAtLeast(0), retryable = false)))
    }

    private fun update(next: AgentProviderAttemptReport) {
        report = next
        checkpoint(next)
    }
}
