package com.galaxyssi.chat.voice.agent

import android.content.Context
import com.galaxyssi.chat.AgentNativeJsonObject
import com.galaxyssi.chat.AgentRunControlEvent
import com.galaxyssi.chat.AgentRunControlEventType
import com.galaxyssi.chat.AgentRunEventStore
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

enum class VoiceAgentRunState {
    CREATED,
    ACCEPTED,
    QUEUED,
    STARTING,
    RUNNING,
    WAITING_INPUT,
    WAITING_APPROVAL,
    CANCELLING,
    COMPLETED,
    FAILED,
    CANCELLED,
    TIMED_OUT;

    val isTerminal: Boolean
        get() = this in setOf(COMPLETED, FAILED, CANCELLED, TIMED_OUT)
}

data class VoiceAgentRunRequest(
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val sourceMessageId: Long,
    val contactId: String,
    val agentId: String,
    val agentName: String,
    val deviceId: String,
    val goal: String,
    val idempotencyKey: String,
    val traceId: String = "",
    val createdAtMillis: Long = System.currentTimeMillis()
)

data class VoiceAgentRunSnapshot(
    val runId: String,
    val conversationId: String,
    val turnId: String,
    val taskId: String,
    val sourceMessageId: Long,
    val contactId: String,
    val agentId: String,
    val agentName: String,
    val deviceId: String,
    val goal: String,
    val idempotencyKey: String,
    val traceId: String,
    val state: VoiceAgentRunState,
    val stage: String = "",
    val progressMessage: String = "",
    val progressPercent: Double? = null,
    val partialResult: String = "",
    val firstDiscovery: String = "",
    val resultSummary: String = "",
    val approvalId: String = "",
    val lastStatusSequence: Long = 0L,
    val lastPartialSequence: Long = 0L,
    val seenEventIds: List<String> = emptyList(),
    val createdAtMillis: Long,
    val acceptedAtMillis: Long = 0L,
    val updatedAtMillis: Long,
    val completedAtMillis: Long = 0L
) {
    val hasRemoteAcceptance: Boolean get() = acceptedAtMillis > 0L
    val cancellable: Boolean get() = !state.isTerminal && state != VoiceAgentRunState.CANCELLING
}

sealed interface VoiceAgentEvent {
    val runId: String
    val eventId: String
    val statusSequence: Long

    data class RunCreated(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long = 0L
    ) : VoiceAgentEvent

    data class Accepted(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val remoteAtMillis: Long?
    ) : VoiceAgentEvent

    data class StageChanged(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val state: VoiceAgentRunState,
        val stage: String
    ) : VoiceAgentEvent

    data class Progress(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val message: String,
        val percent: Double?
    ) : VoiceAgentEvent

    data class PartialResult(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val text: String,
        val sequence: Long
    ) : VoiceAgentEvent

    data class ApprovalRequired(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val approvalId: String
    ) : VoiceAgentEvent

    data class Completed(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val resultSummary: String
    ) : VoiceAgentEvent

    data class Failed(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long,
        val error: String,
        val timedOut: Boolean = false
    ) : VoiceAgentEvent

    data class Cancelled(
        override val runId: String,
        override val eventId: String,
        override val statusSequence: Long
    ) : VoiceAgentEvent
}

data class VoiceAgentRunCreation(
    val snapshot: VoiceAgentRunSnapshot,
    val created: Boolean
)

data class VoiceAgentRunTransition(
    val event: VoiceAgentEvent,
    val previous: VoiceAgentRunSnapshot,
    val snapshot: VoiceAgentRunSnapshot,
    val firstAcceptance: Boolean = false,
    val firstProgress: Boolean = false,
    val firstPartialResult: Boolean = false
)

data class VoiceAgentRunUpdate(
    val snapshot: VoiceAgentRunSnapshot,
    val event: VoiceAgentEvent,
    val previous: VoiceAgentRunSnapshot? = null,
    val firstAcceptance: Boolean = false,
    val firstProgress: Boolean = false,
    val firstPartialResult: Boolean = false
)

fun interface VoiceAgentRunListener {
    fun onRunUpdated(update: VoiceAgentRunUpdate)
}

interface VoiceAgentRunRepository {
    fun save(snapshot: VoiceAgentRunSnapshot, event: VoiceAgentEvent)
    fun find(runId: String): VoiceAgentRunSnapshot?
    fun findByTaskId(taskId: String): VoiceAgentRunSnapshot?
    fun findBySourceMessageId(sourceMessageId: Long): VoiceAgentRunSnapshot?
    fun findByIdempotencyKey(idempotencyKey: String): VoiceAgentRunSnapshot?
    fun list(): List<VoiceAgentRunSnapshot>
    fun clear()
}

class InMemoryVoiceAgentRunRepository : VoiceAgentRunRepository {
    private val snapshots = linkedMapOf<String, VoiceAgentRunSnapshot>()

    @Synchronized
    override fun save(snapshot: VoiceAgentRunSnapshot, event: VoiceAgentEvent) {
        snapshots[snapshot.runId] = snapshot
    }

    @Synchronized
    override fun find(runId: String): VoiceAgentRunSnapshot? = snapshots[runId]

    @Synchronized
    override fun findByTaskId(taskId: String): VoiceAgentRunSnapshot? =
        snapshots.values.lastOrNull { it.taskId == taskId }

