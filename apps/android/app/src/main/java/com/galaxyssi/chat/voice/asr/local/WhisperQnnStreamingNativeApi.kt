package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal interface WhisperQnnTranscriberRuntime : AutoCloseable {
    fun transcribe(melFeatures: FloatBuffer, language: String, maxTokens: Int): WhisperQnnTranscription
    fun cancelActive() = Unit
}

internal fun interface WhisperQnnTranscriberRuntimeFactory {
    fun open(modelDirectory: File): WhisperQnnTranscriberRuntime
}

internal class AndroidWhisperQnnAsrApi private constructor(
    private val runtimeFactory: WhisperQnnTranscriberRuntimeFactory,
    private val frontendFactory: WhisperQnnAudioFrontendFactory,
    private val residentBytes: () -> Long,
    private val elapsedRealtimeMs: () -> Long
) : QnnAsrNativeApi {
    private val nextHandle = AtomicLong(1L)
    private val resources = ConcurrentHashMap<Long, QnnRuntimeResource>()

    constructor(context: Context) : this(
        runtimeFactory = WhisperQnnTranscriberRuntimeFactory { directory ->
            WhisperLargeTurboQnnRuntime.open(context.applicationContext, directory)
        },
        frontendFactory = NativeWhisperQnnAudioFrontend,
        residentBytes = {
            Runtime.getRuntime().let { runtime -> runtime.totalMemory() - runtime.freeMemory() }
        },
        elapsedRealtimeMs = SystemClock::elapsedRealtime
    )

    internal constructor(
        runtimeFactory: WhisperQnnTranscriberRuntimeFactory,
        frontendFactory: WhisperQnnAudioFrontendFactory,
        elapsedRealtimeMs: () -> Long = { System.nanoTime() / 1_000_000L }
    ) : this(runtimeFactory, frontendFactory, { 0L }, elapsedRealtimeMs)

    override fun create(
        modelDirectory: String,
        runtimeDirectory: String,
        callback: QnnAsrNativeCallback
    ): Long {
        val model = File(modelDirectory).canonicalFile
        val runtimeRoot = File(runtimeDirectory).canonicalFile
        require(runtimeRoot.exists() || runtimeRoot.mkdirs()) { "QNN ASR runtime directory is unavailable" }
        require(runtimeRoot.isDirectory && runtimeRoot.canWrite()) { "QNN ASR runtime directory is unavailable" }
        val runtime = runtimeFactory.open(model)
        val handle = nextHandle.getAndIncrement().takeIf { it > 0L } ?: error("QNN ASR handle space exhausted")
        val resource = QnnRuntimeResource(
            model,
            runtime,
            frontendFactory,
            callback,
            residentBytes,
            elapsedRealtimeMs
        )
        check(resources.putIfAbsent(handle, resource) == null)
        return handle
    }

    override fun start(handle: Long, sessionToken: Long, config: AsrConfig): Boolean =
        resource(handle)?.start(sessionToken, config) ?: false

    override fun pushPcm(handle: Long, sessionToken: Long, pcm: ByteBuffer, sampleCount: Int): Boolean =
        resource(handle)?.pushPcm(sessionToken, pcm, sampleCount) ?: false

    override fun stop(handle: Long, sessionToken: Long) {
        resource(handle)?.stop(sessionToken)
    }

    override fun cancel(handle: Long, sessionToken: Long) {
        resource(handle)?.cancel(sessionToken)
    }

    override fun pause(handle: Long, sessionToken: Long) {
        resource(handle)?.pause(sessionToken)
    }

    override fun resume(handle: Long, sessionToken: Long): Boolean =
        resource(handle)?.resume(sessionToken) ?: false

    override fun updateRuntimePolicy(handle: Long, policy: AsrRuntimePolicy) {
        resource(handle)?.updateRuntimePolicy(policy)
    }

    override fun destroy(handle: Long) {
        resources.remove(handle)?.close()
    }

    private fun resource(handle: Long): QnnRuntimeResource? = handle.takeIf { it > 0L }?.let(resources::get)
}

