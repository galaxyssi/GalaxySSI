package com.galaxyssi.chat.voice.asr.local

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.VoiceAssistantSettings
import com.galaxyssi.chat.WhisperModelManager
import com.galaxyssi.chat.LocalWhisperAsr
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.ceil
import kotlin.math.sin

@RunWith(AndroidJUnit4::class)
class LocalWhisperRuntimeInstrumentedTest {
    @Test
    fun selectedCompactModelTranscribesThroughTheAppAsrEntryPoint() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()

        val outcome = withTimeout(180_000L) {
            LocalWhisperAsr.transcribePcmOutcome(
                context = context,
                pcm16 = ShortArray(16_000),
                language = "en",
                source = "instrumented_qnn_entry_point"
            )
        }

        assertEquals(VoiceAssistantSettings.get(context).asrModel, outcome.profileId)
    }

    @Test
    fun selectedCompactModelUsesQnnHtpWhenAvailable() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val profile = WhisperModelCatalog.require(VoiceAssistantSettings.get(context).asrModel)
        assertTrue("QNN HTP runtime is not packaged for this Qualcomm device", WhisperQnnSupport.canUse(context, profile))

        val runtime = QnnWhisperRuntime(context)
        try {
            val loaded = withTimeout(300_000L) {
                runtime.load(profile, WhisperLoadOptions(threadCount = 2, warmUp = false))
            }
            assertEquals(WhisperAccelerationBackend.QNN_HTP, loaded.accelerationBackend)
            val elapsed = buildList {
                repeat(3) { iteration ->
                    runtime.createSession(
                        LocalWhisperSessionConfig(
                            language = "en",
                            singleSegment = true,
                            mode = WhisperExecutionMode.FINAL_ONLY
                        )
                    ).use { session ->
                        val startedAt = android.os.SystemClock.elapsedRealtime()
                        val result = withTimeout(180_000L) {
                            session.decode(WhisperDecodeRequest(ShortArray(16_000)))
                        }
                        add(android.os.SystemClock.elapsedRealtime() - startedAt)
                        assertEquals(
                            "QNN HTP decode $iteration failed: ${result.message}",
                            NativeWhisperCode.OK,
                            result.code
                        )
                    }
                }
            }
            Log.i(TAG, "QNN HTP isolated decode elapsedMs=$elapsed")
        } finally {
            runtime.close()
        }
        Unit
    }

    @Test
    fun selectedDownloadedProfileLoadsAndCompletesFinalDecode() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val selected = WhisperModelCatalog.require(VoiceAssistantSettings.get(context).asrModel)
        assertTrue("Selected model ${selected.id} is not installed", WhisperModelManager.isAvailable(context, selected))

        val runtime = DefaultLocalWhisperRuntime(context)
        try {
            runtime.load(selected, WhisperLoadOptions(threadCount = 2, warmUp = false))
            runtime.createSession(
                LocalWhisperSessionConfig(
                    language = "en",
                    singleSegment = true,
                    mode = WhisperExecutionMode.FINAL_ONLY
                )
            ).use { session ->
                val result = withTimeout(120_000L) {
                    session.decode(
                        WhisperDecodeRequest(
                            pcm16 = ShortArray(16_000),
                            mode = WhisperExecutionMode.FINAL_ONLY
                        )
                    )
                }
                assertEquals("${selected.id} Final failed: ${result.message}", NativeWhisperCode.OK, result.code)
            }
        } finally {
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    @Test
    fun verifiedTinyCreatesSessionDecodesPcmAndReleasesHandles() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val runtime = DefaultLocalWhisperRuntime(context)
        try {
            runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))
            runtime.createSession(LocalWhisperSessionConfig(language = "en", singleSegment = true)).use { session ->
                val result = session.decode(WhisperDecodeRequest(ShortArray(16_000)))

                assertEquals(NativeWhisperCode.OK, result.code)
                assertTrue(result.timings.totalMs >= 0.0)
                assertEquals(1 to 1, runtime.activeNativeHandles())
            }
            assertEquals(1 to 0, runtime.activeNativeHandles())
        } finally {
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    @Test
    fun nativeAbortReturnsWithinAcceptanceWindow() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val runtime = DefaultLocalWhisperRuntime(context)
        try {
            runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))
            val elapsedSamples = buildList {
                repeat(20) {
                    runtime.createSession(LocalWhisperSessionConfig(language = "en")).use { session ->
                        val decode = async {
                            session.decode(WhisperDecodeRequest(ShortArray(16_000 * 30)))
                        }
                        withTimeout(5_000L) {
                            while (runtime.state.value !is WhisperRuntimeState.Decoding) delay(5L)
                        }
                        delay(100L)

                        val startedAt = android.os.SystemClock.elapsedRealtime()
                        session.requestAbort(AbortReason.USER_STOP)
                        val result = withTimeout(5_000L) { decode.await() }
                        add(android.os.SystemClock.elapsedRealtime() - startedAt)

                        assertEquals(NativeWhisperCode.ABORTED, result.code)
                    }
                }
            }
            val sorted = elapsedSamples.sorted()
            val p95Index = (ceil(sorted.size * 0.95).toInt() - 1).coerceIn(sorted.indices)
            val p95 = sorted[p95Index]
            Log.i(TAG, "Whisper abort samples=$elapsedSamples p95=${p95}ms")
            assertTrue("Native abort p95 took ${p95}ms; samples=$elapsedSamples", p95 <= 300L)
        } finally {
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    @Test
    fun thirtyConsecutiveRecognitionsReleaseSessionsWithoutSustainedNativeGrowth() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val runtime = DefaultLocalWhisperRuntime(context)
        try {
            runtime.load(WhisperModelCatalog.require("tiny"), WhisperLoadOptions(warmUp = false))
            val pcm = ShortArray(16_000)
            val nativeHeapSamples = mutableListOf<Long>()
            withTimeout(120_000L) {
                repeat(30) { iteration ->
                    runtime.createSession(LocalWhisperSessionConfig(language = "en", singleSegment = true)).use { session ->
                        val result = session.decode(WhisperDecodeRequest(pcm))
                        assertEquals(NativeWhisperCode.OK, result.code)
                    }
                    assertEquals(1 to 0, runtime.activeNativeHandles())
                    if ((iteration + 1) % 5 == 0) {
                        System.gc()
                        delay(100L)
                        nativeHeapSamples += Debug.getNativeHeapAllocatedSize()
                    }
                }
            }
            val growthBytes = nativeHeapSamples.last() - nativeHeapSamples.first()
            Log.i(TAG, "Whisper 30-run native heap=$nativeHeapSamples growth=$growthBytes")
            assertTrue(
                "Native heap grew continuously by $growthBytes bytes; samples=$nativeHeapSamples",
                growthBytes <= MAX_STEADY_NATIVE_GROWTH_BYTES
            )
        } finally {
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    @Test
    fun installedProfilesCompleteFinalDecodeWhenDeviceResourcesPermit() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val memoryInfo = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java).getMemoryInfo(memoryInfo)
        val eligible = OPTIONAL_PROFILE_IDS.map(WhisperModelCatalog::require).filter { profile ->
            WhisperModelManager.isAvailable(context, profile) &&
                WhisperMemoryAdmissionPolicy.evaluate(
                    profile = profile,
                    availableMemoryBytes = memoryInfo.availMem,
                    currentPssBytes = Debug.getPss().toLong() * 1_024L,
                    lowMemory = memoryInfo.lowMemory
                ).allowed
        }
        Log.i(TAG, "Eligible optional Whisper Final profiles=${eligible.map { it.id }} availMem=${memoryInfo.availMem}")

        val runtime = DefaultLocalWhisperRuntime(context)
        try {
            eligible.forEach { profile ->
                runtime.load(profile, WhisperLoadOptions(warmUp = false))
                runtime.createSession(
                    LocalWhisperSessionConfig(
                        language = "en",
                        singleSegment = true,
                        mode = WhisperExecutionMode.FINAL_ONLY
                    )
                ).use { session ->
                    val result = withTimeout(120_000L) {
                        session.decode(
                            WhisperDecodeRequest(
                                pcm16 = ShortArray(16_000),
                                mode = WhisperExecutionMode.FINAL_ONLY
                            )
                        )
                    }
                    assertEquals("${profile.id} Final failed: ${result.message}", NativeWhisperCode.OK, result.code)
                }
            }
        } finally {
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    @Test
    fun tinyAdaptivePartialFinalMatchesAuthoritativeFullDecode() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val profile = WhisperModelCatalog.require("tiny")
        val runtime = DefaultLocalWhisperRuntime(context)
        val partialCompleted = CompletableDeferred<Unit>()
        val scheduler = DefaultWhisperDecodeScheduler(
            parentScope = this,
            decoder = { request ->
                runtime.createSession(
                    LocalWhisperSessionConfig(
                        language = "en",
                        singleSegment = request.mode == WhisperExecutionMode.REALTIME_PARTIAL,
                        mode = request.mode
                    )
                ).use { session ->
                    session.decode(WhisperDecodeRequest(pcm16 = request.pcm16, mode = request.mode)).also {
                        if (request.mode == WhisperExecutionMode.REALTIME_PARTIAL) partialCompleted.complete(Unit)
                    }
                }
            },
            abortActive = runtime::requestAbortAll
        )
        val live = LiveWhisperTranscriptionSession(
            voiceSessionId = "instrumented-live",
            profile = profile,
            language = "en",
            scheduler = scheduler,
            scope = this,
            elapsedRealtime = { 2_000L },
            onUpdate = {}
        )
        val samples = ShortArray(32_000) { index ->
            (sin(index * 2.0 * Math.PI * 220.0 / 16_000.0) * 2_000.0).toInt().toShort()
        }
        val snapshot = PcmSnapshot(
            samples = samples,
            sampleRateHz = 16_000,
            speechDetected = true,
            speechStartSample = 0L,
            speechEndSampleExclusive = samples.size.toLong(),
            captureStartSample = 0L,
            captureEndSampleExclusive = samples.size.toLong()
        )
        try {
            runtime.load(profile, WhisperLoadOptions(warmUp = false))
            assertTrue(live.nextPartialWindowMs(snapshot.durationMs) != null)
            live.offerPartial(snapshot)
            withTimeout(30_000L) { partialCompleted.await() }

            val adaptiveFinal = withTimeout(60_000L) { live.finish(snapshot) }
            val authoritativeFinal = runtime.createSession(
                LocalWhisperSessionConfig(
                    language = "en",
                    singleSegment = false,
                    mode = WhisperExecutionMode.FINAL_ONLY
                )
            ).use { session ->
                withTimeout(60_000L) {
                    session.decode(
                        WhisperDecodeRequest(pcm16 = samples, mode = WhisperExecutionMode.FINAL_ONLY)
                    )
                }
            }

            assertEquals(NativeWhisperCode.OK, adaptiveFinal.code)
            assertEquals(authoritativeFinal.text, adaptiveFinal.text)
            assertEquals(1 to 0, runtime.activeNativeHandles())
        } finally {
            live.close()
            scheduler.close()
            runtime.close()
        }
        assertEquals(0 to 0, runtime.activeNativeHandles())
    }

    private companion object {
        const val TAG = "GalaxySSI-WhisperTest"
        const val MAX_STEADY_NATIVE_GROWTH_BYTES = 16L * 1024L * 1024L
        val OPTIONAL_PROFILE_IDS = listOf("base", "small", "medium", "large", "large_v3_turbo")
    }
}
