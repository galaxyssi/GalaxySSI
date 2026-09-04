package com.galaxyssi.chat.voice.asr.local

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class WhisperLargeTurboAsrEngine(
    private val native: QnnAsrNativeApi,
    private val runtimeDirectory: String,
    private val modelValidator: QnnAsrModelDirectoryValidator = FileModelDirectoryValidator(),
    private val clock: () -> Long = System::currentTimeMillis
) : LocalAsrEngine {
    private val dispatcher: ExecutorCoroutineDispatcher = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GalaxySSI-QNN-ASR-Lifecycle").apply { isDaemon = true }
    }.asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val lifecycleMutex = Mutex()
    private val stateLock = Any()
    private val closed = AtomicBoolean(false)
    private val mutableState = MutableStateFlow<LocalAsrState>(LocalAsrState.Unprepared)
    private val mutableEvents = MutableSharedFlow<AsrEvent>(extraBufferCapacity = EVENT_BUFFER_CAPACITY)
    private var handle = 0L
    private var modelDirectory = ""
    private var preparedAtMillis = 0L
    private var sessionSequence = 0L
    private var activeSessionToken = 0L
    private var activeConfig: AsrConfig? = null
    private var activeRuntimePolicy: AsrRuntimePolicy? = null
    private var pauseReasons = linkedSetOf<LocalAsrPauseReason>()
    private var transcriptRevision = 0L

    override val state: StateFlow<LocalAsrState> = mutableState.asStateFlow()
    override val events: Flow<AsrEvent> = mutableEvents.asSharedFlow()

    private val callback = object : QnnAsrNativeCallback {
        override fun onPartial(
            sessionToken: Long,
            stableText: String,
            unstableText: String,
            audioDurationMs: Long,
            inferenceMs: Long
        ) {
            val revision = synchronized(stateLock) {
                if (!acceptsTranscriptCallback(sessionToken)) return
                transcriptRevision += 1L
                transcriptRevision
            }
            publish(AsrEvent.Partial(
                stableText = stableText,
                unstableText = unstableText,
                revision = revision,
                audioDurationMs = audioDurationMs.coerceAtLeast(0L),
                inferenceMs = inferenceMs.coerceAtLeast(0L)
            ))
        }

        override fun onFinal(
            sessionToken: Long,
            text: String,
            durationMs: Long,
            inferenceMs: Long,
            termination: AsrTranscriptTermination
        ) {
            val ready = synchronized(stateLock) {
                if (sessionToken != activeSessionToken || closed.get()) return
                clearActiveSessionLocked()
                readyStateLocked()
            }
            publish(
                AsrEvent.Final(
                    text.trim(),
                    durationMs.coerceAtLeast(0L),
                    inferenceMs.coerceAtLeast(0L),
                    termination
                )
            )
            transition(ready)
        }

        override fun onError(
            sessionToken: Long,
            code: String,
            message: String,
            recoverable: Boolean
        ) {
            val next = synchronized(stateLock) {
                if (sessionToken != activeSessionToken || closed.get()) return
                clearActiveSessionLocked()
                if (recoverable) readyStateLocked() else LocalAsrState.Failed(code, message, false)
            }
            publish(AsrEvent.Error(code, message, recoverable))
            transition(next)
        }

        override fun onDiagnostics(sessionToken: Long, diagnostics: AsrEvent.Diagnostics) {
            val accepted = synchronized(stateLock) { sessionToken == activeSessionToken && !closed.get() }
            if (accepted) publish(diagnostics)
        }
    }

    override suspend fun prepare(modelDirectory: String) {
        check(!closed.get()) { "Local ASR engine is closed" }
        withContext(dispatcher) {
            lifecycleMutex.withLock {
                check(!closed.get()) { "Local ASR engine is closed" }
                val canonical = modelValidator.validate(modelDirectory)
                val current = synchronized(stateLock) { mutableState.value }
                check(current !is LocalAsrState.Starting && current !is LocalAsrState.Listening &&
                    current !is LocalAsrState.Paused && current !is LocalAsrState.Stopping) {
                    "Local ASR cannot switch models during an active recording"
                }
                if (handle != 0L && this@WhisperLargeTurboAsrEngine.modelDirectory == canonical &&
                    current is LocalAsrState.Ready
                ) return@withLock

                transition(LocalAsrState.Preparing(canonical))
                if (handle != 0L) {
                    native.destroy(handle)
                    handle = 0L
                }
                try {
                    val created = native.create(canonical, runtimeDirectory, callback)
                    check(created != 0L) { "QNN ASR runtime could not restore the model contexts" }
                    synchronized(stateLock) {
                        handle = created
                        this@WhisperLargeTurboAsrEngine.modelDirectory = canonical
                        preparedAtMillis = clock()
                        clearActiveSessionLocked()
                    }
                    transition(LocalAsrState.Ready(canonical, preparedAtMillis))
                } catch (error: Throwable) {
                    Log.e(TAG, "QNN ASR preparation failed", error)
                    val failed = LocalAsrState.Failed(
                        code = "qnn_prepare_failed",
                        message = error.message ?: "QNN ASR preparation failed",
                        recoverable = true
                    )
                    transition(failed)
                    publish(AsrEvent.Error(failed.code, failed.message, failed.recoverable))
                    throw error
                }
            }
        }
    }

    override fun start(config: AsrConfig) {
        if (closed.get()) return
        val launch = synchronized(stateLock) {
            when (mutableState.value) {
                is LocalAsrState.Starting,
                is LocalAsrState.Listening,
                is LocalAsrState.Paused,
                is LocalAsrState.Stopping -> {
                    publish(AsrEvent.Error("asr_session_active", "A local ASR recording is already active"))
                    return
                }
                is LocalAsrState.Ready -> Unit
                else -> {
                    publish(AsrEvent.Error("asr_not_ready", "Prepare the local ASR model before recording"))
                    return
                }
            }
            if (handle == 0L) return
            sessionSequence += 1L
            activeSessionToken = sessionSequence
            activeConfig = config
            activeRuntimePolicy = AsrRuntimePolicy.from(config)
            pauseReasons.clear()
            transcriptRevision = 0L
            StartCommand(handle, activeSessionToken, config)
        }
        transition(LocalAsrState.Starting(launch.sessionToken, launch.config))
        scope.launch {
            val started = runCatching {
                val policy = synchronized(stateLock) {
                    activeRuntimePolicy ?: AsrRuntimePolicy.from(launch.config)
                }
                native.updateRuntimePolicy(launch.handle, policy)
                native.start(launch.handle, launch.sessionToken, launch.config)
            }
            val failure = started.exceptionOrNull()
            val next = synchronized(stateLock) {
                if (launch.sessionToken != activeSessionToken || closed.get()) return@synchronized null
                val current = mutableState.value
                if (started.getOrDefault(false) && current is LocalAsrState.Starting) {
                    LocalAsrState.Listening(launch.sessionToken, launch.config)
                } else if (started.getOrDefault(false)) {
                    null
                } else {
                    clearActiveSessionLocked()
                    LocalAsrState.Failed(
                        "qnn_start_failed",
                        failure?.message ?: "QNN ASR recording could not start",
                        true
                    )
                }
            }
            next?.let {
                transition(it)
                if (it is LocalAsrState.Failed) {
                    runCatching { native.cancel(launch.handle, launch.sessionToken) }
                    publish(AsrEvent.Error(it.code, it.message, it.recoverable))
                }
            }
        }
    }

    override fun pushPcm(pcm: ByteBuffer, sampleCount: Int): Boolean {
        if (!pcm.isDirect || sampleCount <= 0 || sampleCount > pcm.remaining() / PCM16_BYTES_PER_SAMPLE) {
            publish(AsrEvent.Error("invalid_pcm", "PCM input must be a direct PCM16 buffer", true))
            return false
        }
        val command = synchronized(stateLock) {
            val current = mutableState.value
            if (current !is LocalAsrState.Listening || handle == 0L) return false
            PcmCommand(handle, current.sessionToken)
        }
        return runCatching { native.pushPcm(command.handle, command.sessionToken, pcm, sampleCount) }
            .getOrElse {
                callback.onError(command.sessionToken, "pcm_push_failed", it.message.orEmpty(), true)
                false
            }
    }

    override fun stop() {
        if (closed.get()) return
        val command = synchronized(stateLock) {
            val current = mutableState.value
            val config = activeConfig ?: return
            if (current !is LocalAsrState.Listening && current !is LocalAsrState.Paused &&
                current !is LocalAsrState.Starting
            ) return
            StopCommand(handle, activeSessionToken, config)
        }
        transition(LocalAsrState.Stopping(command.sessionToken, command.config))
        scope.launch {
            runCatching { native.stop(command.handle, command.sessionToken) }
                .onFailure {
                    callback.onError(command.sessionToken, "qnn_stop_failed", it.message.orEmpty(), true)
                    return@launch
                }
            delay(command.config.finalizationTimeoutMs)
            val timedOut = synchronized(stateLock) {
                activeSessionToken == command.sessionToken && mutableState.value is LocalAsrState.Stopping
            }
            if (timedOut) {
                runCatching { native.cancel(command.handle, command.sessionToken) }
                callback.onError(
                    command.sessionToken,
                    "finalization_timeout",
                    "Local ASR did not produce a final transcript in time",
                    true
                )
            }
        }
    }

    override fun cancel() {
        if (closed.get()) return
        val command = synchronized(stateLock) {
            if (activeSessionToken == 0L || handle == 0L) return
            PcmCommand(handle, activeSessionToken).also { clearActiveSessionLocked() }
        }
        transition(synchronized(stateLock) { readyStateLocked() })
        scope.launch { runCatching { native.cancel(command.handle, command.sessionToken) } }
    }

    override fun pause(reason: LocalAsrPauseReason) {
        if (closed.get()) return
        val command = synchronized(stateLock) {
            val current = mutableState.value
            val config = activeConfig ?: return
            if (current !is LocalAsrState.Listening && current !is LocalAsrState.Starting &&
                current !is LocalAsrState.Paused
            ) return
            val added = pauseReasons.add(reason)
            val value = PauseCommand(handle, activeSessionToken, config, pauseReasons.toSet(), added)
            value
        }
        transition(LocalAsrState.Paused(command.sessionToken, command.config, command.reasons))
        if (command.invokeNative) {
            scope.launch { runCatching { native.pause(command.handle, command.sessionToken) } }
        }
    }

    override fun resume(reason: LocalAsrPauseReason) {
        if (closed.get()) return
        val command = synchronized(stateLock) {
            val current = mutableState.value as? LocalAsrState.Paused ?: return
            pauseReasons.remove(reason)
            if (pauseReasons.isNotEmpty()) {
                transition(LocalAsrState.Paused(current.sessionToken, current.config, pauseReasons.toSet()))
                return
            }
            StartCommand(handle, current.sessionToken, current.config)
        }
        transition(LocalAsrState.Starting(command.sessionToken, command.config))
        scope.launch {
            val resumed = runCatching { native.resume(command.handle, command.sessionToken) }
            val next = synchronized(stateLock) {
                if (command.sessionToken != activeSessionToken || closed.get()) return@synchronized null
                if (resumed.getOrDefault(false)) {
                    LocalAsrState.Listening(command.sessionToken, command.config)
                } else {
                    clearActiveSessionLocked()
                    LocalAsrState.Failed(
                        "qnn_resume_failed",
                        resumed.exceptionOrNull()?.message ?: "QNN ASR recording could not resume",
                        true
                    )
                }
            }
            next?.let {
                transition(it)
                if (it is LocalAsrState.Failed) publish(AsrEvent.Error(it.code, it.message, it.recoverable))
            }
        }
    }

    override fun updateRuntimePolicy(policy: AsrRuntimePolicy) {
        if (closed.get()) return
        val currentHandle = synchronized(stateLock) {
            activeRuntimePolicy = policy
            handle
        }
        if (currentHandle == 0L) return
        scope.launch {
            runCatching { native.updateRuntimePolicy(currentHandle, policy) }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runBlocking {
            withContext(dispatcher) {
                lifecycleMutex.withLock {
                    val command = synchronized(stateLock) {
                        val value = handle to activeSessionToken
                        handle = 0L
                        clearActiveSessionLocked()
                        value
                    }
                    if (command.first != 0L) {
                        if (command.second != 0L) runCatching { native.cancel(command.first, command.second) }
                        runCatching { native.destroy(command.first) }
                    }
                    transition(LocalAsrState.Closed)
                }
            }
        }
        scope.cancel()
        dispatcher.close()
    }

    private fun acceptsTranscriptCallback(sessionToken: Long): Boolean {
        if (sessionToken != activeSessionToken || closed.get()) return false
        return mutableState.value is LocalAsrState.Listening || mutableState.value is LocalAsrState.Stopping
    }

    private fun clearActiveSessionLocked() {
        activeSessionToken = 0L
        activeConfig = null
        activeRuntimePolicy = null
        pauseReasons.clear()
        transcriptRevision = 0L
    }

    private fun readyStateLocked(): LocalAsrState = if (handle != 0L && modelDirectory.isNotBlank()) {
        LocalAsrState.Ready(modelDirectory, preparedAtMillis)
    } else {
        LocalAsrState.Unprepared
    }

    private fun transition(next: LocalAsrState) {
        mutableState.value = next
        publish(AsrEvent.StateChanged(next))
    }

    private fun publish(event: AsrEvent) {
        if (!mutableEvents.tryEmit(event) && !closed.get()) {
            scope.launch { mutableEvents.emit(event) }
        }
    }

    private data class StartCommand(val handle: Long, val sessionToken: Long, val config: AsrConfig)
    private data class StopCommand(val handle: Long, val sessionToken: Long, val config: AsrConfig)
    private data class PcmCommand(val handle: Long, val sessionToken: Long)
    private data class PauseCommand(
        val handle: Long,
        val sessionToken: Long,
        val config: AsrConfig,
        val reasons: Set<LocalAsrPauseReason>,
        val invokeNative: Boolean
    )

    class FileModelDirectoryValidator : QnnAsrModelDirectoryValidator {
        override fun validate(modelDirectory: String): String {
            val directory = File(modelDirectory).canonicalFile
            require(directory.isDirectory && directory.canRead()) { "QNN ASR model directory is unavailable" }
            QnnAsrModelDirectoryValidator.REQUIRED_FILES.forEach { name ->
                val file = File(directory, name).canonicalFile
                require(file.parentFile == directory && file.isFile && file.canRead() && file.length() > 0L) {
                    "QNN ASR model is missing $name"
                }
            }
            return directory.path
        }
    }

    private companion object {
        const val TAG = "GalaxySSIQnnAsr"
        const val EVENT_BUFFER_CAPACITY = 128
        const val PCM16_BYTES_PER_SAMPLE = 2
    }
}
