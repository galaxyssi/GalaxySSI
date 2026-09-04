package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.LocalWhisperException
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.BenchmarkRequest
import com.galaxyssi.chat.voice.asr.local.BenchmarkResult
import com.galaxyssi.chat.voice.asr.local.LocalWhisperRuntime
import com.galaxyssi.chat.voice.asr.local.LocalWhisperSession
import com.galaxyssi.chat.voice.asr.local.LocalWhisperSessionConfig
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.NativeWhisperResult
import com.galaxyssi.chat.voice.asr.local.NativeWhisperSegment
import com.galaxyssi.chat.voice.asr.local.NativeWhisperTimings
import com.galaxyssi.chat.voice.asr.local.UnloadReason
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeRequest
import com.galaxyssi.chat.voice.asr.local.WhisperLoadOptions
import com.galaxyssi.chat.voice.asr.local.WhisperLoadedModel
import com.galaxyssi.chat.voice.asr.local.WhisperRuntimeState
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.atomic.AtomicLong

class WhisperBenchmarkRunnerTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun runnerSearchesThreadsPersistsEvidenceAndCertifiesMeasuredRuntime() = runBlocking {
        val store = store()
        val runner = runner(store, runtimeFactory = { FakeRuntime() })
        val progress = mutableListOf<WhisperBenchmarkStage>()

        val record = runner.run(profile, audio(), onProgress = { progress += it.stage })

