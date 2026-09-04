package com.galaxyssi.chat.voice.benchmark

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import com.galaxyssi.chat.BuildConfig
import com.galaxyssi.chat.LocalModelDeviceSnapshotDetector
import com.galaxyssi.chat.WhisperModelManager
import com.galaxyssi.chat.voice.asr.local.DefaultLocalWhisperRuntime
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.sync.Mutex
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.floor
import kotlin.math.roundToInt

object WhisperBenchmarkManager {
    const val BENCHMARK_AUDIO_VERSION = "zh_cn_v2"
    private const val BENCHMARK_AUDIO_ASSET = "voice/benchmark/zh_cn_v1.wav"
    private const val BENCHMARK_AUDIO_SHA256 = "9a3505df8e1d6c1a60c87c7f7cc6e303e882189512d218f075a20f4784db05da"
    private const val STORE_NAME = "benchmark-certifications.json"

    private val benchmarkMutex = Mutex()
    private val runningProfiles = ConcurrentHashMap.newKeySet<String>()
    private val activeBenchmarkJob = AtomicReference<Job?>(null)
    private val thermalController = WhisperThermalController()

    fun isRunning(profileId: String): Boolean = profileId in runningProfiles

    fun cancelForInteractiveVoice() {
        activeBenchmarkJob.get()?.cancel(WhisperBenchmarkPreemptedException())
    }

    fun current(context: Context, profile: WhisperModelProfile): WhisperBenchmarkRecord? {
        val appContext = context.applicationContext
        val record = store(appContext).find(key(appContext, profile))
        if (record == null && WhisperModelManager.isAvailable(appContext, profile)) {
            WhisperModelManager.resetCertification(appContext, profile)
        }
        return record
    }

    fun latest(context: Context, profile: WhisperModelProfile): WhisperBenchmarkRecord? =
        store(context.applicationContext).latestForProfile(profile.id)

    suspend fun benchmark(
        context: Context,
        profile: WhisperModelProfile,
        force: Boolean = false,
        onProgress: (WhisperBenchmarkProgress) -> Unit = {}
    ): WhisperBenchmarkRecord {
        if (!benchmarkMutex.tryLock()) {
            throw WhisperBenchmarkBusyException()
        }
        val appContext = context.applicationContext
        val benchmarkJob = currentCoroutineContext()[Job] ?: run {
            benchmarkMutex.unlock()
            error("Whisper benchmark requires a coroutine Job")
        }
        activeBenchmarkJob.set(benchmarkJob)
        runningProfiles += profile.id
        WhisperModelManager.markBenchmarking(profile.id, true)
        return try {
            val audio = WhisperBenchmarkAudioLoader.load(appContext)
            val runner = WhisperBenchmarkRunner(
                runtimeFactory = { DefaultLocalWhisperRuntime(appContext) },
                keyFactory = { model, audioVersion -> key(appContext, model, audioVersion) },
                snapshot = { controlledSnapshot(appContext) },
                highPerformanceCoreCount = WhisperBenchmarkSystemProbe::highPerformanceCoreCount,
                verifyModel = { model -> WhisperModelManager.ensureVerifiedFile(appContext, model) },
                elapsedRealtime = SystemClock::elapsedRealtime,
                clock = System::currentTimeMillis,
                store = store(appContext),
                plan = WhisperBenchmarkPlan.forProfile(profile)
            )
            runner.run(profile, audio, force, onProgress).also { record ->
                WhisperModelManager.updateCertification(appContext, profile, record.certification.level)
            }
        } finally {
            activeBenchmarkJob.compareAndSet(benchmarkJob, null)
            runningProfiles -= profile.id
            WhisperModelManager.markBenchmarking(profile.id, false)
            benchmarkMutex.unlock()
        }
    }

    fun remove(context: Context, profile: WhisperModelProfile) {
        store(context.applicationContext).removeForProfile(profile.id)
    }

