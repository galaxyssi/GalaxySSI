package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.LocalWhisperException
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.LocalWhisperRuntime
import com.galaxyssi.chat.voice.asr.local.LocalWhisperSessionConfig
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.NativeWhisperResult
import com.galaxyssi.chat.voice.asr.local.UnloadReason
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeRequest
import com.galaxyssi.chat.voice.asr.local.WhisperLoadOptions
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

data class WhisperBenchmarkAudio(
    val version: String,
    val pcm16: ShortArray,
    val expectedTokens: Set<String>,
    val language: String = "zh"
) {
    init {
        require(version.isNotBlank())
        require(pcm16.size >= SAMPLE_RATE_HZ * MIN_AUDIO_SECONDS)
        require(expectedTokens.isNotEmpty())
        require(language.isNotBlank())
    }

    fun window(durationMs: Long): ShortArray {
        val requested = (durationMs.coerceAtLeast(1L) * SAMPLE_RATE_HZ / 1_000L).toInt()
        return if (requested <= pcm16.size) {
            pcm16.copyOf(requested)
        } else {
            pcm16.copyOf(requested)
        }
    }

    companion object {
        const val SAMPLE_RATE_HZ = 16_000
        private const val MIN_AUDIO_SECONDS = 5
    }
}

data class WhisperBenchmarkSystemSnapshot(
    val availableMemoryBytes: Long,
    val systemLowMemory: Boolean,
    val pssBytes: Long,
    val rssBytes: Long,
    val nativeAllocatedBytes: Long,
    val cpuTimeMs: Long,
    val energyCounterNwh: Long?,
    val batteryTemperatureCelsius: Double?,
    val thermalStatus: Int
)

data class WhisperBenchmarkPlan(
    val candidateAudioDurationsMs: List<Long> = listOf(3_000L, 5_000L),
    val candidateIterations: Int = 2,
    val stabilityAudioDurationMs: Long = 10_000L,
    val stabilityIterations: Int = 3,
    val abortIterations: Int = 3,
    val metricSampleIntervalMs: Long = 50L,
    val abortDelayMs: Long = 50L,
    val abortTimeoutMs: Long = 5_000L,
    val warmUpLoads: Boolean = true
) {
    init {
        require(candidateAudioDurationsMs.isNotEmpty() && candidateAudioDurationsMs.all { it > 0L })
        require(candidateIterations in 1..5)
        require(stabilityAudioDurationMs > 0L)
        require(stabilityIterations in 1..5)
        require(abortIterations in 1..5)
        require(metricSampleIntervalMs in 10L..250L)
        require(abortDelayMs in 1L..1_000L)
        require(abortTimeoutMs in 500L..15_000L)
    }

    companion object {
        fun forProfile(profile: WhisperModelProfile): WhisperBenchmarkPlan =
            if (profile.expectedSizeBytes >= LARGE_MODEL_THRESHOLD_BYTES) {
                WhisperBenchmarkPlan(
                    candidateAudioDurationsMs = listOf(3_000L),
                    candidateIterations = 1,
                    stabilityAudioDurationMs = 5_000L,
                    stabilityIterations = 1,
                    abortIterations = 1,
                    metricSampleIntervalMs = 100L,
                    warmUpLoads = false
                )
            } else {
                WhisperBenchmarkPlan()
            }

        private const val LARGE_MODEL_THRESHOLD_BYTES = 768L * 1024L * 1024L
    }
}

enum class WhisperBenchmarkStage {
    VERIFYING,
    CHECKING_DEVICE,
    SEARCHING_THREADS,
    STABILITY,
    CANCELLATION,
    CERTIFYING,
    COMPLETE
}

data class WhisperBenchmarkProgress(
    val stage: WhisperBenchmarkStage,
    val completedSteps: Int,
    val totalSteps: Int,
    val threadCount: Int? = null,
    val detail: String = ""
)

class WhisperBenchmarkDeferredException(message: String) : IllegalStateException(message)

