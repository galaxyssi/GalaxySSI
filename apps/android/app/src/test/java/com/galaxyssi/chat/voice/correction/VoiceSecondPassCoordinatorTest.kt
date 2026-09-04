package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class VoiceSecondPassCoordinatorTest {
    @Test
    fun `new voice preempts an ordinary second pass`() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val coordinator = VoiceSecondPassCoordinator()
        val ledger = ledger()
        val decoderStarted = CompletableDeferred<Unit>()
        val callbackCount = AtomicInteger()
        coordinator.schedule(
            scope = scope,
            request = request(),
            executionLedger = ledger,
            decoder = {
                decoderStarted.complete(Unit)
                delay(30_000L)
                hypothesis("accurate", 2)
            },
            onResult = { callbackCount.incrementAndGet() }
        )
        decoderStarted.await()

        assertEquals(1, coordinator.cancelForInteractiveVoice())
        delay(100L)
        assertEquals(0, callbackCount.get())
        assertTrue(coordinator.activeSessionIds().isEmpty())
        scope.cancel()
    }

    @Test
    fun `duplicate schedule cannot produce duplicate correction`() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val coordinator = VoiceSecondPassCoordinator()
        val ledger = ledger()
        val gate = CompletableDeferred<Unit>()
        val completed = CountDownLatch(1)
        val callbackCount = AtomicInteger()
        val first = coordinator.schedule(
            scope,
            request(),
            ledger,
            decoder = {
                gate.await()
                hypothesis("accurate", 2)
            },
            onResult = {
                callbackCount.incrementAndGet()
                completed.countDown()
            }
        )
        val duplicate = coordinator.schedule(
            scope,
            request(),
            ledger,
            decoder = { hypothesis("duplicate", 3) },
            onResult = { callbackCount.incrementAndGet() }
        )
        gate.complete(Unit)

        assertTrue(first)
        assertFalse(duplicate)
        assertTrue(completed.await(2, TimeUnit.SECONDS))
        assertEquals(1, callbackCount.get())
        scope.cancel()
    }

    private fun ledger() = VoiceExecutionLedger().apply {
        begin("voice-1", "voice-1:dispatch", hypothesis("fast", 1), VoiceCommandRisk.CONVERSATION)
    }

    private fun request() = VoiceSecondPassRequest(
        sessionId = "voice-1",
        pcm16 = ShortArray(16_000) { 1 },
        sampleRateHz = 16_000,
        language = "en",
        fast = hypothesis("fast", 1),
        accurateProfileId = "medium_q5_0",
        accurateModelSha256 = "a".repeat(64),
        mode = WhisperExecutionMode.SECOND_PASS
    )

    private fun hypothesis(text: String, revision: Int) = TranscriptHypothesis(
        text = text,
        revision = revision,
        provider = "whisper.cpp",
        modelProfileId = if (revision == 1) "tiny_q5_1" else "medium_q5_0"
    )
}
