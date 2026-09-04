package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.LocalWhisperException
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

enum class WhisperDecodePriority(val rank: Int) {
    CURRENT_FINAL(0),
    CURRENT_PARTIAL(1),
    ACCURACY_REVIEW(2),
    SECOND_PASS(3),
    BENCHMARK(4),
    BACKGROUND(5)
}

data class ScheduledWhisperDecode(
    val requestId: String,
    val voiceSessionId: String,
    val revision: Int,
    val modelProfileId: String,
    val pcm16: ShortArray,
    val sampleRateHz: Int = 16_000,
    val language: String = "zh",
    val mode: WhisperExecutionMode,
    val priority: WhisperDecodePriority,
    val windowStartSample: Long = 0L,
    val windowEndSampleExclusive: Long = windowStartSample + pcm16.size
) {
    init {
        require(requestId.isNotBlank())
        require(voiceSessionId.isNotBlank())
        require(revision > 0)
        require(modelProfileId.isNotBlank())
        require(pcm16.isNotEmpty())
        require(sampleRateHz == 16_000)
        require(windowStartSample >= 0L)
        require(windowEndSampleExclusive >= windowStartSample + pcm16.size)
    }

    val isFinal: Boolean
        get() = priority == WhisperDecodePriority.CURRENT_FINAL
}

enum class WhisperDecodeDropReason {
    SUPERSEDED_BY_FINAL,
    SESSION_CANCELLED,
    QUEUE_CAPACITY,
    SCHEDULER_CLOSED,
    NATIVE_ABORTED
}

sealed interface ScheduledWhisperResult {
    val request: ScheduledWhisperDecode

    data class Completed(
        override val request: ScheduledWhisperDecode,
        val native: NativeWhisperResult
    ) : ScheduledWhisperResult

    data class Dropped(
        override val request: ScheduledWhisperDecode,
        val reason: WhisperDecodeDropReason
    ) : ScheduledWhisperResult

    data class Failed(
        override val request: ScheduledWhisperDecode,
        val error: Throwable
    ) : ScheduledWhisperResult
}

data class DecodeQueueSnapshot(
    val activeRequestId: String? = null,
    val activeSessionId: String? = null,
    val activeMode: WhisperExecutionMode? = null,
    val queued: Int = 0,
    val queuedPartials: Int = 0,
    val dropped: Long = 0L
)

interface WhisperDecodeScheduler : AutoCloseable {
    suspend fun submit(request: ScheduledWhisperDecode): ScheduledWhisperResult
    fun cancelSession(sessionId: String)
    fun queueSnapshot(): DecodeQueueSnapshot
    override fun close()
}

