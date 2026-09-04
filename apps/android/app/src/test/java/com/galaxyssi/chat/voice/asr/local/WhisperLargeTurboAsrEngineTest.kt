package com.galaxyssi.chat.voice.asr.local

import kotlinx.coroutines.async
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WhisperLargeTurboAsrEngineTest {
    @Test
    fun `engine keeps one prepared context and streams partial then final events`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.prepare("model-a")
            assertEquals(1, native.createCount.get())
            assertTrue(engine.state.value is LocalAsrState.Ready)

            engine.start()
            val listening = awaitState(engine) { it is LocalAsrState.Listening } as LocalAsrState.Listening
            val pcm = ByteBuffer.allocateDirect(320)
            assertTrue(engine.pushPcm(pcm, 160))
            assertEquals(1, native.pushCount.get())

            val partial = async(start = CoroutineStart.UNDISPATCHED) {
                withTimeout(2_000L) { engine.events.filterIsInstance<AsrEvent.Partial>().first() }
            }
            native.emitPartial(
                listening.sessionToken,
                "\u4eca\u5929\u4e0b\u5348",
                "\u53bb\u673a\u573a"
            )
            assertEquals("\u4eca\u5929\u4e0b\u5348", partial.await().stableText)

            engine.stop()
            awaitState(engine) { it is LocalAsrState.Stopping }
            val final = async(start = CoroutineStart.UNDISPATCHED) {
                withTimeout(2_000L) { engine.events.filterIsInstance<AsrEvent.Final>().first() }
            }
            native.emitFinal(listening.sessionToken, "\u4eca\u5929\u4e0b\u5348\u53bb\u673a\u573a")
            assertEquals("\u4eca\u5929\u4e0b\u5348\u53bb\u673a\u573a", final.await().text)
            assertTrue(engine.state.value is LocalAsrState.Ready)
            assertEquals(0, native.destroyCount.get())
        } finally {
            engine.close()
        }
        assertEquals(1, native.destroyCount.get())
    }

    @Test
    fun `invalid PCM and overlapping sessions never reach native inference`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start()
            val first = awaitState(engine) { it is LocalAsrState.Listening } as LocalAsrState.Listening
            engine.start()
            assertEquals(first.sessionToken, (engine.state.value as LocalAsrState.Listening).sessionToken)
            assertFalse(engine.pushPcm(ByteBuffer.allocate(320), 160))
            assertFalse(engine.pushPcm(ByteBuffer.allocateDirect(8), 160))
            assertEquals(1, native.startCount.get())
            assertEquals(0, native.pushCount.get())
        } finally {
            engine.close()
        }
    }

    @Test
    fun `stale callbacks cannot overwrite a newer recording`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start()
            val first = awaitState(engine) { it is LocalAsrState.Listening } as LocalAsrState.Listening
            engine.cancel()
            awaitState(engine) { it is LocalAsrState.Ready }
            engine.start()
            val second = awaitState(engine) {
                it is LocalAsrState.Listening && it.sessionToken != first.sessionToken
            } as LocalAsrState.Listening

            native.emitFinal(first.sessionToken, "stale")
            assertEquals(second.sessionToken, (engine.state.value as LocalAsrState.Listening).sessionToken)
            native.emitFinal(second.sessionToken, "current")
            awaitState(engine) { it is LocalAsrState.Ready }
            Unit
        } finally {
            engine.close()
        }
    }

    @Test
    fun `stop timeout cancels native work and returns to prepared state`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start(AsrConfig(finalizationTimeoutMs = 1_000L))
            awaitState(engine) { it is LocalAsrState.Listening }
            engine.stop()
            awaitState(engine, 2_500L) { it is LocalAsrState.Ready }
            assertEquals(1, native.stopCount.get())
            assertEquals(1, native.cancelCount.get())
        } finally {
            engine.close()
        }
    }

    @Test
    fun `pause requested during native start cannot be overwritten by start completion`() = runBlocking {
        val native = FakeNativeApi().apply { startGate = CountDownLatch(1) }
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start()
            awaitState(engine) { it is LocalAsrState.Starting }
            engine.pause(LocalAsrPauseReason.APP_BACKGROUND)
            awaitState(engine) { it is LocalAsrState.Paused }
            native.startGate?.countDown()
            awaitCondition { native.pauseCount.get() == 1 }
            assertTrue(engine.state.value is LocalAsrState.Paused)

            engine.resume(LocalAsrPauseReason.APP_BACKGROUND)
            awaitState(engine) { it is LocalAsrState.Listening }
            assertEquals(1, native.resumeCount.get())
        } finally {
            native.startGate?.countDown()
            engine.close()
        }
    }

    @Test
    fun `model switch is rejected while recording and allowed after cancel`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start()
            awaitState(engine) { it is LocalAsrState.Listening }
            assertThrows(IllegalStateException::class.java) {
                runBlocking { engine.prepare("model-b") }
            }
            engine.cancel()
            awaitState(engine) { it is LocalAsrState.Ready }
            engine.prepare("model-b")
            assertEquals(2, native.createCount.get())
            assertEquals(1, native.destroyCount.get())
        } finally {
            engine.close()
        }
    }

    @Test
    fun `runtime policy reaches the persistent native context without restarting it`() = runBlocking {
        val native = FakeNativeApi()
        val engine = engine(native)
        try {
            engine.prepare("model-a")
            engine.start(AsrConfig(updateIntervalMs = 600L, performanceMode = AsrPerformanceMode.FAST))
            awaitState(engine) { it is LocalAsrState.Listening }
            assertEquals(600L, native.policies.last().partialIntervalMs)

            engine.updateRuntimePolicy(
                AsrRuntimePolicy(
                    partialIntervalMs = 1_000L,
                    emitIntermediateResults = false,
                    thermalStatus = AsrRuntimePolicy.THERMAL_STATUS_SEVERE
                )
            )
            awaitCondition { native.policies.size == 2 }
            assertFalse(native.policies.last().emitIntermediateResults)
            assertEquals(1, native.createCount.get())
        } finally {
            engine.close()
        }
    }

    @Test
    fun `registry shares one engine instance`() {
        val created = AtomicInteger()
        val registry = LocalAsrEngineRegistry {
            created.incrementAndGet()
            engine(FakeNativeApi())
        }
        try {
            assertSame(registry.get(), registry.get())
            assertEquals(1, created.get())
        } finally {
            registry.close()
        }
    }

    private fun engine(native: FakeNativeApi) = WhisperLargeTurboAsrEngine(
        native = native,
        runtimeDirectory = "runtime",
        modelValidator = QnnAsrModelDirectoryValidator { it }
    )

    private suspend fun awaitState(
        engine: LocalAsrEngine,
        timeoutMs: Long = 2_000L,
        predicate: (LocalAsrState) -> Boolean
    ): LocalAsrState = withTimeout(timeoutMs) { engine.state.first(predicate) }

    private suspend fun awaitCondition(predicate: () -> Boolean) = withTimeout(2_000L) {
        while (!predicate()) delay(10L)
    }

    private class FakeNativeApi : QnnAsrNativeApi {
        val createCount = AtomicInteger()
        val startCount = AtomicInteger()
        val pushCount = AtomicInteger()
        val stopCount = AtomicInteger()
        val cancelCount = AtomicInteger()
        val pauseCount = AtomicInteger()
        val resumeCount = AtomicInteger()
        val destroyCount = AtomicInteger()
        val policies = java.util.concurrent.CopyOnWriteArrayList<AsrRuntimePolicy>()
        private var callback: QnnAsrNativeCallback? = null
        var startGate: CountDownLatch? = null

        override fun create(modelDirectory: String, runtimeDirectory: String, callback: QnnAsrNativeCallback): Long {
            this.callback = callback
            return createCount.incrementAndGet().toLong()
        }

        override fun start(handle: Long, sessionToken: Long, config: AsrConfig): Boolean {
            startCount.incrementAndGet()
            startGate?.await(2L, TimeUnit.SECONDS)
            return true
        }

        override fun pushPcm(
            handle: Long,
            sessionToken: Long,
            pcm: ByteBuffer,
            sampleCount: Int
        ): Boolean {
            pushCount.incrementAndGet()
            return true
        }

        override fun stop(handle: Long, sessionToken: Long) {
            stopCount.incrementAndGet()
        }

        override fun cancel(handle: Long, sessionToken: Long) {
            cancelCount.incrementAndGet()
        }

        override fun pause(handle: Long, sessionToken: Long) {
            pauseCount.incrementAndGet()
        }

        override fun resume(handle: Long, sessionToken: Long): Boolean {
            resumeCount.incrementAndGet()
            return true
        }

        override fun updateRuntimePolicy(handle: Long, policy: AsrRuntimePolicy) {
            policies += policy
        }

        override fun destroy(handle: Long) {
            destroyCount.incrementAndGet()
        }

        fun emitPartial(token: Long, stable: String, unstable: String) {
            callback?.onPartial(token, stable, unstable, 900L, 320L)
        }

        fun emitFinal(token: Long, text: String) {
            callback?.onFinal(
                token,
                text,
                1_100L,
                410L,
                AsrTranscriptTermination.END_OF_TEXT
            )
        }
    }
}
