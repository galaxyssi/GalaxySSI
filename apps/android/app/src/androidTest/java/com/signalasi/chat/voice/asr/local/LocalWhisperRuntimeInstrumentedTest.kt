package com.signalasi.chat.voice.asr.local

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.signalasi.chat.WhisperModelManager
import com.signalasi.chat.voice.model.WhisperExecutionMode
import com.signalasi.chat.voice.model.WhisperModelCatalog
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.ceil

@RunWith(AndroidJUnit4::class)
class LocalWhisperRuntimeInstrumentedTest {
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
                memoryInfo.availMem >= profile.minAvailableRamBytes
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

    private companion object {
        const val TAG = "SignalASI-WhisperTest"
        const val MAX_STEADY_NATIVE_GROWTH_BYTES = 16L * 1024L * 1024L
        val OPTIONAL_PROFILE_IDS = listOf("base", "small", "medium", "large", "large_v3_turbo")
    }
}