    @Synchronized
    override fun findBySourceMessageId(sourceMessageId: Long): VoiceAgentRunSnapshot? =
        snapshots.values.lastOrNull { it.sourceMessageId == sourceMessageId }

    @Synchronized
    override fun findByIdempotencyKey(idempotencyKey: String): VoiceAgentRunSnapshot? =
        snapshots.values.lastOrNull { it.idempotencyKey == idempotencyKey }

    @Synchronized
    override fun list(): List<VoiceAgentRunSnapshot> = snapshots.values.toList()

    @Synchronized
    override fun clear() = snapshots.clear()
}

class AgentRunEventVoiceAgentRunRepository(
    private val eventStore: AgentRunEventStore
) : VoiceAgentRunRepository {

    @Synchronized
    override fun save(snapshot: VoiceAgentRunSnapshot, event: VoiceAgentEvent) {
        val controlEvent = event.toControlEvent(snapshot)
        checkNotNull(eventStore.appendNext(controlEvent.copy(
            payload = controlEvent.payload + mapOf(
                SNAPSHOT_MARKER_KEY to true,
                SNAPSHOT_JSON_KEY to snapshot.toJson().toString()
            )
        ))) { "Voice Agent Run event could not be persisted" }
    }

    @Synchronized
    override fun find(runId: String): VoiceAgentRunSnapshot? = decodeRun(runId)

    @Synchronized
    override fun findByTaskId(taskId: String): VoiceAgentRunSnapshot? =
        list().lastOrNull { it.taskId == taskId }

    @Synchronized
    override fun findBySourceMessageId(sourceMessageId: Long): VoiceAgentRunSnapshot? =
        list().lastOrNull { it.sourceMessageId == sourceMessageId }

    @Synchronized
    override fun findByIdempotencyKey(idempotencyKey: String): VoiceAgentRunSnapshot? =
        list().lastOrNull { it.idempotencyKey == idempotencyKey }

    @Synchronized
    override fun list(): List<VoiceAgentRunSnapshot> = eventStore.storedRunIds(MAX_RUNS)
        .mapNotNull(::decodeRun)

    @Synchronized
    override fun clear() {
        eventStore.removeRuns(list().mapTo(linkedSetOf(), VoiceAgentRunSnapshot::runId))
    }

    private fun decodeRun(runId: String): VoiceAgentRunSnapshot? = eventStore.events(runId)
        .asReversed()
        .firstNotNullOfOrNull { event ->
            event.payload[SNAPSHOT_JSON_KEY]
                ?.toString()
                ?.takeIf(String::isNotBlank)
                ?.let { raw -> runCatching { JSONObject(raw).toVoiceAgentRunSnapshot() }.getOrNull() }
        }

    private companion object {
        const val SNAPSHOT_MARKER_KEY = "voice_agent_run"
        const val SNAPSHOT_JSON_KEY = "voice_agent_run_snapshot"
        const val MAX_RUNS = 256
    }
}

fun interface VoiceAgentRunClock {
    fun nowMillis(): Long
}

