package com.signalasi.chat.voice.asr.local

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.util.Log
import com.argmaxinc.whisperkit.ExperimentalWhisperKit
import com.argmaxinc.whisperkit.TranscriptionResult
import com.argmaxinc.whisperkit.WhisperKit
import com.signalasi.chat.voice.model.WhisperModelFamily
import com.signalasi.chat.voice.model.WhisperModelProfile
import com.signalasi.chat.voice.model.WhisperQuantization
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal object WhisperQnnSupport {
    fun isSupportedFamily(family: WhisperModelFamily): Boolean =
        family == WhisperModelFamily.TINY || family == WhisperModelFamily.BASE

    fun isQualcommDevice(): Boolean {
        val identity = buildList {
            add(Build.MANUFACTURER)
            add(Build.BRAND)
            add(Build.HARDWARE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Build.SOC_MANUFACTURER)
                add(Build.SOC_MODEL)
            }
        }.joinToString(" ").lowercase(Locale.ROOT)
        return listOf("qualcomm", "qcom", "snapdragon", "sm8").any(identity::contains)
    }

    fun hasPackagedRuntime(context: Context): Boolean {
        val names = File(context.applicationInfo.nativeLibraryDir)
            .listFiles()
            .orEmpty()
            .map { it.name.lowercase(Locale.ROOT) }
        return names.any { it == "libqnnhtp.so" } &&
            names.any { it == "libqnnsystem.so" } &&
            names.any { it == "libwhisperkit_jni.so" }
    }

    fun usesFourKilobytePages(): Boolean = runCatching {
        Os.sysconf(OsConstants._SC_PAGESIZE) == 4_096L
    }.getOrDefault(true)

    fun canInstall(context: Context): Boolean =
        isQualcommDevice() && usesFourKilobytePages() && hasPackagedRuntime(context)

    fun canUse(context: Context, profile: WhisperModelProfile): Boolean {
        val modelPackage = QnnWhisperPackageManager.packageForProfile(profile.id) ?: return false
        return isSupportedFamily(profile.family) && profile.quantization == WhisperQuantization.F16 &&
            canInstall(context) && QnnWhisperPackageManager.isInstalled(context, modelPackage)
    }
}