    fun decide(
        context: Context,
        userMode: WhisperUserVoiceMode,
        selectedProfileId: String?,
        foreground: Boolean,
        recentRealTimeFactor: Double? = null,
        decodeQueueDepth: Int = 0,
        utteranceDurationMs: Long = 0L,
        highRiskTask: Boolean = false,
        remoteAllowed: Boolean = false,
        accuracySensitiveTask: Boolean = false
    ): WhisperRuntimeDecision {
        val appContext = context.applicationContext
        val device = LocalModelDeviceSnapshotDetector.capture(appContext)
        return WhisperRuntimePolicyEngine.decide(
            WhisperRuntimePolicyInput(
                userMode = userMode,
                selectedProfileId = selectedProfileId,
                candidates = WhisperModelManager.models.map { profile ->
                    WhisperRuntimeCandidate(
                        profile = profile,
                        installed = WhisperModelManager.isAvailable(appContext, profile),
                        certification = current(appContext, profile)?.certification,
                        loaded = WhisperModelManager.isLoaded(profile)
                    )
                },
                environment = WhisperRuntimeEnvironment(
                    network = networkState(appContext),
                    availableMemoryBytes = device.availableMemoryBytes,
                    currentPssBytes = Debug.getPss().toLong() * 1_024L,
                    thermalStatus = thermalController.effectiveStatus(
                        device.thermalStatus ?: PowerManager.THERMAL_STATUS_NONE
                    ),
                    batteryPercent = device.batteryPercent,
                    charging = device.charging,
                    foreground = foreground,
                    recentRealTimeFactor = recentRealTimeFactor,
                    decodeQueueDepth = decodeQueueDepth.coerceAtLeast(0),
                    utteranceDurationMs = utteranceDurationMs.coerceAtLeast(0L),
                    highRiskTask = highRiskTask,
                    remoteAllowed = remoteAllowed,
                    accuracySensitiveTask = accuracySensitiveTask
                )
            )
        )
    }

    fun key(context: Context, profile: WhisperModelProfile): WhisperBenchmarkKey = key(
        context.applicationContext,
        profile,
        "$BENCHMARK_AUDIO_VERSION:${BENCHMARK_AUDIO_SHA256.take(16)}"
    )

    private fun key(
        context: Context,
        profile: WhisperModelProfile,
        benchmarkAudioVersion: String
    ): WhisperBenchmarkKey = WhisperBenchmarkKey(
        manufacturer = Build.MANUFACTURER.ifBlank { "unknown" },
        device = Build.DEVICE.ifBlank { Build.MODEL.ifBlank { "unknown" } },
        soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL.ifBlank { Build.HARDWARE.ifBlank { "unknown" } }
        } else {
            Build.HARDWARE.ifBlank { "unknown" }
        },
        androidApi = Build.VERSION.SDK_INT,
        appVersionCode = BuildConfig.VERSION_CODE,
        whisperNativeVersion = BuildConfig.WHISPER_NATIVE_VERSION,
        nativeBuildFingerprint = BuildConfig.WHISPER_NATIVE_BUILD_FINGERPRINT,
        modelProfileId = profile.id,
        modelSha256 = profile.sha256,
        benchmarkAudioVersion = benchmarkAudioVersion
    )

    private fun store(context: Context): WhisperBenchmarkStore = WhisperBenchmarkStore(
        File(context.filesDir, "voice/whisper/$STORE_NAME")
    )

    private fun controlledSnapshot(context: Context): WhisperBenchmarkSystemSnapshot {
        val snapshot = WhisperBenchmarkSystemProbe.snapshot(context)
        return snapshot.copy(thermalStatus = thermalController.effectiveStatus(snapshot.thermalStatus))
    }

    private fun networkState(context: Context): WhisperNetworkState {
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: return WhisperNetworkState.OFFLINE
        val network = manager.activeNetwork ?: return WhisperNetworkState.OFFLINE
        val capabilities = manager.getNetworkCapabilities(network) ?: return WhisperNetworkState.OFFLINE
        return if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            if (manager.isActiveNetworkMetered) WhisperNetworkState.METERED else WhisperNetworkState.UNMETERED
        } else {
            WhisperNetworkState.OFFLINE
        }
    }
}

class WhisperBenchmarkBusyException : IllegalStateException("Another Whisper benchmark is already running")

class WhisperBenchmarkPreemptedException : CancellationException(
    "Whisper benchmark was preempted by interactive voice input"
)

object WhisperBenchmarkSystemProbe {
    fun snapshot(context: Context): WhisperBenchmarkSystemSnapshot {
        val memory = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java)?.getMemoryInfo(memory)
        val power = context.getSystemService(PowerManager::class.java)
        val energy = context.getSystemService(BatteryManager::class.java)
            ?.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)
            ?.takeUnless { it == Long.MIN_VALUE }
        val batteryTemperature = runCatching {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                ?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?.takeUnless { it == Int.MIN_VALUE }
                ?.div(10.0)
        }.getOrNull()
        return WhisperBenchmarkSystemSnapshot(
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L),
            systemLowMemory = memory.lowMemory,
            pssBytes = Debug.getPss().toLong().coerceAtLeast(0L) * 1_024L,
            rssBytes = processRssBytes(),
            nativeAllocatedBytes = Debug.getNativeHeapAllocatedSize().coerceAtLeast(0L),
            cpuTimeMs = Process.getElapsedCpuTime().coerceAtLeast(0L),
            energyCounterNwh = energy,
            batteryTemperatureCelsius = batteryTemperature,
            thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                power?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
            } else {
                PowerManager.THERMAL_STATUS_NONE
            }
        )
    }

    fun highPerformanceCoreCount(): Int {
        val logical = Runtime.getRuntime().availableProcessors().coerceIn(1, 16)
        val capacities = (0 until logical).mapNotNull { cpu ->
            sequenceOf(
                File("/sys/devices/system/cpu/cpu$cpu/cpu_capacity"),
                File("/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq")
            ).mapNotNull { file -> runCatching { file.readText().trim().toLong() }.getOrNull() }
                .firstOrNull()
        }
        if (capacities.size != logical || capacities.distinct().size <= 1) return minOf(logical, 4)
        val max = capacities.maxOrNull() ?: return minOf(logical, 4)
        return capacities.count { it >= max * 90L / 100L }.coerceIn(1, logical)
    }

    private fun processRssBytes(): Long = runCatching {
        File("/proc/self/status").useLines { lines ->
            val value = lines.firstOrNull { it.startsWith("VmRSS:") }
                ?.substringAfter(':')
                ?.trim()
                ?.substringBefore(' ')
                ?.toLongOrNull()
                ?: 0L
            value * 1_024L
        }
    }.getOrDefault(0L)
}

