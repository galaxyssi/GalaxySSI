package com.signalasi.chat.voice.tts

import com.signalasi.chat.voice.modelstream.CommittedSpeechChunk
import java.util.ArrayDeque

fun interface TtsChunkPlayback {
    fun cancel(reason: TtsCancelReason)
}

fun interface TtsChunkPlayer {
    fun play(chunk: CommittedSpeechChunk, callbacks: TtsChunkPlaybackCallbacks): TtsChunkPlayback

    fun prefetch(chunk: CommittedSpeechChunk) = Unit

    fun releaseSession(sessionId: String) = Unit
}

data class TtsChunkPlaybackCallbacks(
    val onStarted: () -> Unit,
    val onCompleted: (success: Boolean, errorCode: String?) -> Unit
)

data class TtsChunkSchedulerCallbacks(
    val onPlaybackStarted: (CommittedSpeechChunk) -> Unit = {},
    val onUnderrun: (count: Int) -> Unit = {},
    val onFinished: (success: Boolean, errorCode: String?) -> Unit = { _, _ -> },
    val onCancelled: (TtsCancelReason) -> Unit = {}
)

enum class TtsEnqueueResult {
    ACCEPTED,
    COALESCED,
    STALE_SESSION,
    OUT_OF_ORDER,
    QUEUE_FULL
}

data class TtsChunkSchedulerSnapshot(
    val sessionId: String = "",
    val queuedChunks: Int = 0,
    val playing: Boolean = false,
    val inputClosed: Boolean = false,
    val lastSequence: Long = -1L,
    val underrunCount: Int = 0
)