        assertEquals(WhisperCertificationLevel.REALTIME, record.certification.level)
        assertEquals(2, record.certification.recommendedThreadCount)
        assertEquals(listOf(2), record.threadCandidates)
        assertEquals(7, record.measurements.size)
        assertTrue(record.measurements.all { it.transcriptCorrect })
        assertTrue(record.measurements.any { it.loadKind == WhisperBenchmarkLoadKind.COLD })
        assertTrue(record.measurements.any { it.loadKind == WhisperBenchmarkLoadKind.HOT })
        assertEquals(record.certification, store.find(record.certification.key)?.certification)
        assertEquals(WhisperBenchmarkStage.COMPLETE, progress.last())
    }

    @Test
    fun outOfMemoryFailureIsPersistedAsUnsupportedRemoteRecommendation() = runBlocking {
        val store = store()
        val record = runner(store, runtimeFactory = { FakeRuntime(failLoadWithOom = true) }).run(profile, audio())

        assertEquals(WhisperCertificationLevel.REMOTE_RECOMMENDED, record.certification.level)
        assertTrue(record.certification.remoteRecommended)
        assertTrue(record.certification.failureReason.orEmpty().contains("memory", ignoreCase = true))
        assertEquals(record.certification, store.find(record.certification.key)?.certification)
    }

    @Test
    fun severeThermalPreflightFailsClosedWithoutLoadingNativeRuntime() = runBlocking {
        var runtimeCreated = false
        val store = store()
        val runner = runner(
            store = store,
            runtimeFactory = {
                runtimeCreated = true
                FakeRuntime()
            },
            thermalStatus = 3
        )

        val record = runner.run(profile, audio())

        assertEquals(WhisperCertificationLevel.REMOTE_RECOMMENDED, record.certification.level)
        assertTrue(record.certification.remoteRecommended)
        assertTrue(!runtimeCreated)
    }

    @Test
    fun incompatibleNativeModelIsPersistedAsUnsupported() = runBlocking {
        val store = store()
        val record = runner(
            store,
            runtimeFactory = {
                FakeRuntime(loadFailure = LocalWhisperException(
                    NativeWhisperCode.UNSUPPORTED_MODEL,
                    "unsupported model"
                ))
            }
        ).run(profile, audio())

        assertEquals(WhisperCertificationLevel.UNSUPPORTED, record.certification.level)
        assertTrue(!record.certification.remoteRecommended)
        assertTrue(record.certification.failureReason.orEmpty().contains("native", ignoreCase = true))
    }

    @Test
    fun interruptedBenchmarkDoesNotPersistPartialCertification() = runBlocking {
        val store = store()
        val decodeStarted = CompletableDeferred<Unit>()
        val job = launch {
            runner(
                store,
                runtimeFactory = {
                    FakeRuntime(
                        decodeDelayMs = 5_000L,
                        onDecodeStarted = { decodeStarted.complete(Unit) }
                    )
                }
            ).run(profile, audio())
        }

        decodeStarted.await()
        job.cancelAndJoin()

        assertNull(store.latestForProfile(profile.id))
    }

    @Test
    fun benchmarkCorrectnessNormalizesChineseScriptVariants() = runBlocking {
        val store = store()
        val fixture = WhisperBenchmarkAudio(
            version = "zh-script-v1",
            pcm16 = ShortArray(WhisperBenchmarkAudio.SAMPLE_RATE_HZ * 5),
            expectedTokens = setOf("\u8bed\u97f3", "\u6d4b\u8bd5", "\u6027\u80fd", "\u5185\u5b58", "\u6e29\u5ea6", "\u53d6\u6d88"),
            language = "zh"
        )
        val record = runner(
            store,
            runtimeFactory = { FakeRuntime(outputText = "\u8a9e\u97f3\u6e2c\u8a66\u6027\u80fd\u5167\u5b58\u6eab\u5ea6\u53d6\u6d88") }
        ).run(profile, fixture)

        assertEquals(WhisperCertificationLevel.REALTIME, record.certification.level)
        assertTrue(record.measurements.all { it.transcriptCorrect })
    }

    @Test
    fun largeModelsUseAColdStartFriendlyBenchmarkPlan() {
        val plan = WhisperBenchmarkPlan.forProfile(WhisperModelCatalog.require("large_v3_q5_0"))

        assertEquals(listOf(3_000L), plan.candidateAudioDurationsMs)
        assertEquals(1, plan.candidateIterations)
        assertEquals(1, plan.stabilityIterations)
        assertEquals(1, plan.abortIterations)
        assertTrue(!plan.warmUpLoads)
    }

    @Test
    fun smallModelsKeepTheFullBenchmarkPlan() {
        val plan = WhisperBenchmarkPlan.forProfile(WhisperModelCatalog.require("tiny_q5_1"))

        assertEquals(listOf(3_000L, 5_000L), plan.candidateAudioDurationsMs)
        assertEquals(2, plan.candidateIterations)
        assertEquals(3, plan.stabilityIterations)
        assertTrue(plan.warmUpLoads)
    }

    private fun runner(
        store: WhisperBenchmarkStore,
        runtimeFactory: () -> LocalWhisperRuntime,
        thermalStatus: Int = 0
    ): WhisperBenchmarkRunner {
        val elapsed = AtomicLong(1_000L)
        return WhisperBenchmarkRunner(
            runtimeFactory = runtimeFactory,
            keyFactory = { model, audioVersion -> key(model, audioVersion) },
            snapshot = {
                WhisperBenchmarkSystemSnapshot(
                    availableMemoryBytes = 8L * 1_024L * 1_024L * 1_024L,
                    systemLowMemory = false,
                    pssBytes = 128L * 1_024L * 1_024L,
                    rssBytes = 160L * 1_024L * 1_024L,
                    nativeAllocatedBytes = 64L * 1_024L * 1_024L,
                    cpuTimeMs = elapsed.incrementAndGet(),
                    energyCounterNwh = 1_000_000L - elapsed.get(),
                    batteryTemperatureCelsius = 30.0,
                    thermalStatus = thermalStatus
                )
            },
            highPerformanceCoreCount = { 2 },
            verifyModel = {},
            elapsedRealtime = { elapsed.incrementAndGet() },
            clock = { 10_000L },
            store = store,
            plan = WhisperBenchmarkPlan(
                candidateAudioDurationsMs = listOf(1_000L, 2_000L),
                candidateIterations = 2,
                stabilityAudioDurationMs = 3_000L,
                stabilityIterations = 3,
                abortIterations = 1,
                metricSampleIntervalMs = 10L,
                abortDelayMs = 1L,
                abortTimeoutMs = 500L
            )
        )
    }

    private fun store() = WhisperBenchmarkStore(temporaryFolder.newFile("runner-${System.nanoTime()}.json"))

    private fun audio() = WhisperBenchmarkAudio(
        version = "audio-v1",
        pcm16 = ShortArray(WhisperBenchmarkAudio.SAMPLE_RATE_HZ * 5),
        expectedTokens = setOf("test"),
        language = "en"
    )

    private fun key(model: WhisperModelProfile, audioVersion: String) = WhisperBenchmarkKey(
        manufacturer = "GalaxySSI",
        device = "runner-device",
        soc = "runner-soc",
        androidApi = 36,
        appVersionCode = 309,
        whisperNativeVersion = "v1",
        nativeBuildFingerprint = "native-a",
        modelProfileId = model.id,
        modelSha256 = model.sha256,
        benchmarkAudioVersion = audioVersion
    )

    private class FakeRuntime(
        private val failLoadWithOom: Boolean = false,
        private val loadFailure: Throwable? = null,
        private val decodeDelayMs: Long = 0L,
        private val onDecodeStarted: (() -> Unit)? = null,
        private val outputText: String = "test"
    ) : LocalWhisperRuntime {
        private val mutableState = MutableStateFlow<WhisperRuntimeState>(WhisperRuntimeState.Unloaded)
        private var loaded: WhisperLoadedModel? = null
        override val state: StateFlow<WhisperRuntimeState> = mutableState

        override suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions): WhisperLoadedModel {
            if (failLoadWithOom) throw OutOfMemoryError("benchmark OOM")
            loadFailure?.let { throw it }
            return WhisperLoadedModel(
                profile = profile,
                threadCount = options.threadCount,
                loadedAtMillis = 1L,
                loadDurationMs = 20L,
                warmUpTimings = timing(100L)
            ).also {
                loaded = it
                mutableState.value = WhisperRuntimeState.Ready(it)
            }
        }

        override suspend fun createSession(config: LocalWhisperSessionConfig): LocalWhisperSession {
            check(loaded != null)
            return object : LocalWhisperSession {
                override val id: String = "fake"
                override val config: LocalWhisperSessionConfig = config
                override suspend fun decode(request: WhisperDecodeRequest): NativeWhisperResult {
                    onDecodeStarted?.invoke()
                    if (decodeDelayMs > 0L) delay(decodeDelayMs)
                    return NativeWhisperResult(
                        codeValue = NativeWhisperCode.OK.wireValue,
                        segments = arrayOf(NativeWhisperSegment(0L, 1_000L, outputText, -0.1f, 0f)),
                        detectedLanguage = "en",
                        timings = timing(request.length.toLong() * 1_000L / 16_000L),
                        aborted = false,
                        message = null
                    )
                }

                override fun requestAbort(reason: AbortReason) = Unit
                override fun close() = Unit
            }
        }

        override suspend fun unload(reason: UnloadReason) {
            loaded = null
            mutableState.value = WhisperRuntimeState.Unloaded
        }

        override suspend fun runBenchmark(request: BenchmarkRequest): BenchmarkResult = BenchmarkResult(
            profileId = requireNotNull(loaded).profile.id,
            iterations = request.iterations,
            timings = List(request.iterations) { timing(request.pcm16.size.toLong() * 1_000L / 16_000L) },
            medianRealTimeFactor = 0.4
        )

        override fun requestAbortAll(reason: AbortReason) = Unit

        override fun close() {
            loaded = null
            mutableState.value = WhisperRuntimeState.Unloaded
        }

        private fun timing(audioMs: Long) = NativeWhisperTimings(
            sampleMs = 1.0,
            encodeMs = 2.0,
            decodeMs = audioMs * 0.4,
            totalMs = audioMs * 0.4,
            audioMs = audioMs,
            realTimeFactor = 0.4
        )
    }

    private companion object {
        val profile = WhisperModelCatalog.require("tiny")
    }
}
