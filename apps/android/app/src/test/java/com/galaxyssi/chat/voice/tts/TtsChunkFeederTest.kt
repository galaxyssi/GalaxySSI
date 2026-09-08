package com.galaxyssi.chat.voice.tts

import com.galaxyssi.chat.AgentReplySpeechController
import com.galaxyssi.chat.AgentReplySpeechTarget
import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import org.junit.Assert.*
import org.junit.Test

class TtsChunkFeederTest {
    private class Harness(val synchronous: Boolean = false) {
        val played = mutableListOf<CommittedSpeechChunk>()
        val completions = mutableListOf<TtsChunkPlaybackCallbacks>()
        val results = mutableListOf<Pair<Boolean, String?>>()
        val scheduler = TtsChunkScheduler(object : TtsChunkPlayer {
            override fun play(chunk: CommittedSpeechChunk, callbacks: TtsChunkPlaybackCallbacks): TtsChunkPlayback {
                played += chunk
                completions += callbacks
                callbacks.onStarted()
                if (synchronous) callbacks.onCompleted(true, null)
                return TtsChunkPlayback { }
            }
        }, maximumQueuedChunks = 3)
        val feeder = TtsChunkFeeder(scheduler)

        fun begin(id: String) {
            scheduler.begin(id, TtsChunkSchedulerCallbacks(
                onFinished = { success, error -> feeder.clear(id); results += success to error },
                onCancelled = { feeder.clear(id) },
                onCapacityAvailable = { feeder.onCapacityAvailable(id) }
            ))
            feeder.begin(id)
        }
    }

    private fun chunks(id: String, start: Int, count: Int) = (start until start + count).map {
        CommittedSpeechChunk(id, it.toLong(), "Sentence $it.")
    }

    @Test fun aThousandSentencesPlayInOrderWithoutExpandingTheSynthesisQueue() {
        val h = Harness()
        h.begin("long")
        val input = chunks("long", 0, 1_000)
        h.feeder.offer("long", input)
        h.feeder.finish("long")
        assertEquals(996, h.feeder.pendingCount)
        assertFalse(h.scheduler.snapshot().inputClosed)

        repeat(input.size) { index ->
            assertEquals(input[index], h.played[index])
            assertTrue(h.scheduler.snapshot().queuedChunks <= 3)
            h.completions[index].onCompleted(true, null)
        }
        assertEquals(input, h.played)
        assertEquals(listOf(true to null), h.results)
        assertEquals(0, h.feeder.pendingCount)
        assertEquals("", h.scheduler.snapshot().sessionId)
    }

    @Test fun laterBatchesFollowBackloggedTextAndDuplicateEventsDoNotRepeatSpeech() {
        val h = Harness()
        h.begin("live")
        h.feeder.offer("live", chunks("live", 0, 8))
        h.feeder.offer("live", chunks("live", 7, 6))
        h.feeder.finish("live")
        repeat(13) { h.completions[it].onCompleted(true, null) }
        assertEquals(chunks("live", 0, 13), h.played)
        assertEquals(listOf(true to null), h.results)
    }

    @Test fun cancellationDropsOldTextAndLateCallbacksCannotFeedANewCall() {
        val h = Harness()
        h.begin("old")
        h.feeder.offer("old", chunks("old", 0, 100))
        val oldCompletion = h.completions.first()
        h.scheduler.cancel("old", TtsCancelReason.VOICE_BARGE_IN)
        assertEquals(0, h.feeder.pendingCount)
        h.begin("new")
        h.feeder.offer("new", chunks("new", 0, 2))
        h.feeder.onCapacityAvailable("old")
        h.feeder.finish("old")
        oldCompletion.onCompleted(true, null)
        h.feeder.finish("new")
        h.completions[1].onCompleted(true, null)
        h.completions[2].onCompleted(true, null)
        assertEquals(listOf("old", "new", "new"), h.played.map { it.requestId })
        assertEquals(listOf(true to null), h.results)
    }

    @Test fun playbackFailureReleasesAllDeferredText() {
        val h = Harness()
        h.begin("failed")
        h.feeder.offer("failed", chunks("failed", 0, 100))
        h.feeder.finish("failed")
        h.completions.first().onCompleted(false, "offline")
        h.feeder.onCapacityAvailable("failed")
        assertEquals(0, h.feeder.pendingCount)
        assertEquals(1, h.played.size)
        assertEquals(listOf(false to "offline"), h.results)
    }

    @Test fun synchronousPlayerCallbacksDoNotDuplicateOrRecursivelyDrainText() {
        val h = Harness(synchronous = true)
        h.begin("sync")
        val input = chunks("sync", 0, 1_000)
        h.feeder.offer("sync", input)
        h.feeder.finish("sync")
        assertEquals(input, h.played)
        assertEquals(listOf(true to null), h.results)
    }

    @Test fun aCompleteAgentAnswerKeepsItsLastSentenceAfterTheQueueFills() {
        val controller = AgentReplySpeechController(sessionPrefix = "voice-call")
        val text = (1..100).joinToString(" ") { "This is sentence $it." }
        val command = controller.toggle(AgentReplySpeechTarget("turn", "final", text, complete = true))
        assertTrue(command.chunks.size > 12)
        val h = Harness()
        h.begin(command.beginSessionId)
        h.feeder.offer(command.beginSessionId, command.chunks)
        h.feeder.finish(command.finishSessionId)
        repeat(command.chunks.size) { h.completions[it].onCompleted(true, null) }
        assertEquals(command.chunks, h.played)
        assertTrue(h.played.last().speechText.contains("100"))
        assertEquals(listOf(true to null), h.results)
    }
}
