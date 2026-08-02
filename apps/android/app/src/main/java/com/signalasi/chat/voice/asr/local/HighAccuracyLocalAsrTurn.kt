package com.signalasi.chat.voice.asr.local

import android.content.Context
import com.signalasi.chat.voice.audio.DirectPcmFramePacket
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean

data class HighAccuracyAsrResult(
    val text: String,
    val durationMs: Long,
    val inferenceMs: Long,
    val modelProfileId: String
)

class HighAccuracyLocalAsrController internal constructor(
    private val scope: CoroutineScope,
    private val modelDirectoryResolver: () -> File?,
    private val engineFactory: () -> LocalAsrEngine
) : AutoCloseable {
    private val engine = lazy(LazyThreadSafetyMode.SYNCHRONIZED, engineFactory)
    private val prepareMutex = Mutex()
    private val turnLock = Any()
    private val closed = AtomicBoolean(false)
    @Volatile private var prepareJob: Job? = null
    private var activeTurn: HighAccuracyLocalAsrTurn? = null

    fun prepareAsync() {
        if (closed.get() || isReady()) return
        synchronized(turnLock) {
            if (prepareJob?.isActive == true) return
            prepareJob = scope.launch { prepareNow() }
        }
    }

    suspend fun prepareNow(): Boolean = prepareMutex.withLock {
        if (closed.get()) return@withLock false
        val directory = modelDirectoryResolver()?.canonicalFile ?: return@withLock false
        if (!directory.isDirectory) return@withLock false
        val runtime = engine.value
        val ready = runtime.state.value as? LocalAsrState.Ready
        if (ready?.modelDirectory == directory.path) return@withLock true
        runCatching { runtime.prepare(directory.path) }.isSuccess && runtime.state.value is LocalAsrState.Ready
    }

    fun isReady(): Boolean = engine.isInitialized() && engine.value.state.value is LocalAsrState.Ready

    fun startTurnIfReady(
        config: AsrConfig,
        modelProfileId: String,
        onPartial: (AsrEvent.Partial) -> Unit
    ): HighAccuracyLocalAsrTurn? {
        if (closed.get() || !isReady()) {
            prepareAsync()
            return null
        }
        return synchronized(turnLock) {
            if (activeTurn != null) return@synchronized null
            val turn = HighAccuracyLocalAsrTurn(
                engine = engine.value,
                scope = scope,
                config = config,
                modelProfileId = modelProfileId,
                onPartial = onPartial,
                onReleased = { released ->
                    synchronized(turnLock) {
                        if (activeTurn === released) activeTurn = null
                    }
                }
            )
            if (turn.start()) {
                activeTurn = turn
                turn
            } else {
                turn.close()
                null
            }
        }
    }

    fun cancelActive() {
        synchronized(turnLock) { activeTurn }?.cancel()
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        val turn = synchronized(turnLock) {
            activeTurn.also { activeTurn = null }
        }
        turn?.cancel()
        prepareJob?.cancel()
        if (engine.isInitialized()) engine.value.close()
    }

    companion object {
        fun create(context: Context, scope: CoroutineScope): HighAccuracyLocalAsrController {
            val application = context.applicationContext
            val manifest = LargeTurboQnnModelCatalog.s26Ultra
            val store = LargeTurboQnnModelStore(application.filesDir)
            val capability = AndroidLargeTurboQnnDeviceCapabilityDetector(application, store, manifest)
            return HighAccuracyLocalAsrController(
                scope = scope,
                modelDirectoryResolver = {
                    if (capability.decision().eligibility != QnnAsrEligibility.READY) null
                    else store.inspectActive(manifest)
                        .takeIf { it.state == QnnContextModelState.INSTALLED }
                        ?.directory
                },
                engineFactory = { HighAccuracyLocalAsrEngineFactory.create(application) }
            )
        }
    }
}

