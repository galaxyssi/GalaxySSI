package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.os.Build
import android.os.SystemClock
import com.galaxyssi.chat.VoiceAssistantSettings
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

internal object WhisperQnnSupport {
    fun isSupportedFamily(family: WhisperModelFamily): Boolean = family in setOf(
        WhisperModelFamily.TINY,
        WhisperModelFamily.BASE,
        WhisperModelFamily.SMALL
    )

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
            .toSet()
        return "libqnnhtp.so" in names &&
            "libqnnsystem.so" in names &&
            "libonnxruntime_providers_qnn.so" in names &&
            "libgalaxyssi_asr.so" in names
    }

    fun canInstall(context: Context): Boolean {
        if (!isQualcommDevice() || !hasPackagedRuntime(context)) return false
        val compact = CompactWhisperQnnModelCatalog.tinyFloat
        val store = LargeTurboQnnModelStore(
            filesDirectory = context.applicationContext.filesDir,
            modelRootName = compact.modelRootName,
            deviceRootName = CompactWhisperQnnModelCatalog.DEVICE_ROOT_NAME
        )
        val snapshot = AndroidLargeTurboQnnDeviceCapabilityDetector(
            context.applicationContext,
            store,
            compact.manifest
        ).snapshot(QnnContextModelState.NOT_INSTALLED)
        return LargeTurboQnnDevicePolicy(compact.manifest).evaluate(snapshot).eligibility !=
            QnnAsrEligibility.FALLBACK_REQUIRED
    }

    fun canUse(context: Context, profile: WhisperModelProfile): Boolean {
        val modelPackage = QnnWhisperPackageManager.selectedPackage(context) ?: return false
        return isSupportedFamily(profile.family) && modelPackage.profileId == profile.id &&
            canInstall(context) && QnnWhisperPackageManager.isInstalled(context, modelPackage)
    }
}

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
    private val mutableState = MutableStateFlow<WhisperRuntimeState>(WhisperRuntimeState.Unloaded)
    private var bundle: RuntimeBundle? = null
    private var loadedModel: WhisperLoadedModel? = null

    override val state: StateFlow<WhisperRuntimeState> = mutableState.asStateFlow()

    override suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions): WhisperLoadedModel =
        lifecycleMutex.withLock {
            check(!closed.get()) { "QNN Whisper runtime is closed" }
            val modelPackage = requireNotNull(QnnWhisperPackageManager.selectedPackage(appContext)) {
                "No compact QNN Whisper package is selected"
            }
            require(modelPackage.profileId == profile.id && WhisperQnnSupport.canUse(appContext, profile)) {
                "QNN HTP is not available for ${profile.displayName} on this device"
            }
            loadedModel?.takeIf { it.profile.id == profile.id && bundle?.modelPackage?.id == modelPackage.id }
                ?.let { return@withLock it }
            unloadLocked(UnloadReason.MODEL_SWITCH)
            mutableState.value = WhisperRuntimeState.Loading(profile.id)
            val startedAt = elapsedRealtime()
            try {
                val opened = openBundle(modelPackage)
                if (options.warmUp) {
                    val silence = FloatArray(opened.contract.melBins * opened.contract.melFrames) { -1.5F }
                    opened.transcriber.transcribe(silence, "zh", 1)
                }
                val loaded = WhisperLoadedModel(
                    profile = profile,
                    threadCount = 1,
                    loadedAtMillis = clock(),
                    loadDurationMs = (elapsedRealtime() - startedAt).coerceAtLeast(0L),
                    warmUpTimings = null,
                    accelerationBackend = WhisperAccelerationBackend.QNN_HTP,
                    accelerationDetail = "Qualcomm QNN 2.45 / HTP / ${modelPackage.displayName}"
                )
                bundle = opened
                loadedModel = loaded
                mutableState.value = WhisperRuntimeState.Ready(loaded)
                loaded
            } catch (error: Throwable) {
                bundle?.close()
                bundle = null
                loadedModel = null
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
        bundle?.network?.cancelActiveRun()
        sessions.values.forEach { it.requestAbort(reason) }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runBlocking { lifecycleMutex.withLock { unloadLocked(UnloadReason.APP_SHUTDOWN) } }
    }

    private fun openBundle(modelPackage: QnnWhisperPackage): RuntimeBundle {
        val directory = QnnWhisperPackageManager.modelRoot(appContext, modelPackage).canonicalFile
        require(directory.isDirectory) { "Compact QNN Whisper model is not installed" }
        val contract = CompactWhisperQnnContractParser.parse(directory, modelPackage.manifest)
        val wrappers = WhisperQnnContextAssetInstaller(
            AndroidQnnContextAssetSource(appContext.assets),
            CompactWhisperQnnContextAssets.forPackage(modelPackage)
        ).ensureInstalled(directory)
        val tokenizer = WhisperTiktokenTokenizer.load(
            File(directory, "tokenizer.tiktoken"),
            File(directory, "generation_config.json")
        )
        val nativeDirectory = File(appContext.applicationInfo.nativeLibraryDir).canonicalFile
        val network = OrtWhisperQnnNetwork.open(
            modelDirectory = directory,
            wrapperFiles = wrappers,
            contract = contract,
            generation = tokenizer.generation,
            providerLibrary = requireNativeLibrary(nativeDirectory, "libonnxruntime_providers_qnn.so"),
            htpBackendLibrary = requireNativeLibrary(nativeDirectory, "libQnnHtp.so")
        )
        return RuntimeBundle(
            modelPackage = modelPackage,
            modelDirectory = directory,
            contract = contract,
            network = network,
            transcriber = WhisperGreedyTranscriber(network, tokenizer, contract)
        )
    }

    private fun unloadLocked(reason: UnloadReason) {
        if (bundle == null) {
            mutableState.value = WhisperRuntimeState.Unloaded
            return
        }
        mutableState.value = WhisperRuntimeState.Unloading(reason)
        sessions.values.toList().forEach(Session::close)
        sessions.clear()
        bundle?.close()
        bundle = null
        loadedModel = null
        mutableState.value = WhisperRuntimeState.Unloaded
    }

    private inner class Session(
        override val id: String,
        override val config: LocalWhisperSessionConfig
    ) : LocalWhisperSession {
        private val sessionClosed = AtomicBoolean(false)
        private val aborted = AtomicBoolean(false)

        override suspend fun decode(request: WhisperDecodeRequest): NativeWhisperResult {
            check(!sessionClosed.get()) { "QNN Whisper session is closed" }
            return decodeMutex.withLock {
                val active = requireNotNull(bundle) { "QNN Whisper runtime is not loaded" }
                val loaded = requireNotNull(loadedModel)
                aborted.set(false)
                mutableState.value = WhisperRuntimeState.Decoding(id, request.mode)
                val startedAt = elapsedRealtime()
                try {
                    val featureStartedAt = elapsedRealtime()
                    val features = CompactWhisperQnnFeatureExtractor.extract(
                        active.modelDirectory,
                        active.contract.melBins,
                        request.pcm16,
                        request.offset,
                        request.length
                    )
                    val featureMs = (elapsedRealtime() - featureStartedAt).coerceAtLeast(0L)
                    val transcription = active.transcriber.transcribe(
                        features,
                        normalizeWhisperLanguage(config.language),
                        config.maxTokens.takeIf { it > 0 }?.coerceAtMost(160) ?: 160
                    ) { aborted.get() || sessionClosed.get() }
                    val totalMs = (elapsedRealtime() - startedAt).coerceAtLeast(1L)
                    val audioMs = request.length.toLong() * 1_000L / request.sampleRateHz
                    val timings = NativeWhisperTimings(
                        sampleMs = featureMs.toDouble(),
                        encodeMs = transcription.encoderNanos / 1_000_000.0,
                        decodeMs = transcription.decoderNanos / 1_000_000.0,
                        totalMs = totalMs.toDouble(),
                        audioMs = audioMs,
                        realTimeFactor = totalMs.toDouble() / audioMs.coerceAtLeast(1L)
                    )
                    NativeWhisperResult(
                        codeValue = NativeWhisperCode.OK.wireValue,
                        segments = arrayOf(
                            NativeWhisperSegment(0L, audioMs, transcription.text, 0F, 0F)
                        ),
                        detectedLanguage = transcription.detectedLanguage,
                        timings = timings,
                        aborted = false,
                        message = null
                    )
                } catch (error: Throwable) {
                    NativeWhisperResult.failure(
                        when {
                            aborted.get() || error is QnnInferenceCancelledException -> NativeWhisperCode.ABORTED
                            error is OutOfMemoryError -> NativeWhisperCode.OUT_OF_MEMORY
                            else -> NativeWhisperCode.DECODE_FAILED
                        },
                        error.message ?: "QNN Whisper decode failed"
                    )
                } finally {
                    if (!closed.get() && loadedModel?.profile?.id == loaded.profile.id) {
                        mutableState.value = WhisperRuntimeState.Ready(loaded)
                    }
                }
            }
        }

        override fun requestAbort(reason: AbortReason) {
            aborted.set(true)
            bundle?.network?.cancelActiveRun()
        }

        override fun close() {
            if (!sessionClosed.compareAndSet(false, true)) return
            aborted.set(true)
            sessions.remove(id, this)
        }
    }

    private data class RuntimeBundle(
        val modelPackage: QnnWhisperPackage,
        val modelDirectory: File,
        val contract: QnnWhisperModelContract,
        val network: OrtWhisperQnnNetwork,
        val transcriber: WhisperGreedyTranscriber
    ) : AutoCloseable {
        override fun close() = network.close()
    }

    private fun requireNativeLibrary(directory: File, name: String): File =
        File(directory, name).canonicalFile.also { library ->
            require(library.isFile && library.canRead()) { "$name is unavailable" }
        }

    private fun normalizeWhisperLanguage(language: String): String {
        val normalized = language.trim().lowercase(Locale.ROOT).replace('_', '-')
        return when {
            normalized.isBlank() -> "zh"
            normalized == "auto" -> "auto"
            else -> normalized.substringBefore('-')
        }
    }
}
