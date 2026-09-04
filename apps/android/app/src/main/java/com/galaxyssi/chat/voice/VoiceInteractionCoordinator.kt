package com.galaxyssi.chat.voice

import android.os.SystemClock
import java.util.UUID

fun interface VoiceElapsedClock {
    fun nowNanos(): Long
}

class VoiceInteractionCoordinator(
    private val elapsedClock: VoiceElapsedClock = VoiceElapsedClock(SystemClock::elapsedRealtimeNanos),
    private val sessionIdFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private val observers = linkedMapOf<String, (VoiceInteractionState) -> Unit>()
    private val emittedCommandKeys = LinkedHashSet<String>()
    private var currentConfig: VoiceSessionConfig? = null
    private var state = VoiceInteractionState()

    @Synchronized
    fun snapshot(): VoiceInteractionState = state

    @Synchronized
    fun config(): VoiceSessionConfig? = currentConfig

    fun observe(observer: (VoiceInteractionState) -> Unit): String {
        val observerId = UUID.randomUUID().toString()
        val snapshot = synchronized(this) {
            observers[observerId] = observer
            state
        }
        runCatching { observer(snapshot) }
        return observerId
    }

    @Synchronized
    fun removeObserver(observerId: String) {
        observers.remove(observerId)
    }

    fun begin(config: VoiceSessionConfig): VoiceInteractionTransition {
        var notification: Pair<VoiceInteractionState, List<(VoiceInteractionState) -> Unit>>? = null
        val transition = synchronized(this) {
            val previous = state
            if (!state.phase.isTerminal && state.phase != VoiceInteractionPhase.IDLE) {
                return@synchronized VoiceInteractionTransition(previous, previous, accepted = false)
            }
            val sessionId = config.requestedSessionId.trim().ifBlank(sessionIdFactory)
            if (previous.sessionId == sessionId && previous.phase.isTerminal) {
                return@synchronized VoiceInteractionTransition(previous, previous, accepted = false)
            }
            val now = elapsedClock.nowNanos().coerceAtLeast(0L)
            currentConfig = config.copy(requestedSessionId = sessionId)
            state = VoiceInteractionState(
                sessionId = sessionId,
                phase = VoiceInteractionPhase.PREPARING,
                revision = previous.revision + 1L,
                createdAtElapsedNs = now,
                updatedAtElapsedNs = now
            )
            trimCommandLedger()
            notification = state to observers.values.toList()
            VoiceInteractionTransition(previous, state)
        }
        notification?.let { update ->
            update.second.forEach { observer -> runCatching { observer(update.first) } }
        }
        return transition
    }

    fun dispatch(event: VoiceInteractionEvent): VoiceInteractionTransition {
        var notification: Pair<VoiceInteractionState, List<(VoiceInteractionState) -> Unit>>? = null
        val transition = synchronized(this) {
            val previous = state
            if (event.sessionId.isBlank() || event.sessionId != previous.sessionId ||
                (previous.phase.isTerminal && event !is VoiceInteractionEvent.TranscriptCorrected)
            ) {
                return@synchronized VoiceInteractionTransition(previous, previous, accepted = false)
            }
            val reduced = reduce(previous, event)
            if (reduced.first == previous && reduced.second.isEmpty()) {
                return@synchronized VoiceInteractionTransition(previous, previous, accepted = false)
            }
            state = reduced.first.copy(
                revision = previous.revision + 1L,
                updatedAtElapsedNs = elapsedClock.nowNanos().coerceAtLeast(previous.updatedAtElapsedNs)
            )
            val commands = reduced.second.filter { emittedCommandKeys.add(it.idempotencyKey) }
            trimCommandLedger()
            notification = state to observers.values.toList()
            VoiceInteractionTransition(previous, state, commands)
        }
        notification?.let { update ->
            update.second.forEach { observer -> runCatching { observer(update.first) } }
        }
        return transition
    }

    fun cancel(reasonCode: String = "user_cancelled"): VoiceInteractionTransition {
        val current = snapshot()
        if (current.sessionId.isBlank()) {
            return VoiceInteractionTransition(current, current, accepted = false)
        }
        return dispatch(VoiceInteractionEvent.Cancelled(current.sessionId, reasonCode))
    }

    @Synchronized
    fun result(): VoiceSessionResult? {
        if (!state.phase.isTerminal || state.sessionId.isBlank()) return null
        return VoiceSessionResult(
            sessionId = state.sessionId,
            completed = state.phase == VoiceInteractionPhase.COMPLETED,
            cancelled = state.phase == VoiceInteractionPhase.CANCELLED,
            route = state.route,
            failure = state.failure,
            finalTranscriptRevision = state.finalTranscriptRevision
        )
    }

    private fun reduce(
        previous: VoiceInteractionState,
        event: VoiceInteractionEvent
    ): Pair<VoiceInteractionState, List<VoiceInteractionCommand>> = when (event) {
        is VoiceInteractionEvent.CapturePrepared -> when (previous.phase) {
            VoiceInteractionPhase.PREPARING -> previous.copy(phase = VoiceInteractionPhase.LISTENING) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.AudioLevel -> previous to emptyList()
        is VoiceInteractionEvent.SpeechStarted -> when (previous.phase) {
            VoiceInteractionPhase.PREPARING,
            VoiceInteractionPhase.LISTENING -> previous.copy(phase = VoiceInteractionPhase.LISTENING) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.SpeechEnded -> when (previous.phase) {
            VoiceInteractionPhase.LISTENING -> previous.copy(phase = VoiceInteractionPhase.ENDPOINTING) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.FinalizationStarted -> when (previous.phase) {
            VoiceInteractionPhase.LISTENING,
            VoiceInteractionPhase.ENDPOINTING -> previous.copy(phase = VoiceInteractionPhase.FINALIZING_ASR) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.TranscriptPartial -> when (previous.phase) {
            VoiceInteractionPhase.LISTENING,
            VoiceInteractionPhase.ENDPOINTING,
            VoiceInteractionPhase.FINALIZING_ASR -> previous.copy(
                partialText = event.value.text,
                asrProvider = event.value.provider.takeIf(String::isNotBlank) ?: previous.asrProvider,
                modelProfileId = event.value.modelProfileId.takeIf(String::isNotBlank)
                    ?: previous.modelProfileId
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.TranscriptStable -> when (previous.phase) {
            VoiceInteractionPhase.LISTENING,
            VoiceInteractionPhase.ENDPOINTING,
            VoiceInteractionPhase.FINALIZING_ASR -> previous.copy(
                stableText = event.value.text,
                asrProvider = event.value.provider.takeIf(String::isNotBlank) ?: previous.asrProvider,
                modelProfileId = event.value.modelProfileId.takeIf(String::isNotBlank)
                    ?: previous.modelProfileId
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.TranscriptFinal -> {
            val normalized = event.value.text.trim()
            when {
                normalized.isBlank() -> previous to emptyList()
                previous.finalText == null && previous.phase in setOf(
                    VoiceInteractionPhase.LISTENING,
                    VoiceInteractionPhase.ENDPOINTING,
                    VoiceInteractionPhase.FINALIZING_ASR
                ) -> {
                    val key = "${previous.sessionId}:route:${event.value.revision}"
                    previous.copy(
                        phase = VoiceInteractionPhase.ROUTING,
                        partialText = "",
                        stableText = normalized,
                        finalText = normalized,
                        finalTranscriptRevision = event.value.revision,
                        asrProvider = event.value.provider.takeIf(String::isNotBlank) ?: previous.asrProvider,
                        modelProfileId = event.value.modelProfileId.takeIf(String::isNotBlank)
                            ?: previous.modelProfileId
                    ) to listOf(
                        VoiceInteractionCommand.RouteFinalTranscript(
                            previous.sessionId,
                            event.value.copy(text = normalized),
                            key
                        )
                    )
                }
                previous.finalText != normalized -> previous.copy(correctedText = normalized) to emptyList()
                else -> previous to emptyList()
            }
        }
        is VoiceInteractionEvent.TranscriptCorrected -> {
            val corrected = event.corrected.text.trim()
            if (corrected.isBlank() || corrected == previous.correctedText) {
                previous to emptyList()
            } else {
                previous.copy(correctedText = corrected) to emptyList()
            }
        }
        is VoiceInteractionEvent.RouteSelected -> when (previous.phase) {
            VoiceInteractionPhase.ROUTING -> previous.copy(
                route = event.decision,
                phase = when (event.decision.kind) {
                    VoiceRouteKind.LOCAL_ACTION -> VoiceInteractionPhase.EXECUTING_LOCAL_ACTION
                    VoiceRouteKind.CLOUD_MODEL -> VoiceInteractionPhase.WAITING_MODEL_FIRST_TOKEN
                    VoiceRouteKind.REMOTE_AGENT -> VoiceInteractionPhase.STARTING_AGENT
                }
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.LocalActionCompleted -> when (previous.phase) {
            VoiceInteractionPhase.EXECUTING_LOCAL_ACTION -> previous.copy(
                phase = VoiceInteractionPhase.COMPLETED,
                canInterrupt = false
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.ModelDelta -> when (previous.phase) {
            VoiceInteractionPhase.WAITING_MODEL_FIRST_TOKEN,
            VoiceInteractionPhase.STREAMING_MODEL_TEXT -> previous.copy(
                phase = VoiceInteractionPhase.STREAMING_MODEL_TEXT
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.AgentRunCreated -> when (previous.phase) {
            VoiceInteractionPhase.STARTING_AGENT -> previous.copy(
                phase = VoiceInteractionPhase.COMPLETED,
                agentRunId = event.runId.takeIf(String::isNotBlank) ?: previous.agentRunId,
                canInterrupt = false
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.AgentAccepted -> when (previous.phase) {
            VoiceInteractionPhase.STARTING_AGENT,
            VoiceInteractionPhase.AGENT_RUNNING -> previous.copy(
                phase = VoiceInteractionPhase.AGENT_RUNNING,
                agentRunId = event.runId.takeIf(String::isNotBlank) ?: previous.agentRunId
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.AgentProgress -> when (previous.phase) {
            VoiceInteractionPhase.STARTING_AGENT,
            VoiceInteractionPhase.AGENT_RUNNING -> previous.copy(
                phase = VoiceInteractionPhase.AGENT_RUNNING,
                agentRunId = event.runId.takeIf(String::isNotBlank) ?: previous.agentRunId
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.PlaybackStarted -> when (previous.phase) {
            VoiceInteractionPhase.WAITING_MODEL_FIRST_TOKEN,
            VoiceInteractionPhase.STREAMING_MODEL_TEXT,
            VoiceInteractionPhase.AGENT_RUNNING -> previous.copy(
                phase = VoiceInteractionPhase.PLAYING_TTS
            ) to emptyList()
            else -> previous to emptyList()
        }
        is VoiceInteractionEvent.Completed -> previous.copy(
            phase = VoiceInteractionPhase.COMPLETED,
            canInterrupt = false
        ) to emptyList()
        is VoiceInteractionEvent.Cancelled -> previous.copy(
            phase = VoiceInteractionPhase.CANCELLED,
            canInterrupt = false
        ) to listOf(
            VoiceInteractionCommand.CancelLegacyWork(
                previous.sessionId,
                event.reasonCode,
                "${previous.sessionId}:cancel"
            )
        )
        is VoiceInteractionEvent.Failed -> previous.copy(
            phase = VoiceInteractionPhase.FAILED,
            canInterrupt = false,
            failure = event.failure
        ) to emptyList()
    }

    @Synchronized
    private fun trimCommandLedger() {
        if (emittedCommandKeys.size <= 2_048) return
        val iterator = emittedCommandKeys.iterator()
        repeat(512) {
            if (iterator.hasNext()) {
                iterator.next()
                iterator.remove()
            }
        }
    }
}

object VoiceInteractionCoordinatorRegistry {
    val coordinator: VoiceInteractionCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        VoiceInteractionCoordinator()
    }
}
