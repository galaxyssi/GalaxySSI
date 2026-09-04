package com.galaxyssi.chat.voice.tts

import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TtsChunkSchedulerTest {
    private data class PendingPlayback(
        val chunk: CommittedSpeechChunk,
        val callbacks: TtsChunkPlaybackCallbacks,
        var cancelled: Boolean = false
    )

    private class FakePlayer : TtsChunkPlayer {
        val plays = mutableListOf<PendingPlayback>()
        val prefetched = mutableListOf<CommittedSpeechChunk>()
        val releasedSessions = mutableListOf<String>()

        override fun prefetch(chunk: CommittedSpeechChunk) {
            prefetched += chunk
        }

        override fun play(
            chunk: CommittedSpeechChunk,
            callbacks: TtsChunkPlaybackCallbacks
        ): TtsChunkPlayback {
            val pending = PendingPlayback(chunk, callbacks)
            plays += pending
            return TtsChunkPlayback { pending.cancelled = true }
        }

        override fun releaseSession(sessionId: String) {
            releasedSessions += sessionId
        }
    }

    private fun chunk(session: String, sequence: Long, text: String = "chunk-$sequence") =
        CommittedSpeechChunk(session, sequence, text)

    @Test
    fun playsChunksSequentiallyAndFinishesAfterQueueDrains() {
        val player = FakePlayer()
        var finished = false
        val scheduler = TtsChunkScheduler(player)
        scheduler.begin("session", TtsChunkSchedulerCallbacks(onFinished = { success, _ -> finished = success }))

        scheduler.enqueue("session", chunk("session", 0))
        scheduler.enqueue("session", chunk("session", 1))
        scheduler.finish("session")

        assertEquals(1, player.plays.size)
        assertEquals(listOf(0L, 1L), player.prefetched.map(CommittedSpeechChunk::sequence))
        assertFalse(finished)
        player.plays[0].callbacks.onStarted()
        player.plays[0].callbacks.onCompleted(true, null)
        assertEquals(2, player.plays.size)
        assertFalse(finished)
        player.plays[1].callbacks.onCompleted(true, null)
        assertTrue(finished)
        assertEquals(listOf("session"), player.releasedSessions)
        assertEquals("", scheduler.snapshot().sessionId)
    }

    @Test
    fun cancellationStopsCurrentPlaybackAndClearsPendingChunks() {
        val player = FakePlayer()
        var cancelledReason: TtsCancelReason? = null
        val scheduler = TtsChunkScheduler(player)
        scheduler.begin("session", TtsChunkSchedulerCallbacks(onCancelled = { cancelledReason = it }))
        scheduler.enqueue("session", chunk("session", 0))
        scheduler.enqueue("session", chunk("session", 1))

        assertTrue(scheduler.cancel("session", TtsCancelReason.VOICE_BARGE_IN))

        assertTrue(player.plays.single().cancelled)
        assertEquals(listOf("session"), player.releasedSessions)
        assertEquals(TtsCancelReason.VOICE_BARGE_IN, cancelledReason)
        assertEquals(TtsChunkSchedulerSnapshot(), scheduler.snapshot())
    }

    @Test
    fun lateCompletionFromOldSessionCannotStartOrFinishNewSession() {
        val player = FakePlayer()
        var newFinished = false
        val scheduler = TtsChunkScheduler(player)
        scheduler.begin("old")
        scheduler.enqueue("old", chunk("old", 0))
        val oldPlayback = player.plays.single()

        scheduler.begin("new", TtsChunkSchedulerCallbacks(onFinished = { success, _ -> newFinished = success }))
        scheduler.enqueue("new", chunk("new", 0))
        scheduler.finish("new")
        oldPlayback.callbacks.onCompleted(true, null)

        assertEquals(2, player.plays.size)
        assertFalse(newFinished)
        player.plays[1].callbacks.onCompleted(true, null)
        assertTrue(newFinished)
    }

    @Test
    fun rejectsStaleAndOutOfOrderChunks() {
        val scheduler = TtsChunkScheduler(FakePlayer())
        scheduler.begin("session")

        assertEquals(TtsEnqueueResult.STALE_SESSION, scheduler.enqueue("other", chunk("other", 0)))
        assertEquals(TtsEnqueueResult.ACCEPTED, scheduler.enqueue("session", chunk("session", 2)))
        assertEquals(TtsEnqueueResult.OUT_OF_ORDER, scheduler.enqueue("session", chunk("session", 2)))
        assertEquals(TtsEnqueueResult.OUT_OF_ORDER, scheduler.enqueue("session", chunk("session", 1)))
    }

    @Test
    fun boundedQueueCoalescesTailInsteadOfGrowingWithoutLimit() {
        val player = FakePlayer()
        val scheduler = TtsChunkScheduler(player, maximumQueuedChunks = 2)
        scheduler.begin("session")
        scheduler.enqueue("session", chunk("session", 0))
        scheduler.enqueue("session", chunk("session", 1, "one"))
        scheduler.enqueue("session", chunk("session", 2, "two"))

        val result = scheduler.enqueue("session", chunk("session", 3, "three"))

        assertEquals(TtsEnqueueResult.COALESCED, result)
        assertEquals(2, scheduler.snapshot().queuedChunks)
    }

    @Test
    fun playbackFailureEndsSpeechSessionWithoutThrowing() {
        val player = FakePlayer()
        var result: Pair<Boolean, String?>? = null
        val scheduler = TtsChunkScheduler(player)
        scheduler.begin("session", TtsChunkSchedulerCallbacks(onFinished = { success, error -> result = success to error }))
        scheduler.enqueue("session", chunk("session", 0))
        scheduler.enqueue("session", chunk("session", 1))

        player.plays[0].callbacks.onCompleted(false, "tts_failed")

        assertEquals(false to "tts_failed", result)
        assertEquals(1, player.plays.size)
        assertEquals("", scheduler.snapshot().sessionId)
    }

    @Test
    fun reportsUnderrunWhenPlaybackCatchesLiveModelStream() {
        val player = FakePlayer()
        var underruns = 0
        val scheduler = TtsChunkScheduler(player)
        scheduler.begin("session", TtsChunkSchedulerCallbacks(onUnderrun = { underruns = it }))
        scheduler.enqueue("session", chunk("session", 0))

        player.plays[0].callbacks.onCompleted(true, null)

        assertEquals(1, underruns)
        assertEquals(1, scheduler.snapshot().underrunCount)
        assertFalse(scheduler.snapshot().inputClosed)
    }
}