@OptIn(ExperimentalWhisperKit::class)
internal class QnnWhisperRuntime(
    context: Context,
    private val clock: () -> Long = System::currentTimeMillis,
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime
) : LocalWhisperRuntime {
    private val appContext = context.applicationContext
    private val lifecycleMutex = Mutex()
    private val decodeMutex = Mutex()
    private val closed = AtomicBoolean(false)
    private val sessions = ConcurrentHashMap<String, Session>()
    private val pendingResult = AtomicReference<CompletableDeferred<TranscriptionResult>?>(null)
    private val mutableState = MutableStateFlow<WhisperRuntimeState>(WhisperRuntimeState.Unloaded)
    private var whisperKit: WhisperKit? = null
    private var loadedModel: WhisperLoadedModel? = null
    private var pipelineInitialized = false

    override val state: StateFlow<WhisperRuntimeState> = mutableState.asStateFlow()

    override suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions): WhisperLoadedModel =
        lifecycleMutex.withLock {
            check(!closed.get()) { "QNN Whisper runtime is closed" }
            require(WhisperQnnSupport.canUse(appContext, profile)) {
                "QNN HTP is not available for ${profile.displayName} on this device"
            }
            loadedModel?.takeIf { it.profile.id == profile.id }?.let { return@withLock it }
            unloadLocked(UnloadReason.MODEL_SWITCH)
            mutableState.value = WhisperRuntimeState.Loading(profile.id)
            val startedAt = elapsedRealtime()
            try {
                val runtime = SignalASIWhisperKitFactory.create(
                    appContext,
                    modelVariant(profile),
                    { what, result ->
                        if (what == WhisperKit.TextOutputCallback.MSG_TEXT_OUT) {
                            pendingResult.get()?.complete(result)
                        }
                    },
                    QnnWhisperModelDownloader()
                )
                runtime.loadModel().collect { }
                runtime.init(SAMPLE_RATE_HZ, 1, 0L)
                pipelineInitialized = true
                val loaded = WhisperLoadedModel(
                    profile = profile,
                    threadCount = options.threadCount,
                    loadedAtMillis = clock(),
                    loadDurationMs = (elapsedRealtime() - startedAt).coerceAtLeast(0L),
                    warmUpTimings = null,
                    accelerationBackend = WhisperAccelerationBackend.QNN_HTP,
                    accelerationDetail = "Qualcomm QNN 2.45 / HTP NPU"
                )
                whisperKit = runtime
                loadedModel = loaded
                mutableState.value = WhisperRuntimeState.Ready(loaded)
                loaded
            } catch (error: Throwable) {
                runCatching { whisperKit?.deinitialize() }
                whisperKit = null
                loadedModel = null
                pipelineInitialized = false
                mutableState.value = WhisperRuntimeState.Failed(
                    WhisperRuntimeError(NativeWhisperCode.MODEL_NOT_LOADED, error.message.orEmpty())
                )
                throw error
            }
        }

    override suspend fun createSession(config: LocalWhisperSessionConfig): LocalWhisperSession =
        lifecycleMutex.withLock {
            check(!closed.get()) { "QNN Whisper runtime is closed" }
            requireNotNull(loadedModel) { "A QNN Whisper model must be loaded before creating a session" }
            Session(UUID.randomUUID().toString(), config).also { sessions[it.id] = it }
        }

    override suspend fun unload(reason: UnloadReason) = lifecycleMutex.withLock { unloadLocked(reason) }

    override suspend fun runBenchmark(request: BenchmarkRequest): BenchmarkResult {
        val loaded = requireNotNull(loadedModel) { "A QNN Whisper model must be loaded before benchmarking" }
        val timings = buildList {
            repeat(request.iterations) {
                createSession(LocalWhisperSessionConfig(language = request.language)).use { session ->
                    val result = session.decode(WhisperDecodeRequest(request.pcm16))
                    check(result.successful) { result.message ?: "QNN Whisper benchmark failed" }
                    add(result.timings)
                }
            }
        }
        val factors = timings.map(NativeWhisperTimings::realTimeFactor).sorted()
        return BenchmarkResult(loaded.profile.id, timings.size, timings, factors[factors.size / 2])
    }

    override fun requestAbortAll(reason: AbortReason) {
        pendingResult.getAndSet(null)?.cancel()
        sessions.values.forEach { it.requestAbort(reason) }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runBlocking { lifecycleMutex.withLock { unloadLocked(UnloadReason.APP_SHUTDOWN) } }
    }

    private fun unloadLocked(reason: UnloadReason) {
        if (whisperKit == null) {
            mutableState.value = WhisperRuntimeState.Unloaded
            return
        }
        mutableState.value = WhisperRuntimeState.Unloading(reason)
        pendingResult.getAndSet(null)?.cancel()
        sessions.values.toList().forEach(Session::close)
        sessions.clear()
        if (pipelineInitialized) {
            runCatching { whisperKit?.deinitialize() }
                .onFailure { Log.w(TAG, "QNN Whisper deinitialize failed", it) }
        }
        pipelineInitialized = false
        whisperKit = null
        loadedModel = null
        mutableState.value = WhisperRuntimeState.Unloaded
    }

    private fun modelVariant(profile: WhisperModelProfile): String = when (profile.family) {
        WhisperModelFamily.TINY -> WhisperKit.Builder.OPENAI_TINY
        WhisperModelFamily.BASE -> WhisperKit.Builder.OPENAI_BASE
        else -> error("QNN Whisper currently supports Tiny and Base model families")
    }

    private inner class Session(
        override val id: String,
        override val config: LocalWhisperSessionConfig
    ) : LocalWhisperSession {
        private val sessionClosed = AtomicBoolean(false)

        override suspend fun decode(request: WhisperDecodeRequest): NativeWhisperResult {
            check(!sessionClosed.get()) { "QNN Whisper session is closed" }
            return decodeMutex.withLock {
                val runtime = requireNotNull(whisperKit) { "QNN Whisper runtime is not loaded" }
                val loaded = requireNotNull(loadedModel)
                mutableState.value = WhisperRuntimeState.Decoding(id, request.mode)
                val startedAt = elapsedRealtime()
                if (!pipelineInitialized) {
                    runtime.init(SAMPLE_RATE_HZ, 1, 0L)
                    pipelineInitialized = true
                }
                val preparedAt = elapsedRealtime()
                val deferred = CompletableDeferred<TranscriptionResult>()
                check(pendingResult.compareAndSet(null, deferred)) { "Another QNN decode is already active" }
                try {
                    val pcm = request.pcm16.copyOfRange(request.offset, request.offset + request.length)
                    val bytes = pcm.toLittleEndianBytes().padToFrame()
                    val bufferedSeconds = runtime.transcribe(bytes)
                    val transcribedAt = elapsedRealtime()
                    check(bufferedSeconds >= 0) { "QNN Whisper rejected the PCM stream" }
                    val transcription = withTimeout(DECODE_TIMEOUT_MS) { deferred.await() }
                    val callbackAt = elapsedRealtime()
                    val totalMs = (elapsedRealtime() - startedAt).coerceAtLeast(1L)
                    val audioMs = pcm.size.toLong() * 1_000L / SAMPLE_RATE_HZ
                    val timings = NativeWhisperTimings(
                        sampleMs = 0.0,
                        encodeMs = 0.0,
                        decodeMs = totalMs.toDouble(),
                        totalMs = totalMs.toDouble(),
                        audioMs = audioMs,
                        realTimeFactor = totalMs.toDouble() / audioMs.coerceAtLeast(1L)
                    )
                    val segments = transcription.segments.ifEmpty {
                        listOf(com.argmaxinc.whisperkit.TranscriptionSegment(transcription.text))
                    }
                    Log.i(
                        TAG,
                        "decode id=$id audioMs=$audioMs paddedBytes=${bytes.size} " +
                            "prepareMs=${preparedAt - startedAt} " +
                            "transcribeMs=${transcribedAt - preparedAt} " +
                            "callbackMs=${callbackAt - transcribedAt} totalMs=$totalMs " +
                            "bufferedSeconds=$bufferedSeconds textChars=${transcription.text.length}"
                    )
                    NativeWhisperResult(
                        codeValue = NativeWhisperCode.OK.wireValue,
                        segments = segments.map {
                            NativeWhisperSegment(0L, audioMs, it.text, 0f, 0f)
                        }.toTypedArray(),
                        detectedLanguage = config.language.takeUnless { it == "auto" },
                        timings = timings,
                        aborted = false,
                        message = null
                    )
                } catch (error: Throwable) {
                    NativeWhisperResult.failure(
                        if (error is OutOfMemoryError) NativeWhisperCode.OUT_OF_MEMORY else NativeWhisperCode.DECODE_FAILED,
                        error.message ?: "QNN Whisper decode failed"
                    )
                } finally {
                    pendingResult.compareAndSet(deferred, null)
                    if (pipelineInitialized) {
                        runCatching { runtime.deinitialize() }
                            .onFailure { Log.w(TAG, "QNN Whisper session reset failed", it) }
                        pipelineInitialized = false
                    }
                    if (!closed.get() && loadedModel?.profile?.id == loaded.profile.id) {
                        mutableState.value = WhisperRuntimeState.Ready(loaded)
                    }
                }
            }
        }

        override fun requestAbort(reason: AbortReason) {
            if (!sessionClosed.get()) pendingResult.getAndSet(null)?.cancel()
        }

        override fun close() {
            if (!sessionClosed.compareAndSet(false, true)) return
            sessions.remove(id, this)
        }
    }

    private fun ShortArray.toLittleEndianBytes(): ByteArray =
        ByteBuffer.allocate(size * 2).order(ByteOrder.LITTLE_ENDIAN).apply {
            asShortBuffer().put(this@toLittleEndianBytes)
        }.array()

    private fun ByteArray.padToFrame(): ByteArray {
        val remainder = size % FRAME_BYTES
        if (remainder == 0) return this
        return copyOf(size + FRAME_BYTES - remainder)
    }

    private companion object {
        const val TAG = "SignalASIQnnWhisper"
        const val SAMPLE_RATE_HZ = 16_000
        const val FRAME_BYTES = 30 * SAMPLE_RATE_HZ * 2
        const val DECODE_TIMEOUT_MS = 180_000L
    }
}