class VoiceAgentRunBridge(
    private val repository: VoiceAgentRunRepository,
    private val clock: VoiceAgentRunClock = VoiceAgentRunClock(System::currentTimeMillis)
) {
    private val listeners = CopyOnWriteArrayList<VoiceAgentRunListener>()

    fun addListener(listener: VoiceAgentRunListener) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: VoiceAgentRunListener) {
        listeners.remove(listener)
    }

    @Synchronized
    fun createRun(request: VoiceAgentRunRequest): VoiceAgentRunCreation {
        require(request.conversationId.isNotBlank()) { "Conversation id must not be blank" }
        require(request.turnId.isNotBlank()) { "Turn id must not be blank" }
        require(request.taskId.isNotBlank()) { "Task id must not be blank" }
        require(request.sourceMessageId > 0L) { "Source message id must be positive" }
        require(request.idempotencyKey.isNotBlank()) { "Idempotency key must not be blank" }
        val runId = stableRunId(request.idempotencyKey)
        repository.find(runId)?.let {
            return VoiceAgentRunCreation(it, created = false)
        }
        val now = request.createdAtMillis.takeIf { it > 0L } ?: clock.nowMillis()
        val snapshot = VoiceAgentRunSnapshot(
            runId = runId,
            conversationId = request.conversationId,
            turnId = request.turnId,
            taskId = request.taskId,
            sourceMessageId = request.sourceMessageId,
            contactId = request.contactId,
            agentId = request.agentId,
            agentName = request.agentName,
            deviceId = request.deviceId,
            goal = request.goal.take(MAX_GOAL_CHARACTERS),
            idempotencyKey = request.idempotencyKey,
            traceId = request.traceId,
            state = VoiceAgentRunState.CREATED,
            seenEventIds = listOf(localCreatedEventId(runId)),
            createdAtMillis = now,
            updatedAtMillis = now
        )
        val event = VoiceAgentEvent.RunCreated(runId, localCreatedEventId(runId))
        repository.save(snapshot, event)
        notifyListeners(VoiceAgentRunUpdate(snapshot = snapshot, event = event))
        return VoiceAgentRunCreation(snapshot, created = true)
    }

    @Synchronized
    fun consumeRemoteEnvelope(envelope: JSONObject): List<VoiceAgentRunTransition> {
        if (envelope.optString("type") != "agent_task_event") return emptyList()
        val payload = envelope.optJSONObject("payload") ?: JSONObject()
        val taskId = envelope.optString("task_id").trim().ifBlank {
            payload.optString("task_id").trim()
        }
        val sourceMessageId = envelope.optString("source_message_id").toLongOrNull()
            ?: envelope.optLong("source_message_id", 0L)
                .takeIf { it > 0L }
            ?: envelope.optString("message_id").toLongOrNull()
            ?: payload.optString("source_message_id").toLongOrNull()
            ?: payload.optLong("source_message_id", 0L)
        val runId = envelope.optString("run_id").trim()
        val current = runId.takeIf(String::isNotBlank)?.let(repository::find)
            ?: repository.findByTaskId(taskId)
            ?: repository.findBySourceMessageId(sourceMessageId)
            ?: recoverSnapshot(envelope, taskId, sourceMessageId)
            ?: return emptyList()
        val statusSequence = envelope.optLong("status_seq", 0L).coerceAtLeast(0L)
        val status = envelope.optString("task_status").trim().lowercase()
        val eventType = envelope.optString("event_type").trim().lowercase()
        val rootEventId = envelope.optString("event_id").trim().ifBlank {
            "status:${taskId.ifBlank { current.taskId }}:$statusSequence:${eventType.ifBlank { status }}"
        }
        val events = buildList {
            val standardEvent = eventType.takeIf(String::isNotBlank)?.let {
                mapStandardEvent(
                    runId = current.runId,
                    taskId = taskId.ifBlank { current.taskId },
                    eventId = rootEventId,
                    statusSequence = statusSequence,
                    eventType = it,
                    envelope = envelope,
                    payload = payload
                )
            }
            if (standardEvent != null) {
                add(standardEvent)
            } else {
                statusEvent(current.runId, rootEventId, statusSequence, status, envelope)?.let(::add)
                envelope.optJSONObject("progress_event")?.let { progress ->
                    mapProgressEvent(current.runId, taskId, statusSequence, progress)?.let(::add)
                }
                envelope.optJSONObject("partial_result")?.let { partial ->
                    mapPartialResult(current.runId, taskId, statusSequence, partial)?.let(::add)
                }
                envelope.optJSONObject("approval_request")
                    ?.takeIf { it.length() > 0 }
                    ?.let { approval ->
                        approvalEvent(current.runId, taskId, statusSequence, approval)?.let(::add)
                    }
            }
        }
        return events.mapNotNull(::applyRemoteEvent)
    }

    @Synchronized
    fun consumeLegacyFinal(
        sourceMessageId: Long,
        taskId: String,
        content: String,
        timestampMillis: Long = clock.nowMillis()
    ): VoiceAgentRunTransition? {
        val snapshot = repository.findByTaskId(taskId)
            ?: repository.findBySourceMessageId(sourceMessageId)
            ?: return null
        if (snapshot.state.isTerminal) return null
        return applyRemoteEvent(VoiceAgentEvent.Completed(
            runId = snapshot.runId,
            eventId = "legacy-final:${snapshot.taskId}:${content.hashCode()}",
            statusSequence = snapshot.lastStatusSequence + 1L,
            resultSummary = visibleText(content, MAX_RESULT_CHARACTERS)
        ), timestampMillis)
    }

    @Synchronized
    fun markCancellationRequested(runId: String): VoiceAgentRunSnapshot? {
        val snapshot = repository.find(runId) ?: return null
        if (!snapshot.cancellable) return snapshot
        val updated = snapshot.copy(
            state = VoiceAgentRunState.CANCELLING,
            stage = "cancelling",
            updatedAtMillis = clock.nowMillis()
        )
        val event = VoiceAgentEvent.StageChanged(
            runId = runId,
            eventId = "local-cancelling:$runId:${updated.updatedAtMillis}",
            statusSequence = snapshot.lastStatusSequence,
            state = VoiceAgentRunState.CANCELLING,
            stage = "cancelling"
        )
        repository.save(updated, event)
        notifyListeners(VoiceAgentRunUpdate(
            snapshot = updated,
            previous = snapshot,
            event = event
        ))
        return updated
    }

    @Synchronized
    fun markDispatchFailed(runId: String, error: String): VoiceAgentRunTransition? {
        val snapshot = repository.find(runId) ?: return null
        if (snapshot.state.isTerminal) return null
        return applyRemoteEvent(VoiceAgentEvent.Failed(
            runId = runId,
            eventId = "local-dispatch-failed:$runId",
            statusSequence = snapshot.lastStatusSequence + 1L,
            error = error,
            timedOut = false
        ))
    }

    fun find(runId: String): VoiceAgentRunSnapshot? = repository.find(runId)

    fun findByTaskId(taskId: String): VoiceAgentRunSnapshot? = repository.findByTaskId(taskId)

    fun findBySourceMessageId(sourceMessageId: Long): VoiceAgentRunSnapshot? =
        repository.findBySourceMessageId(sourceMessageId)

    fun snapshots(conversationId: String = ""): List<VoiceAgentRunSnapshot> = repository.list()
        .filter { conversationId.isBlank() || it.conversationId == conversationId }
        .sortedBy(VoiceAgentRunSnapshot::createdAtMillis)

    fun clear() = repository.clear()

    private fun applyRemoteEvent(
        event: VoiceAgentEvent,
        observedAtMillis: Long = clock.nowMillis()
    ): VoiceAgentRunTransition? {
        val previous = repository.find(event.runId) ?: return null
        if (event.eventId.isBlank() || event.eventId in previous.seenEventIds) return null
        if (previous.state.isTerminal) return null
        if (event.statusSequence > 0L && event.statusSequence < previous.lastStatusSequence) return null
        val seen = (previous.seenEventIds + event.eventId).takeLast(MAX_EVENT_IDS)
        val now = observedAtMillis.coerceAtLeast(previous.updatedAtMillis)
        var firstAcceptance = false
        var firstProgress = false
        var firstPartial = false
        val updated = when (event) {
            is VoiceAgentEvent.RunCreated -> previous
            is VoiceAgentEvent.Accepted -> {
                firstAcceptance = !previous.hasRemoteAcceptance
                previous.copy(
                    state = if (previous.state in setOf(
                            VoiceAgentRunState.CREATED,
                            VoiceAgentRunState.ACCEPTED
                        )
                    ) VoiceAgentRunState.ACCEPTED else previous.state,
                    stage = previous.stage.ifBlank { "accepted" },
                    acceptedAtMillis = previous.acceptedAtMillis.takeIf { it > 0L }
                        ?: event.remoteAtMillis?.takeIf { it > 0L }
                        ?: now
                )
            }
            is VoiceAgentEvent.StageChanged -> previous.copy(
                state = event.state,
                stage = event.stage.take(MAX_STAGE_CHARACTERS)
            )
            is VoiceAgentEvent.Progress -> {
                firstProgress = previous.progressMessage.isBlank()
                previous.copy(
                    state = if (previous.state in setOf(
                            VoiceAgentRunState.CREATED,
                            VoiceAgentRunState.ACCEPTED,
                            VoiceAgentRunState.QUEUED,
                            VoiceAgentRunState.STARTING
                        )
                    ) VoiceAgentRunState.RUNNING else previous.state,
                    progressMessage = visibleText(event.message, MAX_PROGRESS_CHARACTERS),
                    progressPercent = event.percent?.coerceIn(0.0, 100.0)
                )
            }
            is VoiceAgentEvent.PartialResult -> {
                if (event.sequence > 0L && event.sequence <= previous.lastPartialSequence) return null
                val text = visiblePartialText(event.text, MAX_PARTIAL_CHARACTERS)
                if (text.isBlank()) return null
                firstPartial = previous.partialResult.isBlank()
                previous.copy(
                    partialResult = mergePartial(previous.partialResult, text),
                    firstDiscovery = previous.firstDiscovery.ifBlank {
                        text.trim().take(MAX_DISCOVERY_CHARACTERS)
                    },
                    lastPartialSequence = maxOf(previous.lastPartialSequence, event.sequence)
                )
            }
            is VoiceAgentEvent.ApprovalRequired -> previous.copy(
                state = VoiceAgentRunState.WAITING_APPROVAL,
                stage = "waiting_approval",
                approvalId = event.approvalId
            )
            is VoiceAgentEvent.Completed -> previous.copy(
                state = VoiceAgentRunState.COMPLETED,
                stage = "completed",
                resultSummary = visibleText(event.resultSummary, MAX_RESULT_CHARACTERS),
                completedAtMillis = now
            )
            is VoiceAgentEvent.Failed -> previous.copy(
                state = if (event.timedOut) VoiceAgentRunState.TIMED_OUT else VoiceAgentRunState.FAILED,
                stage = if (event.timedOut) "timed_out" else "failed",
                resultSummary = visibleText(event.error, MAX_RESULT_CHARACTERS),
                completedAtMillis = now
            )
            is VoiceAgentEvent.Cancelled -> previous.copy(
                state = VoiceAgentRunState.CANCELLED,
                stage = "cancelled",
                completedAtMillis = now
            )
        }.copy(
            lastStatusSequence = maxOf(previous.lastStatusSequence, event.statusSequence),
            seenEventIds = seen,
            updatedAtMillis = now
        )
        repository.save(updated, event)
        val transition = VoiceAgentRunTransition(
            event = event,
            previous = previous,
            snapshot = updated,
            firstAcceptance = firstAcceptance,
            firstProgress = firstProgress,
            firstPartialResult = firstPartial
        )
        notifyListeners(VoiceAgentRunUpdate(
            snapshot = updated,
            event = event,
            previous = previous,
            firstAcceptance = firstAcceptance,
            firstProgress = firstProgress,
            firstPartialResult = firstPartial
        ))
        return transition
    }

    private fun mapStandardEvent(
        runId: String,
        taskId: String,
        eventId: String,
        statusSequence: Long,
        eventType: String,
        envelope: JSONObject,
        payload: JSONObject
    ): VoiceAgentEvent? {
        val kind = eventType
            .substringAfterLast('.')
            .substringAfterLast('/')
            .replace('-', '_')
        return when {
            kind == "accepted" || kind == "run_accepted" -> VoiceAgentEvent.Accepted(
                runId = runId,
                eventId = eventId,
                statusSequence = statusSequence,
                remoteAtMillis = payload.optLong("remote_at_ms", 0L).takeIf { it > 0L }
                    ?: envelope.optLong("created_at_ms", 0L).takeIf { it > 0L }
            )
            kind in setOf("stage", "stage_changed", "status_changed") -> {
                val stage = payload.optString("stage").trim().ifBlank {
                    payload.optString("status").trim()
                }
                when (val state = voiceRunState(stage)) {
                    VoiceAgentRunState.COMPLETED -> VoiceAgentEvent.Completed(
                        runId, eventId, statusSequence, standardText(payload, "result_summary", "result", "text")
                    )
                    VoiceAgentRunState.FAILED,
                    VoiceAgentRunState.TIMED_OUT -> VoiceAgentEvent.Failed(
                        runId,
                        eventId,
                        statusSequence,
                        standardText(payload, "error", "message", "detail"),
                        timedOut = state == VoiceAgentRunState.TIMED_OUT
                    )
                    VoiceAgentRunState.CANCELLED -> VoiceAgentEvent.Cancelled(runId, eventId, statusSequence)
                    null -> null
                    else -> VoiceAgentEvent.StageChanged(runId, eventId, statusSequence, state, stage)
                }
            }
            kind in setOf("progress", "run_progress", "tool_progress") -> {
                if (!isUserVisible(payload)) return null
                val message = standardText(payload, "message", "title", "detail", "text")
                message.takeIf(String::isNotBlank)?.let {
                    VoiceAgentEvent.Progress(
                        runId,
                        eventId,
                        statusSequence,
                        it,
                        payload.optDouble("percent", Double.NaN).takeUnless(Double::isNaN)
                    )
                }
            }
            kind in setOf("partial", "partial_result", "finding", "discovery", "user_output") -> {
                if (!isUserVisible(payload)) return null
                standardText(payload, "text", "content", "message")
                    .takeIf(String::isNotBlank)
                    ?.let { text ->
                        VoiceAgentEvent.PartialResult(
                            runId,
                            eventId,
                            statusSequence,
                            text,
                            payload.optLong("sequence", statusSequence).coerceAtLeast(0L)
                        )
                    }
            }
            kind in setOf("approval", "approval_required", "permission_required") -> {
                val request = payload.optJSONObject("request") ?: payload
                approvalEvent(runId, taskId, statusSequence, request, eventId)
            }
            kind in setOf("completed", "run_completed", "final") -> VoiceAgentEvent.Completed(
                runId,
                eventId,
                statusSequence,
                standardText(payload, "result_summary", "result", "text", "content")
            )
            kind in setOf("failed", "run_failed", "error") -> VoiceAgentEvent.Failed(
                runId,
                eventId,
                statusSequence,
                standardText(payload, "error", "message", "detail"),
                timedOut = false
            )
            kind in setOf("timed_out", "timeout") -> VoiceAgentEvent.Failed(
                runId,
                eventId,
                statusSequence,
                standardText(payload, "error", "message", "detail"),
                timedOut = true
            )
            kind in setOf("cancelled", "canceled", "run_cancelled") ->
                VoiceAgentEvent.Cancelled(runId, eventId, statusSequence)
            else -> null
        }
    }

    private fun approvalEvent(
        runId: String,
        taskId: String,
        statusSequence: Long,
        approval: JSONObject,
        eventId: String = ""
    ): VoiceAgentEvent.ApprovalRequired? {
        val approvalId = approval.optString("approval_id").trim()
            .ifBlank { approval.optString("request_id").trim() }
        if (approvalId.isBlank()) return null
        return VoiceAgentEvent.ApprovalRequired(
            runId = runId,
            eventId = eventId.ifBlank { "approval:$taskId:$approvalId" },
            statusSequence = statusSequence,
            approvalId = approvalId
        )
    }

    private fun voiceRunState(value: String): VoiceAgentRunState? = when (
        value.trim().lowercase().replace('-', '_')
    ) {
        "created" -> VoiceAgentRunState.CREATED
        "accepted" -> VoiceAgentRunState.ACCEPTED
        "queued" -> VoiceAgentRunState.QUEUED
        "starting" -> VoiceAgentRunState.STARTING
        "recovering" -> VoiceAgentRunState.STARTING
        "running", "planning", "executing" -> VoiceAgentRunState.RUNNING
        "waiting_input", "waiting_for_input", "waiting_for_user" -> VoiceAgentRunState.WAITING_INPUT
        "waiting_approval", "approval_required", "permission_required" -> VoiceAgentRunState.WAITING_APPROVAL
        "cancelling", "canceling" -> VoiceAgentRunState.CANCELLING
        "completed", "complete" -> VoiceAgentRunState.COMPLETED
        "failed", "error" -> VoiceAgentRunState.FAILED
        "timed_out", "timeout" -> VoiceAgentRunState.TIMED_OUT
        "cancelled", "canceled" -> VoiceAgentRunState.CANCELLED
        else -> null
    }

    private fun standardText(payload: JSONObject, vararg keys: String): String = keys.asSequence()
        .mapNotNull { key -> payload.opt(key).takeUnless { it == null || it == JSONObject.NULL } }
        .map { value ->
            when (value) {
                is String -> value
                is JSONObject -> value.optString("summary").ifBlank { value.optString("text") }
                    .ifBlank { value.toString() }
                else -> value.toString()
            }
        }
        .firstOrNull(String::isNotBlank)
        .orEmpty()

    private fun statusEvent(
        runId: String,
        eventId: String,
        statusSequence: Long,
        status: String,
        envelope: JSONObject
    ): VoiceAgentEvent? = when (status) {
        "accepted" -> VoiceAgentEvent.Accepted(
            runId,
            eventId,
            statusSequence,
            envelope.optLong("updated_at", 0L).takeIf { it > 0L }
        )
        "queued" -> VoiceAgentEvent.StageChanged(runId, eventId, statusSequence, VoiceAgentRunState.QUEUED, "queued")
        "starting" -> VoiceAgentEvent.StageChanged(runId, eventId, statusSequence, VoiceAgentRunState.STARTING, "starting")
        "recovering" -> VoiceAgentEvent.StageChanged(runId, eventId, statusSequence, VoiceAgentRunState.STARTING, "recovering")
        "running" -> VoiceAgentEvent.StageChanged(
            runId,
            eventId,
            statusSequence,
            VoiceAgentRunState.RUNNING,
            visibleText(envelope.optString("current_step"), MAX_STAGE_CHARACTERS).ifBlank { "running" }
        )
        "waiting_input" -> VoiceAgentEvent.StageChanged(
            runId, eventId, statusSequence, VoiceAgentRunState.WAITING_INPUT, "waiting_input"
        )
        "waiting_approval" -> VoiceAgentEvent.StageChanged(
            runId, eventId, statusSequence, VoiceAgentRunState.WAITING_APPROVAL, "waiting_approval"
        )
        "completed" -> VoiceAgentEvent.Completed(
            runId,
            eventId,
            statusSequence,
            envelope.optString("result_summary")
        )
        "failed", "not_found" -> VoiceAgentEvent.Failed(
            runId,
            eventId,
            statusSequence,
            envelope.optString("error"),
            timedOut = false
        )
        "timed_out" -> VoiceAgentEvent.Failed(
            runId,
            eventId,
            statusSequence,
            envelope.optString("error"),
            timedOut = true
        )
        "cancelled" -> VoiceAgentEvent.Cancelled(runId, eventId, statusSequence)
        else -> null
    }

    private fun mapProgressEvent(
        runId: String,
        taskId: String,
        statusSequence: Long,
        progress: JSONObject
    ): VoiceAgentEvent? {
        if (!isUserVisible(progress)) return null
        val message = listOf(
            progress.optString("title"),
            progress.optString("detail"),
            progress.optString("message"),
            progress.optString("text")
        ).firstOrNull { it.isNotBlank() }.orEmpty()
        if (message.isBlank()) return null
        val eventId = progress.optString("event_id").trim().ifBlank {
            "progress:$taskId:$statusSequence:${message.hashCode()}"
        }
        val kind = progress.optString("kind").trim().lowercase()
        val sequence = progress.optLong("sequence", statusSequence).coerceAtLeast(0L)
        return if (kind in PARTIAL_RESULT_KINDS || progress.optBoolean("partial_result", false)) {
            VoiceAgentEvent.PartialResult(runId, eventId, statusSequence, message, sequence)
        } else {
            VoiceAgentEvent.Progress(
                runId,
                eventId,
                statusSequence,
                message,
                progress.optDouble("percent", Double.NaN).takeUnless(Double::isNaN)
            )
        }
    }

    private fun mapPartialResult(
        runId: String,
        taskId: String,
        statusSequence: Long,
        partial: JSONObject
    ): VoiceAgentEvent? {
        if (!isUserVisible(partial)) return null
        val text = partial.optString("text").ifBlank { partial.optString("content") }
        if (text.isBlank()) return null
        val sequence = partial.optLong("sequence", statusSequence).coerceAtLeast(0L)
        return VoiceAgentEvent.PartialResult(
            runId = runId,
            eventId = partial.optString("event_id").ifBlank {
                "partial:$taskId:$sequence:${text.hashCode()}"
            },
            statusSequence = statusSequence,
            text = text,
            sequence = sequence
        )
    }

    private fun recoverSnapshot(
        envelope: JSONObject,
        taskId: String,
        sourceMessageId: Long
    ): VoiceAgentRunSnapshot? {
        val payload = envelope.optJSONObject("payload") ?: JSONObject()
        val conversationId = envelope.optString("conversation_id").trim().ifBlank {
            payload.optString("conversation_id").trim()
        }
        val turnId = envelope.optString("turn_id").trim().ifBlank {
            payload.optString("turn_id").trim()
        }
        if (taskId.isBlank() || conversationId.isBlank() || turnId.isBlank() || sourceMessageId <= 0L) return null
        val now = clock.nowMillis()
        val idempotencyKey = "recovered:$conversationId:$turnId:$taskId"
        return VoiceAgentRunSnapshot(
            runId = stableRunId(idempotencyKey),
            conversationId = conversationId,
            turnId = turnId,
            taskId = taskId,
            sourceMessageId = sourceMessageId,
            contactId = envelope.optString("contact_id").ifBlank { payload.optString("contact_id") },
            agentId = envelope.optString("agent_id").ifBlank { payload.optString("agent_id") },
            agentName = envelope.optString("agent_name").ifBlank { payload.optString("agent_name") },
            deviceId = envelope.optString("source_device_id")
                .ifBlank { envelope.optString("desktop_id") }
                .ifBlank { payload.optString("device_id") },
            goal = "",
            idempotencyKey = idempotencyKey,
            traceId = envelope.optString("trace_id"),
            state = VoiceAgentRunState.CREATED,
            createdAtMillis = envelope.optLong("created_at_ms", 0L).takeIf { it > 0L }
                ?: envelope.optLong("created_at", now).takeIf { it > 0L }
                ?: now,
            updatedAtMillis = now
        ).also { snapshot ->
            repository.save(
                snapshot,
                VoiceAgentEvent.RunCreated(
                    runId = snapshot.runId,
                    eventId = "voice-run-recovered:${snapshot.runId}"
                )
            )
        }
    }

    private fun stableRunId(idempotencyKey: String): String = UUID.nameUUIDFromBytes(
        "voice-agent-run\u001f$idempotencyKey".toByteArray(Charsets.UTF_8)
    ).toString()

    private fun localCreatedEventId(runId: String): String = "voice-run-created:$runId"

    private fun notifyListeners(update: VoiceAgentRunUpdate) {
        listeners.forEach { listener -> runCatching { listener.onRunUpdated(update) } }
    }

    private fun mergePartial(previous: String, incoming: String): String {
        if (previous.isBlank()) return incoming.trimStart()
        if (incoming == previous || previous.endsWith(incoming)) return previous
        if (incoming.startsWith(previous)) return incoming.take(MAX_PARTIAL_CHARACTERS)
        val merged = if (previous.lastOrNull()?.isWhitespace() == true &&
            incoming.firstOrNull()?.isWhitespace() == true
        ) {
            previous + incoming.trimStart()
        } else {
            previous + incoming
        }
        return merged.takeLast(MAX_PARTIAL_CHARACTERS)
    }

    private fun isUserVisible(payload: JSONObject): Boolean {
        if (payload.optBoolean("private", false)) return false
        val visibility = payload.optString("visibility").trim().lowercase()
        if (visibility in setOf("private", "internal", "hidden")) return false
        val sensitivity = payload.optString("sensitivity").trim().lowercase()
        if (sensitivity in setOf("private", "secret", "credential")) return false
        val kind = payload.optString("kind").trim().lowercase()
        return kind !in PRIVATE_EVENT_KINDS
    }

    private fun visibleText(value: String, limit: Int): String = value
        .replace(PRIVATE_REASONING_BLOCK, " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .take(limit)

    private fun visiblePartialText(value: String, limit: Int): String = value
        .replace(PRIVATE_REASONING_BLOCK, " ")
        .replace(Regex("\\s+"), " ")
        .take(limit)

    companion object {
        @Volatile private var shared: VoiceAgentRunBridge? = null

        fun get(context: Context): VoiceAgentRunBridge = shared ?: synchronized(this) {
            shared ?: VoiceAgentRunBridge(
                repository = AgentRunEventVoiceAgentRunRepository(
                    AgentRunEventStore(context.applicationContext)
                )
            ).also { shared = it }
        }

        private const val MAX_GOAL_CHARACTERS = 2_000
        private const val MAX_STAGE_CHARACTERS = 240
        private const val MAX_PROGRESS_CHARACTERS = 1_000
        private const val MAX_PARTIAL_CHARACTERS = 8_000
        private const val MAX_DISCOVERY_CHARACTERS = 1_000
        private const val MAX_RESULT_CHARACTERS = 8_000
        private const val MAX_EVENT_IDS = 96
        private val PARTIAL_RESULT_KINDS = setOf("partial_result", "finding", "discovery", "user_output")
        private val PRIVATE_EVENT_KINDS = setOf(
            "reasoning",
            "chain_of_thought",
            "private_reasoning",
            "analysis_private",
            "internal"
        )
        private val PRIVATE_REASONING_BLOCK = Regex(
            "<\\s*(think|analysis|reasoning)\\s*>.*?<\\s*/\\s*\\1\\s*>",
            setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
        )
    }
}