class DefaultWhisperDecodeScheduler(
    parentScope: CoroutineScope,
    private val maxQueueSize: Int = 8,
    private val decoder: suspend (ScheduledWhisperDecode) -> NativeWhisperResult,
    private val abortActive: (AbortReason) -> Unit
) : WhisperDecodeScheduler {
    private data class Queued(
        val sequence: Long,
        val request: ScheduledWhisperDecode,
        val result: CompletableDeferred<ScheduledWhisperResult>
    )

    private val lock = Any()
    private val sequence = AtomicLong(0L)
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private val job = SupervisorJob(parentScope.coroutineContext[Job])
    private val scope = CoroutineScope(parentScope.coroutineContext + job)
    private val pending = mutableListOf<Queued>()
    private var active: Queued? = null
    private var closed = false
    private var droppedCount = 0L

    init {
        require(maxQueueSize in 1..64)
        scope.launch { workerLoop() }
    }

    override suspend fun submit(request: ScheduledWhisperDecode): ScheduledWhisperResult {
        val queued = Queued(sequence.getAndIncrement(), request, CompletableDeferred())
        val dropped = mutableListOf<Pair<Queued, WhisperDecodeDropReason>>()
        var abortCurrent = false
        synchronized(lock) {
            if (closed) {
                return ScheduledWhisperResult.Dropped(request, WhisperDecodeDropReason.SCHEDULER_CLOSED)
            }
            if (request.isFinal) {
                pending.filterTo(mutableListOf()) {
                    it.request.voiceSessionId == request.voiceSessionId &&
                        it.request.mode == WhisperExecutionMode.REALTIME_PARTIAL
                }.forEach {
                    pending.remove(it)
                    dropped += it to WhisperDecodeDropReason.SUPERSEDED_BY_FINAL
                }
                abortCurrent = active?.request?.mode == WhisperExecutionMode.REALTIME_PARTIAL
            }
            if (pending.size >= maxQueueSize) {
                val replaceable = pending.maxWithOrNull(
                    compareBy<Queued> { it.request.priority.rank }.thenBy { it.sequence }
                )
                if (replaceable != null && replaceable.request.priority.rank > request.priority.rank) {
                    pending.remove(replaceable)
                    dropped += replaceable to WhisperDecodeDropReason.QUEUE_CAPACITY
                } else {
                    droppedCount += 1L
                    return ScheduledWhisperResult.Dropped(request, WhisperDecodeDropReason.QUEUE_CAPACITY)
                }
            }
            pending += queued
            droppedCount += dropped.size
        }
        dropped.forEach { (item, reason) -> item.result.complete(ScheduledWhisperResult.Dropped(item.request, reason)) }
        if (abortCurrent) abortActive(AbortReason.UPSTREAM_FINAL_SELECTED)
        wake.trySend(Unit)
        return queued.result.await()
    }

    override fun cancelSession(sessionId: String) {
        if (sessionId.isBlank()) return
        val cancelled = mutableListOf<Queued>()
        var abortCurrent = false
        synchronized(lock) {
            pending.filterTo(cancelled) { it.request.voiceSessionId == sessionId }
            pending.removeAll(cancelled.toSet())
            abortCurrent = active?.request?.voiceSessionId == sessionId
            droppedCount += cancelled.size
        }
        cancelled.forEach {
            it.result.complete(ScheduledWhisperResult.Dropped(it.request, WhisperDecodeDropReason.SESSION_CANCELLED))
        }
        if (abortCurrent) abortActive(AbortReason.SESSION_CLOSED)
    }

    override fun queueSnapshot(): DecodeQueueSnapshot = synchronized(lock) {
        DecodeQueueSnapshot(
            activeRequestId = active?.request?.requestId,
            activeSessionId = active?.request?.voiceSessionId,
            activeMode = active?.request?.mode,
            queued = pending.size,
            queuedPartials = pending.count { it.request.mode == WhisperExecutionMode.REALTIME_PARTIAL },
            dropped = droppedCount
        )
    }

    override fun close() {
        val abandoned = mutableListOf<Queued>()
        var running: Queued? = null
        synchronized(lock) {
            if (closed) return
            closed = true
            abandoned += pending
            pending.clear()
            running = active
            active = null
            droppedCount += abandoned.size + if (running == null) 0 else 1
        }
        abandoned.forEach {
            it.result.complete(ScheduledWhisperResult.Dropped(it.request, WhisperDecodeDropReason.SCHEDULER_CLOSED))
        }
        running?.let {
            it.result.complete(ScheduledWhisperResult.Dropped(it.request, WhisperDecodeDropReason.SCHEDULER_CLOSED))
            abortActive(AbortReason.SESSION_CLOSED)
        }
        wake.close()
        job.cancel()
    }

    private suspend fun workerLoop() {
        for (ignored in wake) {
            while (scope.isActive) {
                val next = synchronized(lock) {
                    pending.minWithOrNull(
                        compareBy<Queued> { it.request.priority.rank }.thenBy { it.sequence }
                    )?.also {
                        pending.remove(it)
                        active = it
                    }
                } ?: break
                val result = runCatching { decoder(next.request) }.fold(
                    onSuccess = { native ->
                        if (native.code == NativeWhisperCode.ABORTED) {
                            ScheduledWhisperResult.Dropped(next.request, WhisperDecodeDropReason.NATIVE_ABORTED)
                        } else if (native.successful) {
                            ScheduledWhisperResult.Completed(next.request, native)
                        } else {
                            ScheduledWhisperResult.Failed(
                                next.request,
                                LocalWhisperException(native.code, native.message ?: "Whisper decode failed")
                            )
                        }
                    },
                    onFailure = { ScheduledWhisperResult.Failed(next.request, it) }
                )
                synchronized(lock) {
                    if (active === next) active = null
                }
                next.result.complete(result)
            }
        }
    }
}