class WhisperBenchmarkRunner(
    private val runtimeFactory: () -> LocalWhisperRuntime,
    private val keyFactory: (WhisperModelProfile, String) -> WhisperBenchmarkKey,
    private val snapshot: () -> WhisperBenchmarkSystemSnapshot,
    private val highPerformanceCoreCount: () -> Int,
    private val verifyModel: (WhisperModelProfile) -> Unit,
    private val elapsedRealtime: () -> Long,
    private val clock: () -> Long,
    private val store: WhisperBenchmarkStore,
    private val plan: WhisperBenchmarkPlan = WhisperBenchmarkPlan()
) {
    suspend fun run(
        profile: WhisperModelProfile,
        audio: WhisperBenchmarkAudio,
        force: Boolean = false,
        onProgress: (WhisperBenchmarkProgress) -> Unit = {}
    ): WhisperBenchmarkRecord {
        val key = keyFactory(profile, audio.version)
        if (!force) store.find(key)?.let { return it }

        val hpc = highPerformanceCoreCount().coerceIn(1, 16)
        val candidates = WhisperThreadSearch.candidates(hpc)
        val totalSteps = 3 +
            candidates.size * plan.candidateAudioDurationsMs.size * plan.candidateIterations +
            plan.stabilityIterations + plan.abortIterations
        var completed = 0
        fun progress(stage: WhisperBenchmarkStage, threads: Int? = null, detail: String = "") {
            onProgress(WhisperBenchmarkProgress(stage, completed, totalSteps, threads, detail))
        }

        progress(WhisperBenchmarkStage.VERIFYING)
        val verificationStarted = elapsedRealtime()
        verifyModel(profile)
        val verificationDuration = (elapsedRealtime() - verificationStarted).coerceAtLeast(0L)
        completed += 1

        progress(WhisperBenchmarkStage.CHECKING_DEVICE)
        val initial = snapshot()
        val preflightFailure = preflightFailure(profile, initial)
        if (preflightFailure != null) {
            return terminalRecord(
                key = key,
                profile = profile,
                level = WhisperCertificationLevel.REMOTE_RECOMMENDED,
                reason = preflightFailure,
                verificationDurationMs = verificationDuration,
                highPerformanceCoreCount = hpc,
                threadCandidates = candidates
            ).also(store::save)
        }
        if (initial.thermalStatus >= THERMAL_MODERATE) {
            throw WhisperBenchmarkDeferredException("Benchmark paused until the device cools below MODERATE")
        }
        completed += 1

        val candidateMeasurements = mutableListOf<WhisperBenchmarkMeasurement>()
        var loadSequence = 0
        try {
            candidates.forEach { threads ->
                runtimeFactory().use { runtime ->
                    progress(WhisperBenchmarkStage.SEARCHING_THREADS, threads, "loading_model")
                    val loaded = runtime.load(
                        profile,
                        WhisperLoadOptions(threadCount = threads, warmUp = plan.warmUpLoads)
                    )
                    progress(WhisperBenchmarkStage.SEARCHING_THREADS, threads, "decoding_audio")
                    val loadKind = if (loadSequence++ == 0) {
                        WhisperBenchmarkLoadKind.COLD
                    } else {
                        WhisperBenchmarkLoadKind.HOT
                    }
                    plan.candidateAudioDurationsMs.forEach { durationMs ->
                        repeat(plan.candidateIterations) {
                            ensureThermalAllowsBenchmark()
                            candidateMeasurements += measureDecode(
                                runtime = runtime,
                                audio = audio,
                                durationMs = durationMs,
                                threadCount = threads,
                                loadKind = loadKind,
                                loadDurationMs = loaded.loadDurationMs,
                                warmUpDurationMs = loaded.warmUpTimings?.totalMs?.toLong()?.coerceAtLeast(0L) ?: 0L
                            )
                            completed += 1
                            progress(WhisperBenchmarkStage.SEARCHING_THREADS, threads)
                        }
                    }
                    runtime.unload(UnloadReason.USER_REQUEST)
                }
            }
        } catch (error: Throwable) {
            if (isOutOfMemory(error)) {
                return terminalRecord(
                    key = key,
                    profile = profile,
                    level = WhisperCertificationLevel.REMOTE_RECOMMENDED,
                    reason = "Local benchmark ran out of memory",
                    verificationDurationMs = verificationDuration,
                    highPerformanceCoreCount = hpc,
                    threadCandidates = candidates,
                    measurements = candidateMeasurements
                ).also(store::save)
            }
            if (isUnsupportedNativeModel(error)) {
                return terminalRecord(
                    key = key,
                    profile = profile,
                    level = WhisperCertificationLevel.UNSUPPORTED,
                    reason = "The native runtime cannot load this model on this device",
                    verificationDurationMs = verificationDuration,
                    highPerformanceCoreCount = hpc,
                    threadCandidates = candidates,
                    measurements = candidateMeasurements
                ).also(store::save)
            }
            throw error
        }

        val bestThreads = WhisperThreadSearch.selectBest(candidateMeasurements)
        val stability = mutableListOf<WhisperBenchmarkMeasurement>()
        val abortLatencies = mutableListOf<Long>()
        try {
            runtimeFactory().use { runtime ->
                progress(WhisperBenchmarkStage.STABILITY, bestThreads, "loading_model")
                val loaded = runtime.load(
                    profile,
                    WhisperLoadOptions(threadCount = bestThreads, warmUp = plan.warmUpLoads)
                )
                progress(WhisperBenchmarkStage.STABILITY, bestThreads, "decoding_audio")
                val loadKind = if (loadSequence++ == 0) {
                    WhisperBenchmarkLoadKind.COLD
                } else {
                    WhisperBenchmarkLoadKind.HOT
                }
                repeat(plan.stabilityIterations) {
                    ensureThermalAllowsBenchmark()
                    stability += measureDecode(
                        runtime = runtime,
                        audio = audio,
                        durationMs = plan.stabilityAudioDurationMs,
                        threadCount = bestThreads,
                        loadKind = loadKind,
                        loadDurationMs = loaded.loadDurationMs,
                        warmUpDurationMs = loaded.warmUpTimings?.totalMs?.toLong()?.coerceAtLeast(0L) ?: 0L
                    )
                    completed += 1
                    progress(WhisperBenchmarkStage.STABILITY, bestThreads)
                }
                progress(WhisperBenchmarkStage.CANCELLATION, bestThreads)
                repeat(plan.abortIterations) {
                    abortLatencies += measureAbortLatency(runtime, audio)
                    completed += 1
                    progress(WhisperBenchmarkStage.CANCELLATION, bestThreads)
                }
                runtime.unload(UnloadReason.USER_REQUEST)
            }
        } catch (error: Throwable) {
            if (isOutOfMemory(error)) {
                return terminalRecord(
                    key = key,
                    profile = profile,
                    level = WhisperCertificationLevel.REMOTE_RECOMMENDED,
                    reason = "Local stability test ran out of memory",
                    verificationDurationMs = verificationDuration,
                    highPerformanceCoreCount = hpc,
                    threadCandidates = candidates,
                    measurements = candidateMeasurements + stability,
                    abortLatenciesMs = abortLatencies
                ).also(store::save)
            }
            if (isUnsupportedNativeModel(error)) {
                return terminalRecord(
                    key = key,
                    profile = profile,
                    level = WhisperCertificationLevel.UNSUPPORTED,
                    reason = "The native runtime cannot execute this model on this device",
                    verificationDurationMs = verificationDuration,
                    highPerformanceCoreCount = hpc,
                    threadCandidates = candidates,
                    measurements = candidateMeasurements + stability,
                    abortLatenciesMs = abortLatencies
                ).also(store::save)
            }
            throw error
        }

        progress(WhisperBenchmarkStage.CERTIFYING, bestThreads)
        val record = certify(
            key = key,
            profile = profile,
            measurements = candidateMeasurements + stability,
            stabilityMeasurements = stability,
            verificationDurationMs = verificationDuration,
            abortLatenciesMs = abortLatencies,
            hpc = hpc,
            candidates = candidates,
            threadCount = bestThreads
        )
        store.save(record)
        completed = totalSteps
        progress(WhisperBenchmarkStage.COMPLETE, bestThreads)
        return record
    }

    private suspend fun measureDecode(
        runtime: LocalWhisperRuntime,
        audio: WhisperBenchmarkAudio,
        durationMs: Long,
        threadCount: Int,
        loadKind: WhisperBenchmarkLoadKind,
        loadDurationMs: Long,
        warmUpDurationMs: Long
    ): WhisperBenchmarkMeasurement {
        val pcm = audio.window(durationMs)
        val executionMode = if (durationMs <= FIRST_PARTIAL_PROBE_DURATION_MS) {
            WhisperExecutionMode.REALTIME_PARTIAL
        } else {
            WhisperExecutionMode.FINAL_ONLY
        }
        val measured = measureSystemMetrics {
            runtime.createSession(
                LocalWhisperSessionConfig(
                    language = audio.language,
                    noContext = true,
                    singleSegment = executionMode == WhisperExecutionMode.REALTIME_PARTIAL,
                    mode = executionMode
                )
            ).use { session ->
                session.decode(WhisperDecodeRequest(pcm, mode = executionMode)).also { result ->
                check(result.successful) { result.message ?: "Whisper correctness decode failed" }
                }
            }
        }
        val timing = measured.value.timings
        val transcript = measured.value.text
        return WhisperBenchmarkMeasurement(
            threadCount = threadCount,
            loadKind = loadKind,
            audioDurationMs = timing.audioMs.coerceAtLeast(durationMs),
            decodeDurationMs = timing.totalMs.toLong().coerceAtLeast(0L),
            realTimeFactor = timing.realTimeFactor.coerceAtLeast(0.0),
            loadDurationMs = loadDurationMs,
            warmUpDurationMs = warmUpDurationMs,
            peakPssBytes = measured.peakPssBytes,
            peakRssBytes = measured.peakRssBytes,
            peakNativeAllocatedBytes = measured.peakNativeAllocatedBytes,
            cpuTimeMs = measured.cpuTimeMs,
            energyDeltaNwh = measured.energyDeltaNwh,
            firstPartialLatencyMs = if (executionMode == WhisperExecutionMode.REALTIME_PARTIAL) {
                timing.totalMs.toLong().coerceAtLeast(0L)
            } else 0L,
            finalTailLatencyMs = if (executionMode == WhisperExecutionMode.FINAL_ONLY) {
                timing.totalMs.toLong().coerceAtLeast(0L)
            } else 0L,
            batteryTemperatureStartCelsius = measured.temperatureStartCelsius,
            batteryTemperatureEndCelsius = measured.temperatureEndCelsius,
            thermalStatusStart = measured.thermalStart,
            thermalStatusEnd = measured.thermalEnd,
            transcriptCorrect = transcriptMatches(transcript, audio.expectedTokens)
        )
    }

    private suspend fun measureAbortLatency(runtime: LocalWhisperRuntime, audio: WhisperBenchmarkAudio): Long =
        coroutineScope {
            runtime.createSession(LocalWhisperSessionConfig(language = audio.language, noContext = true)).use { session ->
                val decode = async(Dispatchers.Default) {
                    session.decode(WhisperDecodeRequest(audio.window(plan.stabilityAudioDurationMs)))
                }
                delay(plan.abortDelayMs)
                if (decode.isCompleted) return@use 0L
                val started = elapsedRealtime()
                session.requestAbort(AbortReason.USER_STOP)
                val result = withTimeoutOrNull(plan.abortTimeoutMs) { decode.await() }
                if (result == null) {
                    decode.cancel()
                    plan.abortTimeoutMs
                } else {
                    (elapsedRealtime() - started).coerceAtLeast(0L)
                }
            }
        }

    private suspend fun <T> measureSystemMetrics(block: suspend () -> T): MeasuredValue<T> = coroutineScope {
        val samples = CopyOnWriteArrayList<WhisperBenchmarkSystemSnapshot>()
        val running = AtomicBoolean(true)
        samples += snapshot()
        val sampler = launch(Dispatchers.Default) {
            while (running.get()) {
                delay(plan.metricSampleIntervalMs)
                samples += snapshot()
            }
        }
        val value = try {
            block()
        } finally {
            running.set(false)
            sampler.cancelAndJoin()
            samples += snapshot()
        }
        val first = samples.first()
        val last = samples.last()
        MeasuredValue(
            value = value,
            peakPssBytes = samples.maxOf(WhisperBenchmarkSystemSnapshot::pssBytes),
            peakRssBytes = samples.maxOf(WhisperBenchmarkSystemSnapshot::rssBytes),
            peakNativeAllocatedBytes = samples.maxOf(WhisperBenchmarkSystemSnapshot::nativeAllocatedBytes),
            cpuTimeMs = (last.cpuTimeMs - first.cpuTimeMs).coerceAtLeast(0L),
            energyDeltaNwh = if (first.energyCounterNwh != null && last.energyCounterNwh != null) {
                kotlin.math.abs(last.energyCounterNwh - first.energyCounterNwh)
            } else null,
            temperatureStartCelsius = first.batteryTemperatureCelsius,
            temperatureEndCelsius = last.batteryTemperatureCelsius,
            thermalStart = first.thermalStatus,
            thermalEnd = samples.maxOf(WhisperBenchmarkSystemSnapshot::thermalStatus)
        )
    }

    private fun certify(
        key: WhisperBenchmarkKey,
        profile: WhisperModelProfile,
        measurements: List<WhisperBenchmarkMeasurement>,
        stabilityMeasurements: List<WhisperBenchmarkMeasurement>,
        verificationDurationMs: Long,
        abortLatenciesMs: List<Long>,
        hpc: Int,
        candidates: List<Int>,
        threadCount: Int
    ): WhisperBenchmarkRecord {
        val stableRtf = stabilityMeasurements.map(WhisperBenchmarkMeasurement::realTimeFactor)
        val p50 = percentile(stableRtf, 0.50)
        val p95 = percentile(stableRtf, 0.95)
        val maxThermal = measurements.maxOfOrNull(WhisperBenchmarkMeasurement::thermalStatusEnd) ?: 0
        val peakPss = measurements.maxOfOrNull(WhisperBenchmarkMeasurement::peakPssBytes) ?: 0L
        val correct = stabilityMeasurements.count(WhisperBenchmarkMeasurement::transcriptCorrect) >=
            ((stabilityMeasurements.size + 1) / 2)
        val abortP95 = percentileLong(abortLatenciesMs, 0.95)
        val classification = WhisperCertificationClassifier.classify(
            profile = profile,
            rtfP95 = p95,
            transcriptCorrect = correct,
            maxThermalStatus = maxThermal,
            abortLatencyMsP95 = abortP95
        )
        val certification = WhisperCertification(
            key = key,
            level = classification.level,
            recommendedMode = classification.mode,
            recommendedThreadCount = threadCount,
            recommendedPartialIntervalMs = classification.partialIntervalMs,
            warmRtfP50 = p50,
            warmRtfP95 = p95,
            loadTimeMsP95 = percentileLong(measurements.map(WhisperBenchmarkMeasurement::loadDurationMs), 0.95),
            peakPssBytes = peakPss,
            maxThermalStatus = maxThermal,
            abortLatencyMsP95 = abortP95,
            createdAtEpochMs = clock(),
            failureReason = classification.failureReason
        )
        return WhisperBenchmarkRecord(
            certification = certification,
            measurements = measurements,
            verificationDurationMs = verificationDurationMs,
            abortLatenciesMs = abortLatenciesMs,
            highPerformanceCoreCount = hpc,
            threadCandidates = candidates
        )
    }

    private fun terminalRecord(
        key: WhisperBenchmarkKey,
        profile: WhisperModelProfile,
        level: WhisperCertificationLevel,
        reason: String,
        verificationDurationMs: Long,
        highPerformanceCoreCount: Int,
        threadCandidates: List<Int>,
        measurements: List<WhisperBenchmarkMeasurement> = emptyList(),
        abortLatenciesMs: List<Long> = emptyList()
    ): WhisperBenchmarkRecord {
        require(level in setOf(
            WhisperCertificationLevel.REMOTE_RECOMMENDED,
            WhisperCertificationLevel.UNSUPPORTED
        ))
        val threadCount = threadCandidates.firstOrNull() ?: 1
        return WhisperBenchmarkRecord(
            certification = WhisperCertification(
                key = key,
                level = level,
                recommendedMode = WhisperExecutionMode.REMOTE_NODE,
                recommendedThreadCount = threadCount,
                recommendedPartialIntervalMs = 0L,
                warmRtfP50 = percentile(measurements.map(WhisperBenchmarkMeasurement::realTimeFactor), 0.50),
                warmRtfP95 = percentile(measurements.map(WhisperBenchmarkMeasurement::realTimeFactor), 0.95),
                loadTimeMsP95 = percentileLong(measurements.map(WhisperBenchmarkMeasurement::loadDurationMs), 0.95),
                peakPssBytes = measurements.maxOfOrNull(WhisperBenchmarkMeasurement::peakPssBytes) ?: 0L,
                maxThermalStatus = measurements.maxOfOrNull(WhisperBenchmarkMeasurement::thermalStatusEnd) ?:
                    snapshot().thermalStatus,
                abortLatencyMsP95 = percentileLong(abortLatenciesMs, 0.95),
                createdAtEpochMs = clock(),
                failureReason = reason
            ),
            measurements = measurements,
            verificationDurationMs = verificationDurationMs,
            abortLatenciesMs = abortLatenciesMs,
            highPerformanceCoreCount = highPerformanceCoreCount,
            threadCandidates = threadCandidates
        )
    }

    private fun preflightFailure(
        profile: WhisperModelProfile,
        system: WhisperBenchmarkSystemSnapshot
    ): String? = when {
        system.systemLowMemory -> "Android reported system-wide low memory"
        !WhisperMemoryAdmissionPolicy.evaluate(
            profile = profile,
            availableMemoryBytes = system.availableMemoryBytes,
            currentPssBytes = system.pssBytes,
            lowMemory = system.systemLowMemory,
            safetyMarginBytes = MEMORY_SAFETY_MARGIN_BYTES
        ).allowed ->
            "The model does not have enough memory headroom on this device"
        system.thermalStatus >= THERMAL_SEVERE -> "The device is too hot to certify this model"
        else -> null
    }

    private fun ensureThermalAllowsBenchmark() {
        if (snapshot().thermalStatus >= THERMAL_MODERATE) {
            throw WhisperBenchmarkDeferredException("Benchmark paused because the device reached MODERATE thermal pressure")
        }
    }

    private fun transcriptMatches(transcript: String, expectedTokens: Set<String>): Boolean {
        val normalized = normalizeTranscript(transcript)
        if (normalized.isBlank()) return false
        val matched = expectedTokens.count { token -> normalizeTranscript(token) in normalized }
        return matched >= kotlin.math.ceil(expectedTokens.size * MIN_CORRECT_TOKEN_RATIO).toInt()
    }

    private fun normalizeTranscript(value: String): String = value
        .lowercase(Locale.ROOT)
        .map { character -> BENCHMARK_SCRIPT_NORMALIZATION[character] ?: character }
        .joinToString("")
        .replace(Regex("[^\\p{L}\\p{N}]+"), "")

    private fun isOutOfMemory(error: Throwable): Boolean = error is OutOfMemoryError ||
        (error as? LocalWhisperException)?.code == NativeWhisperCode.OUT_OF_MEMORY ||
        generateSequence(error.cause) { it.cause }.any {
            it is OutOfMemoryError || (it as? LocalWhisperException)?.code == NativeWhisperCode.OUT_OF_MEMORY
        }

    private fun isUnsupportedNativeModel(error: Throwable): Boolean =
        generateSequence(error as Throwable?) { it.cause }
            .mapNotNull { (it as? LocalWhisperException)?.code }
            .any { it in setOf(NativeWhisperCode.MODEL_CORRUPTED, NativeWhisperCode.UNSUPPORTED_MODEL) }

    private data class MeasuredValue<T>(
        val value: T,
        val peakPssBytes: Long,
        val peakRssBytes: Long,
        val peakNativeAllocatedBytes: Long,
        val cpuTimeMs: Long,
        val energyDeltaNwh: Long?,
        val temperatureStartCelsius: Double?,
        val temperatureEndCelsius: Double?,
        val thermalStart: Int,
        val thermalEnd: Int
    )

    private companion object {
        const val MEMORY_SAFETY_MARGIN_BYTES = 256L * 1024L * 1024L
        const val FIRST_PARTIAL_PROBE_DURATION_MS = 3_000L
        const val THERMAL_MODERATE = 2
        const val THERMAL_SEVERE = 3
        const val MIN_CORRECT_TOKEN_RATIO = 0.60
        val BENCHMARK_SCRIPT_NORMALIZATION = mapOf(
            '\u8a9e' to '\u8bed',
            '\u6e2c' to '\u6d4b',
            '\u8a66' to '\u8bd5',
            '\u5167' to '\u5185',
            '\u6eab' to '\u6e29',
            '\u61c9' to '\u5e94',
            '\u8b58' to '\u8bc6',
            '\u6e96' to '\u51c6'
        )
    }
}