private fun VoiceAgentEvent.toControlEvent(snapshot: VoiceAgentRunSnapshot): AgentRunControlEvent =
    AgentRunControlEvent(
        eventId = eventId,
        conversationId = snapshot.conversationId,
        messageId = snapshot.sourceMessageId.toString(),
        taskId = snapshot.taskId,
        runId = snapshot.runId,
        agentId = snapshot.agentId,
        deviceId = snapshot.deviceId,
        type = controlEventType(),
        sequence = 0L,
        timestampMillis = snapshot.updatedAtMillis,
        payload = eventPayload() + mapOf("remote_status_sequence" to statusSequence)
    )

private fun VoiceAgentEvent.controlEventType(): AgentRunControlEventType = when (this) {
    is VoiceAgentEvent.RunCreated -> AgentRunControlEventType.RUN_CREATED
    is VoiceAgentEvent.Accepted -> AgentRunControlEventType.AGENT_CONNECTED
    is VoiceAgentEvent.StageChanged -> when (state) {
        VoiceAgentRunState.QUEUED -> AgentRunControlEventType.RUN_QUEUED
        VoiceAgentRunState.STARTING -> if (stage == "recovering") {
            AgentRunControlEventType.RUN_RECOVERED
        } else {
            AgentRunControlEventType.RUN_STARTED
        }
        VoiceAgentRunState.RUNNING -> AgentRunControlEventType.STEP_STARTED
        VoiceAgentRunState.WAITING_INPUT -> AgentRunControlEventType.WAITING_FOR_USER
        VoiceAgentRunState.WAITING_APPROVAL -> AgentRunControlEventType.TOOL_PERMISSION_REQUIRED
        VoiceAgentRunState.CANCELLING -> AgentRunControlEventType.PAUSED
        VoiceAgentRunState.COMPLETED -> AgentRunControlEventType.RUN_COMPLETED
        VoiceAgentRunState.FAILED,
        VoiceAgentRunState.TIMED_OUT -> AgentRunControlEventType.RUN_FAILED
        VoiceAgentRunState.CANCELLED -> AgentRunControlEventType.RUN_CANCELLED
        VoiceAgentRunState.CREATED -> AgentRunControlEventType.RUN_CREATED
        VoiceAgentRunState.ACCEPTED -> AgentRunControlEventType.AGENT_CONNECTED
    }
    is VoiceAgentEvent.Progress,
    is VoiceAgentEvent.PartialResult -> AgentRunControlEventType.TOOL_PROGRESS
    is VoiceAgentEvent.ApprovalRequired -> AgentRunControlEventType.TOOL_PERMISSION_REQUIRED
    is VoiceAgentEvent.Completed -> AgentRunControlEventType.RUN_COMPLETED
    is VoiceAgentEvent.Failed -> AgentRunControlEventType.RUN_FAILED
    is VoiceAgentEvent.Cancelled -> AgentRunControlEventType.RUN_CANCELLED
}