class TtsChunkScheduler(
    private val player: TtsChunkPlayer,
    private val maximumQueuedChunks: Int = 12,
    private val maximumCoalescedCharacters: Int = 1_200
) {
    private data class Session(
        val id: String,
        val generation: Long,
        val callbacks: TtsChunkSchedulerCallbacks,
        val pending: ArrayDeque<CommittedSpeechChunk> = ArrayDeque(),
        var activeToken: Long? = null,
        var activePlayback: TtsChunkPlayback? = null,
        var lastSequence: Long = -1L,
        var inputClosed: Boolean = false,
        var underrunCount: Int = 0
    )

    private data class StartPlan(
        val sessionId: String,
        val generation: Long,
        val token: Long,
        val chunk: CommittedSpeechChunk
    )

    private var generation = 0L
    private var playbackToken = 0L
    private var active: Session? = null

    init {
        require(maximumQueuedChunks > 0)
        require(maximumCoalescedCharacters > 0)
    }

    fun begin(sessionId: String, callbacks: TtsChunkSchedulerCallbacks = TtsChunkSchedulerCallbacks()) {
        require(sessionId.isNotBlank())
        val previous = synchronized(this) {
            val old = active
            generation += 1L
            active = Session(sessionId, generation, callbacks)
            old
        }
        previous?.activePlayback?.cancel(TtsCancelReason.NEW_RESPONSE)
        previous?.let { player.releaseSession(it.id) }
        previous?.callbacks?.onCancelled?.invoke(TtsCancelReason.NEW_RESPONSE)
    }

    fun enqueue(sessionId: String, chunk: CommittedSpeechChunk): TtsEnqueueResult {
        var plan: StartPlan? = null
        var prefetch: CommittedSpeechChunk? = null
        val result = synchronized(this) {
            val session = active
            if (session == null || session.id != sessionId || chunk.requestId != sessionId) {
                return@synchronized TtsEnqueueResult.STALE_SESSION
            }
            if (chunk.sequence <= session.lastSequence) return@synchronized TtsEnqueueResult.OUT_OF_ORDER
            session.lastSequence = chunk.sequence
            if (session.pending.size >= maximumQueuedChunks) {
                val last = session.pending.peekLast()
                val mergedText = listOfNotNull(last?.speechText, chunk.speechText)
                    .filter(String::isNotBlank)
                    .joinToString(" ")
                if (last == null || mergedText.length > maximumCoalescedCharacters) {
                    return@synchronized TtsEnqueueResult.QUEUE_FULL
                }
                session.pending.removeLast()
                val merged = last.copy(
                    sequence = chunk.sequence,
                    speechText = mergedText,
                    isFinal = chunk.isFinal
                )
                session.pending.addLast(merged)
                prefetch = merged
                TtsEnqueueResult.COALESCED
            } else {
                session.pending.addLast(chunk)
                prefetch = chunk
                plan = takeStartPlanLocked(session)
                TtsEnqueueResult.ACCEPTED
            }
        }
        prefetch?.let(player::prefetch)
        plan?.let(::launch)
        return result
    }

    fun finish(sessionId: String) {
        var plan: StartPlan? = null
        var finished: TtsChunkSchedulerCallbacks? = null
        synchronized(this) {
            val session = active ?: return
            if (session.id != sessionId) return
            session.inputClosed = true
            plan = takeStartPlanLocked(session)
            if (plan == null && session.activeToken == null && session.pending.isEmpty()) {
                active = null
                finished = session.callbacks
            }
        }
        plan?.let(::launch)
        finished?.let {
            player.releaseSession(sessionId)
            it.onFinished(true, null)
        }
    }

    fun cancel(sessionId: String, reason: TtsCancelReason): Boolean {
        val cancelled = synchronized(this) {
            val session = active ?: return false
            if (session.id != sessionId) return false
            active = null
            session
        }
        cancelled.activePlayback?.cancel(reason)
        player.releaseSession(cancelled.id)
        cancelled.callbacks.onCancelled(reason)
        return true
    }

    fun cancelActive(reason: TtsCancelReason): Boolean {
        val sessionId = synchronized(this) { active?.id } ?: return false
        return cancel(sessionId, reason)
    }

    @Synchronized
    fun snapshot(): TtsChunkSchedulerSnapshot {
        val session = active ?: return TtsChunkSchedulerSnapshot()
        return TtsChunkSchedulerSnapshot(
            sessionId = session.id,
            queuedChunks = session.pending.size,
            playing = session.activeToken != null,
            inputClosed = session.inputClosed,
            lastSequence = session.lastSequence,
            underrunCount = session.underrunCount
        )
    }

    private fun takeStartPlanLocked(session: Session): StartPlan? {
        if (session.activeToken != null || session.pending.isEmpty()) return null
        val chunk = session.pending.removeFirst()
        val token = ++playbackToken
        session.activeToken = token
        return StartPlan(session.id, session.generation, token, chunk)
    }

    private fun launch(plan: StartPlan) {
        val handle = runCatching {
            player.play(
                plan.chunk,
                TtsChunkPlaybackCallbacks(
                    onStarted = { onPlaybackStarted(plan) },
                    onCompleted = { success, errorCode -> onPlaybackCompleted(plan, success, errorCode) }
                )
            )
        }.getOrElse {
            onPlaybackCompleted(plan, false, it.javaClass.simpleName)
            TtsChunkPlayback { }
        }
        val stale = synchronized(this) {
            val session = active
            if (session != null && session.id == plan.sessionId && session.generation == plan.generation &&
                session.activeToken == plan.token
            ) {
                session.activePlayback = handle
                false
            } else {
                true
            }
        }
        if (stale) handle.cancel(TtsCancelReason.STALE_SESSION)
    }

    private fun onPlaybackStarted(plan: StartPlan) {
        val callbacks = synchronized(this) {
            active?.takeIf {
                it.id == plan.sessionId && it.generation == plan.generation && it.activeToken == plan.token
            }?.callbacks
        } ?: return
        callbacks.onPlaybackStarted(plan.chunk)
    }

    private fun onPlaybackCompleted(plan: StartPlan, success: Boolean, errorCode: String?) {
        var next: StartPlan? = null
        var finished: Pair<TtsChunkSchedulerCallbacks, Pair<Boolean, String?>>? = null
        var underrun: Pair<TtsChunkSchedulerCallbacks, Int>? = null
        synchronized(this) {
            val session = active ?: return
            if (session.id != plan.sessionId || session.generation != plan.generation || session.activeToken != plan.token) {
                return
            }
            session.activeToken = null
            session.activePlayback = null
            if (!success) {
                active = null
                session.pending.clear()
                finished = session.callbacks to (false to errorCode)
            } else {
                next = takeStartPlanLocked(session)
                if (next == null && session.inputClosed && session.pending.isEmpty()) {
                    active = null
                    finished = session.callbacks to (true to null)
                } else if (next == null && session.pending.isEmpty()) {
                    session.underrunCount += 1
                    underrun = session.callbacks to session.underrunCount
                }
            }
        }
        next?.let(::launch)
        underrun?.let { (callbacks, count) -> callbacks.onUnderrun(count) }
        finished?.let { (callbacks, result) ->
            player.releaseSession(plan.sessionId)
            callbacks.onFinished(result.first, result.second)
        }
    }
}