object WhisperThreadSearch {
    fun candidates(highPerformanceCoreCount: Int): List<Int> {
        val cores = highPerformanceCoreCount.coerceIn(1, 16)
        return linkedSetOf(2, 3, 4, cores, minOf(6, cores))
            .map { it.coerceAtMost(cores).coerceAtLeast(1) }
            .distinct()
            .sorted()
    }

    fun selectBest(measurements: List<WhisperBenchmarkMeasurement>): Int {
        require(measurements.isNotEmpty()) { "Thread search has no measurements" }
        return measurements.groupBy(WhisperBenchmarkMeasurement::threadCount)
            .minWith(
                compareBy<Map.Entry<Int, List<WhisperBenchmarkMeasurement>>> { (_, values) ->
                    val p95 = percentile(values.map(WhisperBenchmarkMeasurement::realTimeFactor), 0.95)
                    val thermalPenalty = values.maxOf(WhisperBenchmarkMeasurement::thermalStatusEnd) * 0.10
                    val degradation = values.last().realTimeFactor - values.first().realTimeFactor
                    p95 + thermalPenalty + degradation.coerceAtLeast(0.0)
                }.thenBy { (_, values) ->
                    values.mapNotNull(WhisperBenchmarkMeasurement::energyDeltaNwh)
                        .takeIf { it.isNotEmpty() }
                        ?.average()
                        ?: Double.MAX_VALUE
                }
            ).key
    }
}

