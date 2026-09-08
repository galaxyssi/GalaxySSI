package com.galaxyssi.chat.voice.tts

import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import java.util.ArrayDeque

/** UI-thread owner of text waiting for the bounded synthesis/playback queue. */
internal class TtsChunkFeeder(private val scheduler: TtsChunkScheduler) {
    private class Session(val id: String) {
        val pending = ArrayDeque<CommittedSpeechChunk>()
        var lastOffered = -1L
        var inputClosed = false
        var draining = false
    }

    private var current: Session? = null
    internal val pendingCount: Int get() = current?.pending?.size ?: 0

    fun begin(sessionId: String) {
        require(sessionId.isNotBlank())
        current = Session(sessionId)
    }

    fun offer(sessionId: String, chunks: List<CommittedSpeechChunk>) {
        val session = current?.takeIf { it.id == sessionId && !it.inputClosed } ?: return
        chunks.forEach { chunk ->
            if (chunk.requestId == sessionId && chunk.sequence > session.lastOffered) {
                session.pending.addLast(chunk)
                session.lastOffered = chunk.sequence
            }
        }
        drain(session)
    }

    fun finish(sessionId: String) {
        val session = current?.takeIf { it.id == sessionId } ?: return
        session.inputClosed = true
        drain(session)
    }

    fun onCapacityAvailable(sessionId: String) {
        current?.takeIf { it.id == sessionId }?.let(::drain)
    }

    fun clear(sessionId: String) {
        if (current?.id == sessionId) current = null
    }

    private fun drain(session: Session) {
        if (session.draining) return
        session.draining = true
        try {
            while (current === session && session.pending.isNotEmpty()) {
                val result = scheduler.enqueue(session.id, session.pending.first(), coalesceWhenFull = false)
                if (current !== session) return
                when (result) {
                    TtsEnqueueResult.QUEUE_FULL -> return
                    TtsEnqueueResult.STALE_SESSION -> { current = null; return }
                    else -> session.pending.removeFirst()
                }
            }
            if (current === session && session.inputClosed) {
                current = null
                scheduler.finish(session.id)
            }
        } finally {
            session.draining = false
        }
    }
}
