package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** A transport child Run in the existing encrypted ledger, never a second chat session. */
internal class AgentProviderAttemptJournal(
    private val store: AgentRunEventStore,
    private val deviceId: String,
    private val identity: AgentProviderAttemptReport
) {
    constructor(context: Context, identity: AgentProviderAttemptReport) : this(
        AgentRunEventStore(context),
        AppStore.profile(context).let { it.optString("device_id").ifBlank { it.optString("galaxyssi_id") } },
        identity
    )

    val runId = runId(identity)

    fun checkpoint(report: AgentProviderAttemptReport) = append(report, terminal = false)

    fun finish(report: AgentProviderAttemptReport, cancelled: Boolean = false) = append(report, terminal = true, cancelled = cancelled)

    private fun append(report: AgentProviderAttemptReport, terminal: Boolean, cancelled: Boolean = false) {
        require(report.matches(identity.sourceMessageId, identity.conversationId, identity.turnId,
            identity.taskId, identity.actionId))
        val last = report.attempts.lastOrNull()
        val stage = if (terminal) "finished" else "${last?.ordinal}:${last?.state}"
        val eventId = "$runId:$stage"
        val event = AgentRunControlEvent(
            eventId = eventId, idempotencyKey = eventId,
            conversationId = identity.conversationId, messageId = identity.sourceMessageId.toString(),
            taskId = identity.taskId.ifBlank { identity.turnId.ifBlank { runId } }, runId = runId,
            turnId = identity.turnId, actionId = identity.actionId, agentId = "cloud-provider",
            deviceId = deviceId, sequence = 0L,
            type = if (terminal) {
                if (cancelled) AgentRunControlEventType.RUN_CANCELLED
                else if (last?.state == "completed") AgentRunControlEventType.RUN_COMPLETED else AgentRunControlEventType.RUN_FAILED
            } else if (last?.state == "started" && last.ordinal == 1) {
                AgentRunControlEventType.RUN_STARTED
            } else AgentRunControlEventType.CHECKPOINT_SAVED,
            payload = buildMap {
                put("recovery_mode", "observation_only")
                put(IDENTITY, AgentProviderAttemptCodec.encode(identity.copy(attempts = emptyList())).toString())
                last?.let { put(ATTEMPT, AgentProviderAttemptCodec.encodeAttempt(it).toString()) }
            }
        )
        // Telemetry storage failure must not terminate an otherwise healthy model stream.
        runCatching { store.appendNext(event) }.onFailure {
            Log.w("GalaxySSIProvider", "attempt_checkpoint_failed type=${it.javaClass.simpleName}")
        }
    }

    fun restore(): AgentProviderAttemptReport? {
        var sequence = 0L
        val attempts = sortedMapOf<Int, AgentProviderAttemptRecord>()
        while (true) {
            val page = store.eventsPage(runId, sequence)
            if (page.isEmpty()) break
            page.forEach { event ->
                val recorded = AgentProviderAttemptCodec.decode(JSONObject(event.payload.getValue(IDENTITY).toString()))
                require(recorded.matches(identity.sourceMessageId, identity.conversationId, identity.turnId,
                    identity.taskId, identity.actionId))
                event.payload[ATTEMPT]?.let { payload ->
                    val attempt = AgentProviderAttemptCodec.decodeAttempt(JSONObject(payload.toString()))
                    attempts[attempt.ordinal]?.let { require(it.requestId == attempt.requestId) }
                    attempts[attempt.ordinal] = attempt
                }
            }
            sequence = page.last().sequence
        }
        if (sequence == 0L) return null
        require(attempts.keys.toList() == (1..attempts.size).toList())
        return identity.copy(attempts = attempts.values.toList())
    }

    companion object {
        private const val IDENTITY = "provider_attempt_identity"
        private const val ATTEMPT = "provider_attempt"

        fun recover(context: Context, pending: AgentActionResult): AgentActionResult {
            val metadata = pending.metadata
            val recordedRun = metadata["provider_attempt_run_id"].orEmpty()
            if (recordedRun.isBlank()) return pending
            val identity = AgentProviderAttemptReport(
                metadata["source_message_id"]?.toLongOrNull() ?: return pending,
                metadata["conversation_id"].orEmpty(), metadata["turn_id"].orEmpty(),
                metadata["task_id"].orEmpty(), pending.actionId)
            if (recordedRun != runId(identity)) return pending
            return runCatching {
                val journal = AgentProviderAttemptJournal(context, identity)
                val report = journal.restore() ?: return pending
                pending.copy(metadata = report.mergeMetadata(metadata))
            }.getOrElse { pending }
        }

        fun runId(identity: AgentProviderAttemptReport): String {
            val bytes = JSONArray(listOf(identity.sourceMessageId, identity.conversationId,
                identity.turnId, identity.taskId, identity.actionId)).toString().toByteArray(Charsets.UTF_8)
            return try { "provider-attempts:${UUID.nameUUIDFromBytes(bytes)}" } finally { bytes.fill(0) }
        }
    }
}
