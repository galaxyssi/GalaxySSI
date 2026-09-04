package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.atomic.AtomicLong

class DefaultLocalWhisperRuntimeTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun runtimeOwnsSessionLifecycleAndStructuredDecode() = runBlocking {
        val native = FakeNativeApi()
        val runtime = runtime(native)

        val loaded = runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))
        val session = runtime.createSession(LocalWhisperSessionConfig(language = "zh"))
        val result = session.decode(WhisperDecodeRequest(ShortArray(16_000) { 3 }))

        assertEquals("tiny", loaded.profile.id)
        assertEquals(NativeWhisperCode.OK, result.code)
        assertEquals("test", result.text)
        assertTrue(runtime.state.value is WhisperRuntimeState.Ready)
        assertEquals(1, native.runtimeCount)
        assertEquals(1, native.sessionCount)

        session.close()
        runtime.unload()
        assertEquals(0, native.runtimeCount)
        assertEquals(0, native.sessionCount)
        assertEquals(WhisperRuntimeState.Unloaded, runtime.state.value)
        runtime.close()
    }

    @Test
    fun switchingModelsAbortsAndClosesExistingSessions() = runBlocking {
        val native = FakeNativeApi()
        val runtime = runtime(native)
        runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))
        runtime.createSession()

        runtime.load(WhisperModelCatalog.require("base"), WhisperLoadOptions(warmUp = false))

        assertTrue(native.abortCount > 0)
        assertEquals(1, native.runtimeCount)
        assertEquals(0, native.sessionCount)
        assertEquals("base", (runtime.state.value as WhisperRuntimeState.Ready).model.profile.id)
        runtime.close()
        assertEquals(0, native.runtimeCount)
    }

    @Test
    fun benchmarkUsesFreshSessionsAndLeavesNoSessionHandles() = runBlocking {
        val native = FakeNativeApi()
        val runtime = runtime(native)
        runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))

        val result = runtime.runBenchmark(BenchmarkRequest(ShortArray(16_000), iterations = 3))

        assertEquals(3, result.iterations)
        assertEquals(3, result.timings.size)
        assertEquals(0.1, result.medianRealTimeFactor, 0.0001)
        assertEquals(0, native.sessionCount)
        runtime.close()
    }

    @Test
    fun thirtyRecognitionsReleaseEverySession() = runBlocking {
        val native = FakeNativeApi()
        val runtime = runtime(native)
        runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))

        repeat(30) {
            val session = runtime.createSession()
            assertTrue(session.decode(WhisperDecodeRequest(ShortArray(1_600))).successful)
            session.close()
        }

        assertEquals(0, native.sessionCount)
        assertEquals(1, native.runtimeCount)
        runtime.close()
        assertEquals(0, native.runtimeCount)
    }

    @Test
    fun pcmRequestRejectsUnsupportedRatesAndRanges() {
        assertThrows(IllegalArgumentException::class.java) {
            WhisperDecodeRequest(ShortArray(100), sampleRateHz = 48_000)
        }
        assertThrows(IllegalArgumentException::class.java) {
            WhisperDecodeRequest(ShortArray(100), offset = 90, length = 20)
        }
    }

    @Test
    fun everyCatalogProfileUsesTheSameFinalRuntimePath() = runBlocking {
        val native = FakeNativeApi()
        val runtime = runtime(native)

        WhisperModelCatalog.profiles.forEach { profile ->
            val loaded = runtime.load(profile, WhisperLoadOptions(warmUp = false))
            runtime.createSession(LocalWhisperSessionConfig(mode = WhisperExecutionMode.FINAL_ONLY)).use { session ->
                val result = session.decode(
                    WhisperDecodeRequest(ShortArray(1_600), mode = WhisperExecutionMode.FINAL_ONLY)
                )
                assertEquals(profile.id, loaded.profile.id)
                assertEquals(NativeWhisperCode.OK, result.code)
            }
        }

        assertEquals(1, native.runtimeCount)
        assertEquals(0, native.sessionCount)
        runtime.close()
        assertEquals(0, native.runtimeCount)
    }

    private fun runtime(native: FakeNativeApi): DefaultLocalWhisperRuntime {
        val model = temporaryFolder.newFile("model-${System.nanoTime()}.bin").apply { writeText("model") }
        var elapsed = 1_000L
        return DefaultLocalWhisperRuntime(
            modelResolver = { model },
            native = native,
            clock = { 10_000L },
            elapsedRealtime = { elapsed++ }
        )
    }

    private class FakeNativeApi : WhisperNativeApi {
        private val handles = AtomicLong(1L)
        private val runtimes = linkedSetOf<Long>()
        private val sessions = linkedSetOf<Long>()
        var abortCount = 0
            private set

        val runtimeCount: Int get() = runtimes.size
        val sessionCount: Int get() = sessions.size

        override fun createRuntime(modelPath: String, threadCount: Int, useGpu: Boolean): Long =
            handles.getAndIncrement().also(runtimes::add)

        override fun createSession(runtimeHandle: Long, config: LocalWhisperSessionConfig): Long =
            if (runtimeHandle !in runtimes) 0L else handles.getAndIncrement().also(sessions::add)

        override fun decodePcm16(
            sessionHandle: Long,
            pcm: ShortArray,
            offset: Int,
            length: Int
        ): NativeWhisperResult = if (sessionHandle !in sessions) {
            NativeWhisperResult.failure(NativeWhisperCode.INVALID_HANDLE, "invalid")
        } else {
            NativeWhisperResult(
                codeValue = NativeWhisperCode.OK.wireValue,
                segments = arrayOf(NativeWhisperSegment(0L, 1_000L, "test", -0.1f, 0.0f)),
                detectedLanguage = "en",
                timings = NativeWhisperTimings(1.0, 2.0, 3.0, 100.0, 1_000L, 0.1),
                aborted = false,
                message = null
            )
        }

        override fun requestAbort(sessionHandle: Long) {
            if (sessionHandle in sessions) abortCount++
        }

        override fun getTimings(sessionHandle: Long): NativeWhisperTimings = NativeWhisperTimings.EMPTY

        override fun destroySession(sessionHandle: Long) {
            sessions.remove(sessionHandle)
        }

        override fun destroyRuntime(runtimeHandle: Long) {
            runtimes.remove(runtimeHandle)
        }

        override fun activeRuntimeCount(): Int = runtimeCount

        override fun activeSessionCount(): Int = sessionCount
    }
}
