package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperDecodeSchedulerTest {
    @Test
    fun finalAbortsActivePartialAndRunsExactlyOnce() = runBlocking {
        val partialStarted = CompletableDeferred<Unit>()
        val partialAbort = CompletableDeferred<Unit>()
        var finalRuns = 0
        val scheduler = DefaultWhisperDecodeScheduler(
            parentScope = this,
            decoder = { request ->
                if (request.mode == WhisperExecutionMode.REALTIME_PARTIAL) {
                    partialStarted.complete(Unit)
                    partialAbort.await()
                    NativeWhisperResult.failure(NativeWhisperCode.ABORTED, "cancelled")
                } else {
                    finalRuns += 1
                    success("final")
                }
            },
            abortActive = { partialAbort.complete(Unit) }
        )
        try {
            val partial = async { scheduler.submit(request("partial", WhisperDecodePriority.CURRENT_PARTIAL)) }
            partialStarted.await()
            val final = async { scheduler.submit(request("final", WhisperDecodePriority.CURRENT_FINAL)) }

            assertTrue(partial.await() is ScheduledWhisperResult.Dropped)
            val finalResult = final.await()
            assertTrue(finalResult is ScheduledWhisperResult.Completed)
            assertEquals(1, finalRuns)
            assertEquals(0, scheduler.queueSnapshot().queued)
        } finally {
            scheduler.close()
        }
    }

    @Test
    fun boundedQueueRejectsLowerPriorityWork() = runBlocking {
        val activeStarted = CompletableDeferred<Unit>()
        val releaseActive = CompletableDeferred<Unit>()
        val scheduler = DefaultWhisperDecodeScheduler(
            parentScope = this,
            maxQueueSize = 1,
            decoder = { request ->
                if (request.requestId == "active") {
                    activeStarted.complete(Unit)
                    releaseActive.await()
                }
                success(request.requestId)
            },
            abortActive = {}
        )
        try {
            val active = async { scheduler.submit(request("active", WhisperDecodePriority.CURRENT_PARTIAL)) }
            activeStarted.await()
            val queued = async { scheduler.submit(request("queued", WhisperDecodePriority.CURRENT_PARTIAL)) }
            while (scheduler.queueSnapshot().queued == 0) kotlinx.coroutines.yield()
            val rejected = scheduler.submit(request("background", WhisperDecodePriority.BACKGROUND))
            assertTrue(rejected is ScheduledWhisperResult.Dropped)
            assertEquals(WhisperDecodeDropReason.QUEUE_CAPACITY, (rejected as ScheduledWhisperResult.Dropped).reason)
            releaseActive.complete(Unit)
            assertTrue(active.await() is ScheduledWhisperResult.Completed)
            assertTrue(queued.await() is ScheduledWhisperResult.Completed)
        } finally {
            scheduler.close()
        }
    }

    private fun request(id: String, priority: WhisperDecodePriority) = ScheduledWhisperDecode(
        requestId = id,
        voiceSessionId = "voice-1",
        revision = id.hashCode().and(Int.MAX_VALUE).coerceAtLeast(1),
        modelProfileId = "tiny",
        pcm16 = ShortArray(1_600),
        mode = if (priority == WhisperDecodePriority.CURRENT_FINAL) {
            WhisperExecutionMode.FINAL_ONLY
        } else {
            WhisperExecutionMode.REALTIME_PARTIAL
        },
        priority = priority
    )

    private fun success(text: String) = NativeWhisperResult(
        codeValue = NativeWhisperCode.OK.wireValue,
        segments = arrayOf(NativeWhisperSegment(0L, 100L, text, -0.1f, 0.0f)),
        detectedLanguage = "en",
        timings = NativeWhisperTimings(1.0, 2.0, 3.0, 50.0, 100L, 0.5),
        aborted = false,
        message = null
    )
}