class HighAccuracyLocalAsrTurn internal constructor(
    private val engine: LocalAsrEngine,
    private val scope: CoroutineScope,
    private val config: AsrConfig,
    private val modelProfileId: String,
    private val onPartial: (AsrEvent.Partial) -> Unit,
    private val onReleased: (HighAccuracyLocalAsrTurn) -> Unit
) : AutoCloseable {
    private data class PendingFrame(val pcm16: ByteBuffer, val sampleCount: Int)

    private val started = AtomicBoolean(false)
    private val released = AtomicBoolean(false)
    private val pushLock = Any()
    private val pending = ArrayDeque<PendingFrame>()
    private val finalResult = CompletableDeferred<HighAccuracyAsrResult>()
    private var pendingSamples = 0
    private val eventJob = scope.launch(start = CoroutineStart.UNDISPATCHED) {
        engine.events.collect(::consume)
    }

    internal fun start(): Boolean {
        if (!started.compareAndSet(false, true)) return false
        if (engine.state.value !is LocalAsrState.Ready) return false
        engine.start(config)
        return true
    }

    fun offer(frame: DirectPcmFramePacket): Boolean {
        if (!started.get() || released.get() || frame.sampleRateHz != config.inputSampleRateHz) return false
        synchronized(pushLock) {
            return when (engine.state.value) {
                is LocalAsrState.Listening -> {
                    flushPendingLocked()
                    engine.pushPcm(frame.pcm16, frame.sampleCount)
                }
                is LocalAsrState.Starting -> {
                    retainStartupFrameLocked(frame)
                    true
                }
                else -> false
            }
        }
    }

    suspend fun finish(): HighAccuracyAsrResult {
        check(started.get() && !released.get()) { "High accuracy ASR turn is not active" }
        engine.stop()
        return try {
            withTimeout(config.finalizationTimeoutMs + FINAL_TIMEOUT_GRACE_MS) { finalResult.await() }
        } catch (error: TimeoutCancellationException) {
            engine.cancel()
            throw error
        } finally {
            release(cancelEngine = false)
        }
    }

    fun cancel() {
        if (!released.get()) engine.cancel()
        finalResult.cancel()
        release(cancelEngine = false)
    }

    override fun close() {
        if (!finalResult.isCompleted) cancel() else release(cancelEngine = false)
    }

    private fun consume(event: AsrEvent) {
        if (!started.get() || released.get()) return
        when (event) {
            is AsrEvent.StateChanged -> if (event.state is LocalAsrState.Listening) {
                synchronized(pushLock) { flushPendingLocked() }
            }
            is AsrEvent.Partial -> onPartial(event)
            is AsrEvent.Final -> {
                finalResult.complete(HighAccuracyAsrResult(
                    text = event.text,
                    durationMs = event.durationMs,
                    inferenceMs = event.inferenceMs,
                    modelProfileId = modelProfileId
                ))
            }
            is AsrEvent.Error -> if (!finalResult.isCompleted) {
                finalResult.completeExceptionally(
                    IllegalStateException("${event.code}: ${event.message}".trim())
                )
            }
            is AsrEvent.Diagnostics -> Unit
        }
    }

    private fun retainStartupFrameLocked(frame: DirectPcmFramePacket) {
        val byteCount = frame.sampleCount * PCM16_BYTES_PER_SAMPLE
        val copy = ByteBuffer.allocateDirect(byteCount).order(ByteOrder.LITTLE_ENDIAN)
        val source = frame.pcm16.duplicate().apply { limit(position() + byteCount) }
        copy.put(source).flip()
        pending += PendingFrame(copy, frame.sampleCount)
        pendingSamples += frame.sampleCount
        val maxPendingSamples = config.inputSampleRateHz * STARTUP_AUDIO_BUFFER_MS / 1_000
        while (pendingSamples > maxPendingSamples && pending.isNotEmpty()) {
            pendingSamples -= pending.removeFirst().sampleCount
        }
    }

    private fun flushPendingLocked() {
        while (pending.isNotEmpty()) {
            val frame = pending.removeFirst()
            pendingSamples -= frame.sampleCount
            if (!engine.pushPcm(frame.pcm16, frame.sampleCount)) {
                pending.clear()
                pendingSamples = 0
                return
            }
        }
        pendingSamples = 0
    }

    private fun release(cancelEngine: Boolean) {
        if (!released.compareAndSet(false, true)) return
        if (cancelEngine) engine.cancel()
        synchronized(pushLock) {
            pending.clear()
            pendingSamples = 0
        }
        eventJob.cancel()
        onReleased(this)
    }

    private companion object {
        const val PCM16_BYTES_PER_SAMPLE = 2
        const val STARTUP_AUDIO_BUFFER_MS = 500
        const val FINAL_TIMEOUT_GRACE_MS = 750L
    }
}