data class WhisperCertificationClassification(
    val level: WhisperCertificationLevel,
    val mode: WhisperExecutionMode,
    val partialIntervalMs: Long,
    val failureReason: String?
)

object WhisperCertificationClassifier {
    fun classify(
        profile: WhisperModelProfile,
        rtfP95: Double,
        transcriptCorrect: Boolean,
        maxThermalStatus: Int,
        abortLatencyMsP95: Long
    ): WhisperCertificationClassification {
        if (!transcriptCorrect) return unsupported("Benchmark transcript correctness failed")
        if (maxThermalStatus >= THERMAL_SEVERE) return remoteRecommended("Benchmark reached severe thermal pressure")
        if (abortLatencyMsP95 > MAX_ABORT_LATENCY_MS) return unsupported("Cancellation latency exceeded the safe limit")
        return when {
            rtfP95 <= REALTIME_RTF_P95 -> WhisperCertificationClassification(
                level = WhisperCertificationLevel.REALTIME,
                mode = WhisperExecutionMode.REALTIME_PARTIAL,
                partialIntervalMs = profile.defaultPartialIntervalMs.coerceIn(400L, 3_000L),
                failureReason = null
            )
            rtfP95 <= FINAL_RTF_P95 -> WhisperCertificationClassification(
                level = WhisperCertificationLevel.FINAL,
                mode = WhisperExecutionMode.FINAL_ONLY,
                partialIntervalMs = 0L,
                failureReason = null
            )
            else -> WhisperCertificationClassification(
                level = WhisperCertificationLevel.SECOND_PASS,
                mode = WhisperExecutionMode.SECOND_PASS,
                partialIntervalMs = 0L,
                failureReason = "RTF p95=${formatRtf(rtfP95)} limits this model to background correction"
            )
        }
    }

    private fun unsupported(reason: String) = WhisperCertificationClassification(
        level = WhisperCertificationLevel.UNSUPPORTED,
        mode = WhisperExecutionMode.REMOTE_NODE,
        partialIntervalMs = 0L,
        failureReason = reason
    )

    private fun remoteRecommended(reason: String) = WhisperCertificationClassification(
        level = WhisperCertificationLevel.REMOTE_RECOMMENDED,
        mode = WhisperExecutionMode.REMOTE_NODE,
        partialIntervalMs = 0L,
        failureReason = reason
    )

    private fun formatRtf(value: Double): String = "%.2f".format(Locale.US, value)

    private const val REALTIME_RTF_P95 = 0.80
    private const val FINAL_RTF_P95 = 1.50
    private const val MAX_ABORT_LATENCY_MS = 300L
    private const val THERMAL_SEVERE = 3
}