object WhisperBenchmarkAudioLoader {
    fun load(context: Context): WhisperBenchmarkAudio {
        val bytes = context.assets.open("voice/benchmark/zh_cn_v1.wav").use { it.readBytes() }
        val actualSha = sha256(bytes)
        require(actualSha == "9a3505df8e1d6c1a60c87c7f7cc6e303e882189512d218f075a20f4784db05da") {
            "Whisper benchmark audio checksum mismatch"
        }
        return WhisperBenchmarkAudio(
            version = "${WhisperBenchmarkManager.BENCHMARK_AUDIO_VERSION}:${actualSha.take(16)}",
            pcm16 = decodePcmWave(bytes),
            expectedTokens = setOf(
                "\u4f60\u597d",
                "\u672c\u5730",
                "\u8bed\u97f3",
                "\u6d4b\u8bd5",
                "\u6027\u80fd",
                "\u5185\u5b58",
                "\u6e29\u5ea6",
                "\u53d6\u6d88"
            )
        )
    }

    private fun decodePcmWave(bytes: ByteArray): ShortArray {
        require(bytes.size >= 44 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
            String(bytes, 8, 4, Charsets.US_ASCII) == "WAVE") { "Invalid benchmark PCM wave file" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bitsPerSample = 0
        var audioFormat = 0
        var pcmBytes: ByteArray? = null
        while (offset + 8 <= bytes.size) {
            val chunkId = String(bytes, offset, 4, Charsets.US_ASCII)
            val chunkSize = buffer.getInt(offset + 4).coerceAtLeast(0)
            val payloadOffset = offset + 8
            if (payloadOffset + chunkSize > bytes.size) break
            when (chunkId) {
                "fmt " -> if (chunkSize >= 16) {
                    audioFormat = buffer.getShort(payloadOffset).toInt() and 0xffff
                    channels = buffer.getShort(payloadOffset + 2).toInt() and 0xffff
                    sampleRate = buffer.getInt(payloadOffset + 4)
                    bitsPerSample = buffer.getShort(payloadOffset + 14).toInt() and 0xffff
                }
                "data" -> pcmBytes = bytes.copyOfRange(payloadOffset, payloadOffset + chunkSize)
            }
            offset = payloadOffset + chunkSize + (chunkSize and 1)
        }
        require(audioFormat == 1 && bitsPerSample == 16) { "Benchmark audio must be PCM16" }
        require(sampleRate > 0 && channels > 0) { "Benchmark audio format is incomplete" }
        return resamplePcm16(requireNotNull(pcmBytes), sampleRate, channels)
    }

    private fun resamplePcm16(bytes: ByteArray, sourceRate: Int, channels: Int): ShortArray {
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val frames = buffer.remaining() / channels
        val mono = ShortArray(frames)
        repeat(frames) { frame ->
            var sum = 0L
            repeat(channels) { channel -> sum += buffer.get(frame * channels + channel).toLong() }
            mono[frame] = (sum / channels).coerceIn(Short.MIN_VALUE.toLong(), Short.MAX_VALUE.toLong()).toShort()
        }
        if (sourceRate == WhisperBenchmarkAudio.SAMPLE_RATE_HZ) return mono
        val outputSize = (frames.toLong() * WhisperBenchmarkAudio.SAMPLE_RATE_HZ / sourceRate).toInt()
        return ShortArray(outputSize.coerceAtLeast(1)) { index ->
            val source = index.toDouble() * sourceRate / WhisperBenchmarkAudio.SAMPLE_RATE_HZ
            val left = floor(source).toInt().coerceIn(0, mono.lastIndex)
            val right = (left + 1).coerceAtMost(mono.lastIndex)
            val fraction = source - left
            (mono[left] + (mono[right] - mono[left]) * fraction)
                .roundToInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte) }
}