private fun VoiceAgentEvent.eventPayload(): AgentNativeJsonObject = when (this) {
    is VoiceAgentEvent.RunCreated -> mapOf("status" to "created")
    is VoiceAgentEvent.Accepted -> mapOf("status" to "accepted")
    is VoiceAgentEvent.StageChanged -> mapOf("status" to state.name.lowercase(), "stage" to stage)
    is VoiceAgentEvent.Progress -> mapOf(
        "status" to "progress",
        "message" to message,
        "percent" to percent
    )
    is VoiceAgentEvent.PartialResult -> mapOf(
        "status" to "partial_result",
        "content" to text,
        "partial_sequence" to sequence
    )
    is VoiceAgentEvent.ApprovalRequired -> mapOf(
        "status" to "waiting_approval",
        "approval_id" to approvalId
    )
    is VoiceAgentEvent.Completed -> mapOf("status" to "completed", "result" to resultSummary)
    is VoiceAgentEvent.Failed -> mapOf(
        "status" to if (timedOut) "timed_out" else "failed",
        "error" to error
    )
    is VoiceAgentEvent.Cancelled -> mapOf("status" to "cancelled")
}

private fun VoiceAgentRunSnapshot.toJson(): JSONObject = JSONObject()
    .put("run_id", runId)
    .put("conversation_id", conversationId)
    .put("turn_id", turnId)
    .put("task_id", taskId)
    .put("source_message_id", sourceMessageId)
    .put("contact_id", contactId)
    .put("agent_id", agentId)
    .put("agent_name", agentName)
    .put("device_id", deviceId)
    .put("goal", goal)
    .put("idempotency_key", idempotencyKey)
    .put("trace_id", traceId)
    .put("state", state.name)
    .put("stage", stage)
    .put("progress_message", progressMessage)
    .put("progress_percent", progressPercent)
    .put("partial_result", partialResult)
    .put("first_discovery", firstDiscovery)
    .put("result_summary", resultSummary)
    .put("approval_id", approvalId)
    .put("last_status_sequence", lastStatusSequence)
    .put("last_partial_sequence", lastPartialSequence)
    .put("seen_event_ids", JSONArray(seenEventIds))
    .put("created_at_millis", createdAtMillis)
    .put("accepted_at_millis", acceptedAtMillis)
    .put("updated_at_millis", updatedAtMillis)
    .put("completed_at_millis", completedAtMillis)