object HighAccuracyLocalAsrEngineFactory {
    fun create(context: Context): LocalAsrEngine {
        val application = context.applicationContext
        val runtimeDirectory = File(application.noBackupFilesDir, "voice/qnn/runtime").apply {
            require(exists() || mkdirs()) { "QNN ASR runtime directory is unavailable" }
        }
        return WhisperLargeTurboAsrEngine(
            native = AndroidWhisperQnnAsrApi(application),
            runtimeDirectory = runtimeDirectory.path
        )
    }
}

private class QnnRuntimeResource(
    private val modelDirectory: File,
    private val runtime: WhisperQnnTranscriberRuntime,
    private val frontendFactory: WhisperQnnAudioFrontendFactory,
    private val callback: QnnAsrNativeCallback,
    private val residentBytes: () -> Long,
    private val elapsedRealtimeMs: () -> Long
) : AutoCloseable {
    private val lock = Any()
    private val closed = AtomicBoolean(false)
    private val callbackExecutor = namedSingleThreadExecutor("GalaxySSI-ASR-Callback")
    private var active: QnnStreamingSession? = null
    private var runtimePolicy: AsrRuntimePolicy? = null

    fun start(sessionToken: Long, config: AsrConfig): Boolean = synchronized(lock) {
        if (closed.get() || active != null || sessionToken <= 0L) return false
        val frontend = frontendFactory.open(modelDirectory, config)
        val session = QnnStreamingSession(
            sessionToken = sessionToken,
            config = config,
            frontend = frontend,
            runtime = runtime,
            callback = callback,
            callbackExecutor = callbackExecutor,
            residentBytes = residentBytes,
            elapsedRealtimeMs = elapsedRealtimeMs,
            onTerminal = ::onTerminal
        )
        session.updateRuntimePolicy(runtimePolicy ?: AsrRuntimePolicy.from(config))
        if (!session.start()) {
            session.close()
            return false
        }
        active = session
        true
    }

    fun pushPcm(sessionToken: Long, pcm: ByteBuffer, sampleCount: Int): Boolean =
        active(sessionToken)?.pushPcm(pcm, sampleCount) ?: false

    fun stop(sessionToken: Long) {
        active(sessionToken)?.stop()
    }

    fun cancel(sessionToken: Long) {
        active(sessionToken)?.cancel()
    }

    fun pause(sessionToken: Long) {
        active(sessionToken)?.pause()
    }

    fun resume(sessionToken: Long): Boolean = active(sessionToken)?.resume() ?: false

    fun updateRuntimePolicy(policy: AsrRuntimePolicy) = synchronized(lock) {
        if (closed.get()) return@synchronized
        runtimePolicy = policy
        active?.updateRuntimePolicy(policy)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        val session = synchronized(lock) {
            active.also {
                active = null
                runtimePolicy = null
            }
        }
        session?.cancel()
        runtime.close()
        callbackExecutor.shutdown()
        callbackExecutor.awaitTermination(CALLBACK_CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        callbackExecutor.shutdownNow()
    }

    private fun active(sessionToken: Long): QnnStreamingSession? = synchronized(lock) {
        active?.takeIf { it.sessionToken == sessionToken && !closed.get() }
    }

    private fun onTerminal(session: QnnStreamingSession) {
        synchronized(lock) {
            if (active === session) {
                active = null
                runtimePolicy = null
            }
        }
    }

    private companion object {
        const val CALLBACK_CLOSE_TIMEOUT_MS = 500L
    }
}

private class QnnStreamingSession(
    val sessionToken: Long,
    private val config: AsrConfig,
    private val frontend: WhisperQnnAudioFrontend,
    private val runtime: WhisperQnnTranscriberRuntime,
    private val callback: QnnAsrNativeCallback,
    private val callbackExecutor: ExecutorService,
    private val residentBytes: () -> Long,
    private val elapsedRealtimeMs: () -> Long,
    private val onTerminal: (QnnStreamingSession) -> Unit
) : AutoCloseable {
    private val terminal = AtomicBoolean(false)
    private val paused = AtomicBoolean(false)
    private val finalPending = AtomicBoolean(false)
    private val partialPreemptionRequested = AtomicBoolean(false)
    private val activeInferenceKind = AtomicReference<NativeFeatureWindowKind?>()
    private val featureExecutor = namedSingleThreadExecutor("GalaxySSI-ASR-Feature")
    private val inferenceExecutor = namedSingleThreadExecutor("GalaxySSI-ASR-QNN")
    private val featureBuffers = ArrayBlockingQueue<ByteBuffer>(FEATURE_BUFFER_COUNT).apply {
        repeat(FEATURE_BUFFER_COUNT) {
            add(ByteBuffer.allocateDirect(NativeWhisperQnnAudioFrontend.MEL_BUFFER_BYTES).order(ByteOrder.nativeOrder()))
        }
    }
    private val mailbox = FeatureMailbox()
    private val stabilizer = WhisperTwoPassStabilizer()
    private val runtimePolicy = AtomicReference(AsrRuntimePolicy.from(config))
    private var lastPartialInferenceAtMs = Long.MIN_VALUE

    fun start(): Boolean {
        if (terminal.get() || !frontend.start()) return false
        featureExecutor.execute(::featureLoop)
        inferenceExecutor.execute(::inferenceLoop)
        return true
    }

    fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean {
        if (terminal.get() || finalPending.get()) return false
        val accepted = runCatching { frontend.pushPcm(pcm, sampleCount) }.getOrDefault(false)
        if (!accepted && !finalPending.get()) {
            fail("audio_backpressure", "Local ASR audio queue could not accept PCM", true)
        }
        return accepted
    }

    fun stop() {
        if (!terminal.get()) {
            logPerformance("stage=stop_requested session=$sessionToken")
            runCatching(frontend::stop).onFailure(::failFrontend)
        }
    }

    fun pause() {
        if (terminal.get()) return
        paused.set(true)
        mailbox.discardPartial().forEach(::release)
        runCatching(frontend::pause).onFailure(::failFrontend)
    }

    fun resume(): Boolean {
        if (terminal.get()) return false
        return runCatching(frontend::resume).getOrElse {
            failFrontend(it)
            false
        }.also { resumed -> if (resumed) paused.set(false) }
    }

    fun updateRuntimePolicy(policy: AsrRuntimePolicy) {
        runtimePolicy.set(policy)
        frontend.updateRuntimePolicy(policy)
        if (!policy.emitIntermediateResults) {
            mailbox.discardPartial().forEach(::release)
        }
    }

    fun cancel() {
        terminateWithoutCallback()
    }

    override fun close() {
        terminateWithoutCallback()
    }

    private fun featureLoop() {
        while (!terminal.get()) {
            val buffer = try {
                featureBuffers.poll(FEATURE_POOL_WAIT_MS, TimeUnit.MILLISECONDS) ?: continue
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
            val featureStartedAt = elapsedRealtimeMs().coerceAtLeast(0L)
            val window = try {
                frontend.waitForFeatures(buffer, FEATURE_WAIT_MS)
            } catch (error: Throwable) {
                featureBuffers.offer(buffer)
                failFrontend(error)
                return
            }
            if (window == null) {
                featureBuffers.offer(buffer)
                continue
            }
            logPerformance(
                "stage=features kind=${window.kind.name.lowercase()} audio_ms=${window.durationMs} " +
                    "wait_extract_ms=${(elapsedRealtimeMs().coerceAtLeast(0L) - featureStartedAt).coerceAtLeast(0L)}"
            )
            if (paused.get()) {
                featureBuffers.offer(buffer)
                continue
            }
            if (window.final) {
                finalPending.set(true)
                if (activeInferenceKind.get() == NativeFeatureWindowKind.PARTIAL) {
                    partialPreemptionRequested.set(true)
                    runtime.cancelActive()
                }
            }
            val packet = if (window.kind == NativeFeatureWindowKind.NO_SPEECH_FINAL) {
                featureBuffers.offer(buffer)
                FeaturePacket(window, null)
            } else {
                FeaturePacket(window, buffer)
            }
            mailbox.offer(packet).forEach(::release)
            if (window.final) return
        }
    }

    private fun inferenceLoop() {
        while (!terminal.get()) {
            val packet = try {
                mailbox.take() ?: return
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
            if (paused.get()) {
                release(packet)
                continue
            }
            if (packet.window.kind == NativeFeatureWindowKind.NO_SPEECH_FINAL) {
                finishFinal(StableWhisperHypothesis("", "", "", true), packet.window, null)
                return
            }
            if (!packet.window.final && !shouldInferPartial()) {
                release(packet)
                continue
            }
            if (!packet.window.final && finalPending.get()) {
                release(packet)
                continue
            }

            activeInferenceKind.set(packet.window.kind)
            if (!packet.window.final && finalPending.get()) {
                activeInferenceKind.compareAndSet(packet.window.kind, null)
                release(packet)
                continue
            }
            val startedAt = elapsedRealtimeMs().coerceAtLeast(0L)
            // Partial text is revisable, so a bounded budget keeps it responsive. Final text must
            // retain the configured hard maximum because duration-derived caps can silently cut
            // fast speech, numbers, URLs, or dense multilingual tokens before EOT.
            val tokenBudget = if (packet.window.final) {
                config.maxTokens
            } else {
                WhisperQnnPartialTokenBudget.forAudioDuration(packet.window.durationMs, config.maxTokens)
            }
            val transcription = try {
                val features = requireNotNull(packet.buffer)
                    .duplicate()
                    .order(ByteOrder.nativeOrder())
                    .asFloatBuffer()
                runtime.transcribe(features, config.language, tokenBudget)
            } catch (error: Throwable) {
                activeInferenceKind.compareAndSet(packet.window.kind, null)
                release(packet)
                if (!packet.window.final && finalPending.get() &&
                    (partialPreemptionRequested.getAndSet(false) || error is QnnInferenceCancelledException)
                ) {
                    logPerformance("stage=partial_preempted audio_ms=${packet.window.durationMs}")
                    continue
                }
                fail("qnn_inference_failed", error.message ?: "QNN Whisper inference failed", true)
                return
            }
            activeInferenceKind.compareAndSet(packet.window.kind, null)
            partialPreemptionRequested.set(false)
            val wallMs = (elapsedRealtimeMs().coerceAtLeast(0L) - startedAt).coerceAtLeast(0L)
            logPerformance(
                "stage=${if (packet.window.final) "final" else "partial"} " +
                    "audio_ms=${packet.window.durationMs} wall_ms=$wallMs " +
                    "encoder_ms=${transcription.encoderNanos / 1_000_000.0} " +
                    "decoder_ms=${transcription.decoderNanos / 1_000_000.0} " +
                    "decoder_steps=${transcription.decoderSteps} output_tokens=${transcription.tokenIds.size} " +
                    "token_budget=$tokenBudget decode_passes=${transcription.decodePasses} " +
                    "compression_ratio=${transcription.compressionRatio} " +
                    "repeated_ngram_ratio=${transcription.repeatedNgramRatio} " +
                    "termination=${transcription.termination.name.lowercase()}"
            )
            release(packet)
            if (terminal.get()) return
            if (!packet.window.final && finalPending.get()) continue
            val hypothesis = stabilizer.update(transcription.text, packet.window.final)
            if (packet.window.final) {
                finishFinal(hypothesis, packet.window, transcription)
                return
            }
            emitDiagnostics(transcription)
            executeCallback {
                callback.onPartial(
                    sessionToken,
                    hypothesis.stableText,
                    hypothesis.unstableText,
                    packet.window.durationMs,
                    transcription.inferenceMs
                )
            }
        }
    }

    private fun finishFinal(
        hypothesis: StableWhisperHypothesis,
        window: NativeFeatureWindow,
        transcription: WhisperQnnTranscription?
    ) {
        if (!terminal.compareAndSet(false, true)) return
        logPerformance(
            "stage=final_callback audio_ms=${window.durationMs} " +
                "inference_ms=${transcription?.inferenceMs ?: 0L} text_chars=${hypothesis.fullText.length} " +
                "termination=${transcription?.termination?.name?.lowercase() ?: "no_speech"}"
        )
        mailbox.close().forEach(::release)
        closeFrontendSafely()
        onTerminal(this)
        if (transcription != null) emitDiagnostics(transcription)
        executeCallback {
            callback.onFinal(
                sessionToken,
                hypothesis.fullText,
                window.durationMs,
                transcription?.inferenceMs ?: 0L,
                transcription?.termination ?: AsrTranscriptTermination.NO_SPEECH
            )
        }
        shutdownWorkers()
    }

    private fun failFrontend(error: Throwable) {
        fail("native_frontend_failed", error.message ?: "Native ASR frontend failed", true)
    }

    private fun logPerformance(message: String) {
        // Android's Log methods throw in local JVM tests unless an Android runtime is present.
        runCatching { Log.i(PERF_TAG, message) }
    }

    private fun fail(code: String, message: String, recoverable: Boolean) {
        if (!terminal.compareAndSet(false, true)) return
        mailbox.close().forEach(::release)
        closeFrontendSafely()
        onTerminal(this)
        executeCallback { callback.onError(sessionToken, code, message, recoverable) }
        shutdownWorkers()
    }

    private fun terminateWithoutCallback() {
        if (!terminal.compareAndSet(false, true)) return
        runtime.cancelActive()
        mailbox.close().forEach(::release)
        closeFrontendSafely()
        onTerminal(this)
        shutdownWorkers()
    }

    private fun emitDiagnostics(transcription: WhisperQnnTranscription) {
        val policy = runtimePolicy.get()
        val execution = transcription.qnnExecution
        val verified = execution?.fullHtpExecutionVerified == true
        executeCallback {
            callback.onDiagnostics(
                sessionToken,
                AsrEvent.Diagnostics(
                    encoderMs = transcription.encoderNanos / 1_000_000.0,
                    decoderMsPerToken = transcription.decoderMsPerToken,
                    encoderNpuLayers = if (verified) WhisperLargeTurboQnnContract.ENCODER_NPU_LAYERS else 0,
                    encoderTotalLayers = WhisperLargeTurboQnnContract.ENCODER_NPU_LAYERS,
                    decoderNpuLayers = if (verified) WhisperLargeTurboQnnContract.DECODER_NPU_LAYERS else 0,
                    decoderTotalLayers = WhisperLargeTurboQnnContract.DECODER_NPU_LAYERS,
                    thermalStatus = policy.thermalStatus,
                    residentBytes = residentBytes().coerceAtLeast(0L),
                    qnnExecution = execution
                )
            )
        }
    }

    private fun shouldInferPartial(): Boolean {
        val policy = runtimePolicy.get()
        if (!policy.emitIntermediateResults) return false
        val now = elapsedRealtimeMs().coerceAtLeast(0L)
        if (lastPartialInferenceAtMs != Long.MIN_VALUE &&
            now - lastPartialInferenceAtMs < policy.partialIntervalMs
        ) return false
        lastPartialInferenceAtMs = now
        return true
    }

    private fun executeCallback(block: () -> Unit) {
        if (!callbackExecutor.isShutdown) runCatching { callbackExecutor.execute(block) }
    }

    private fun shutdownWorkers() {
        featureExecutor.shutdownNow()
        inferenceExecutor.shutdownNow()
        if (Thread.currentThread().name != INFERENCE_THREAD_NAME) {
            runCatching { inferenceExecutor.awaitTermination(INFERENCE_CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        }
    }

    private fun closeFrontendSafely() {
        runCatching(frontend::cancel)
        featureExecutor.shutdownNow()
        if (Thread.currentThread().name != FEATURE_THREAD_NAME) {
            runCatching { featureExecutor.awaitTermination(FEATURE_CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS) }
        }
        runCatching(frontend::close)
    }

    private fun release(packet: FeaturePacket) {
        packet.buffer?.let { buffer ->
            buffer.clear()
            featureBuffers.offer(buffer)
        }
    }

    private companion object {
        const val FEATURE_BUFFER_COUNT = 2
        const val FEATURE_CLOSE_TIMEOUT_MS = 750L
        const val FEATURE_THREAD_NAME = "GalaxySSI-ASR-Feature"
        const val INFERENCE_CLOSE_TIMEOUT_MS = 750L
        const val INFERENCE_THREAD_NAME = "GalaxySSI-ASR-QNN"
        const val FEATURE_WAIT_MS = 250
        const val FEATURE_POOL_WAIT_MS = 100L
        const val PERF_TAG = "GalaxySSIQnnPerf"
    }
}

internal data class FeaturePacket(
    val window: NativeFeatureWindow,
    val buffer: ByteBuffer?
)

internal object WhisperQnnPartialTokenBudget {
    private const val MIN_OUTPUT_TOKENS = 32
    private const val OUTPUT_TOKENS_PER_SECOND = 10L
    private const val OUTPUT_TOKEN_HEADROOM = 24L

    fun forAudioDuration(audioDurationMs: Long, configuredMaximum: Int): Int {
        require(configuredMaximum in 1..AsrConfig.MAX_FINAL_TOKENS)
        val duration = audioDurationMs.coerceAtLeast(0L)
        val estimated = ((duration * OUTPUT_TOKENS_PER_SECOND + 999L) / 1_000L) +
            OUTPUT_TOKEN_HEADROOM
        return estimated.toInt().coerceIn(minOf(MIN_OUTPUT_TOKENS, configuredMaximum), configuredMaximum)
    }
}

internal class FeatureMailbox {
    private val lock = ReentrantLock()
    private val available = lock.newCondition()
    private var partial: FeaturePacket? = null
    private var final: FeaturePacket? = null
    private var closed = false

    fun offer(packet: FeaturePacket): List<FeaturePacket> = lock.withLock {
        if (closed) return listOf(packet)
        val discarded = ArrayList<FeaturePacket>(2)
        if (packet.window.final) {
            partial?.let(discarded::add)
            final?.let(discarded::add)
            partial = null
            final = packet
        } else if (final == null) {
            partial?.let(discarded::add)
            partial = packet
        } else {
            discarded += packet
        }
        available.signal()
        discarded
    }

    @Throws(InterruptedException::class)
    fun take(): FeaturePacket? = lock.withLock {
        while (!closed && partial == null && final == null) available.await()
        if (closed) return null
        final?.also { final = null } ?: partial.also { partial = null }
    }

    fun discardPartial(): List<FeaturePacket> = lock.withLock {
        listOfNotNull(partial).also { partial = null }
    }

    fun close(): List<FeaturePacket> = lock.withLock {
        if (closed) return emptyList()
        closed = true
        val discarded = listOfNotNull(partial, final)
        partial = null
        final = null
        available.signalAll()
        discarded
    }
}

private fun namedSingleThreadExecutor(name: String): ExecutorService = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, name).apply { isDaemon = true }
}