private fun JSONObject.toVoiceAgentRunSnapshot(): VoiceAgentRunSnapshot? = runCatching {
    VoiceAgentRunSnapshot(
        runId = getString("run_id"),
        conversationId = getString("conversation_id"),
        turnId = getString("turn_id"),
        taskId = getString("task_id"),
        sourceMessageId = getLong("source_message_id"),
        contactId = optString("contact_id"),
        agentId = optString("agent_id"),
        agentName = optString("agent_name"),
        deviceId = optString("device_id"),
        goal = optString("goal"),
        idempotencyKey = getString("idempotency_key"),
        traceId = optString("trace_id"),
        state = runCatching { VoiceAgentRunState.valueOf(getString("state")) }
            .getOrDefault(VoiceAgentRunState.CREATED),
        stage = optString("stage"),
        progressMessage = optString("progress_message"),
        progressPercent = optDouble("progress_percent", Double.NaN).takeUnless(Double::isNaN),
        partialResult = optString("partial_result"),
        firstDiscovery = optString("first_discovery"),
        resultSummary = optString("result_summary"),
        approvalId = optString("approval_id"),
        lastStatusSequence = optLong("last_status_sequence"),
        lastPartialSequence = optLong("last_partial_sequence"),
        seenEventIds = buildList {
            val source = optJSONArray("seen_event_ids") ?: JSONArray()
            for (index in 0 until source.length()) source.optString(index).takeIf(String::isNotBlank)?.let(::add)
        },
        createdAtMillis = getLong("created_at_millis"),
        acceptedAtMillis = optLong("accepted_at_millis"),
        updatedAtMillis = getLong("updated_at_millis"),
        completedAtMillis = optLong("completed_at_millis")
    )
}.getOrNull()
