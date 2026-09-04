package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import android.os.SystemClock
import com.galaxyssi.chat.WhisperModelManager
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DefaultLocalWhisperRuntime internal constructor(
    private val modelResolver: (WhisperModelProfile) -> File,
    private val native: WhisperNativeApi = WhisperNativeBridge,
    private val clock: () -> Long = System::currentTimeMillis,
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime
) : LocalWhisperRuntime {
    constructor(context: Context) : this(
        modelResolver = { profile -> WhisperModelManager.ensureVerifiedFile(context.applicationContext, profile) }
    )

    private data class RuntimeLease(
        val handle: Long,
        val loaded: WhisperLoadedModel,
        val options: WhisperLoadOptions
    )

    private val lifecycleMutex = Mutex()
    private val decodeMutex = Mutex()
    private val sessions = ConcurrentHashMap<String, Session>()
    private val dispatcher: ExecutorCoroutineDispatcher = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GalaxySSI-WhisperDecode").apply { isDaemon = true }
    }.asCoroutineDispatcher()
    private val closed = AtomicBoolean(false)
    private val mutableState = MutableStateFlow<WhisperRuntimeState>(WhisperRuntimeState.Unloaded)
    private var runtime: RuntimeLease? = null

    override val state: StateFlow<WhisperRuntimeState> = mutableState.asStateFlow()

    override suspend fun load(profile: WhisperModelProfile, options: WhisperLoadOptions): WhisperLoadedModel =
        lifecycleMutex.withLock {
            check(!closed.get()) { "LocalWhisperRuntime is closed" }
            runtime?.takeIf { it.loaded.profile.id == profile.id && it.options == options }?.let { return@withLock it.loaded }
            if (runtime != null) unloadLocked(UnloadReason.MODEL_SWITCH)

            mutableState.value = WhisperRuntimeState.Loading(profile.id)
            val startedAt = elapsedRealtime()
            var handle = 0L
            try {
                val modelFile = modelResolver(profile).canonicalFile
                require(modelFile.isFile && modelFile.canRead()) { "Verified Whisper model is unavailable" }
                handle = native.createRuntime(modelFile.path, options.threadCount, options.useGpu)
                check(handle != 0L) { "Native Whisper runtime could not load ${profile.displayName}" }
                val warmUp = if (options.warmUp) warmUp(handle, options) else null
                val smeAvailable = WhisperCpuFeatures.osExposesSme()
                val loaded = WhisperLoadedModel(
                    profile = profile,
                    threadCount = options.threadCount,
                    loadedAtMillis = clock(),
                    loadDurationMs = (elapsedRealtime() - startedAt).coerceAtLeast(0L),
                    warmUpTimings = warmUp,
                    accelerationBackend = if (smeAvailable) {
                        WhisperAccelerationBackend.QMX_SME
                    } else {
                        WhisperAccelerationBackend.CPU
                    },
                    accelerationDetail = if (smeAvailable) {
                        "GGML ARMv9.2 SME runtime backend"
                    } else {
                        "GGML runtime-selected NEON backend"
                    }
                )
                runtime = RuntimeLease(handle, loaded, options)
                WhisperModelManager.markLoaded(profile.id)
                mutableState.value = WhisperRuntimeState.Ready(loaded)
                loaded
            } catch (error: Throwable) {
                if (handle != 0L) native.destroyRuntime(handle)
                WhisperModelManager.markUnloaded(profile.id)
                mutableState.value = WhisperRuntimeState.Failed(
                    WhisperRuntimeError(
                        if (error is OutOfMemoryError) NativeWhisperCode.OUT_OF_MEMORY else NativeWhisperCode.MODEL_NOT_LOADED,
                        error.message.orEmpty()
                    )
                )
                throw error
            }
        }

    override suspend fun createSession(config: LocalWhisperSessionConfig): LocalWhisperSession =
        lifecycleMutex.withLock {
            check(!closed.get()) { "LocalWhisperRuntime is closed" }
            val lease = requireNotNull(runtime) { "A Whisper model must be loaded before creating a session" }
            val nativeHandle = native.createSession(lease.handle, config)
            check(nativeHandle != 0L) { "Native Whisper session could not be created" }
            Session(UUID.randomUUID().toString(), nativeHandle, config).also { sessions[it.id] = it }
        }

    override suspend fun unload(reason: UnloadReason) {
        lifecycleMutex.withLock { unloadLocked(reason) }
    }

    override fun requestAbortAll(reason: AbortReason) {
        sessions.values.forEach { it.requestAbort(reason) }
    }

    override suspend fun runBenchmark(request: BenchmarkRequest): BenchmarkResult {
        val loaded = requireNotNull(runtime?.loaded) { "A Whisper model must be loaded before benchmarking" }
        val timings = buildList {
            repeat(request.iterations) {
                createSession(LocalWhisperSessionConfig(language = request.language)).use { session ->
                    val result = session.decode(WhisperDecodeRequest(request.pcm16))
                    check(result.successful) { result.message ?: "Whisper benchmark decode failed" }
                    add(result.timings)
                }
            }
        }
        val sorted = timings.map(NativeWhisperTimings::realTimeFactor).sorted()
        return BenchmarkResult(
            profileId = loaded.profile.id,
            iterations = timings.size,
            timings = timings,
            medianRealTimeFactor = sorted[sorted.size / 2]
        )
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runBlocking { lifecycleMutex.withLock { unloadLocked(UnloadReason.APP_SHUTDOWN) } }
        dispatcher.close()
    }

    internal fun activeNativeHandles(): Pair<Int, Int> = native.activeRuntimeCount() to native.activeSessionCount()

    private suspend fun warmUp(runtimeHandle: Long, options: WhisperLoadOptions): NativeWhisperTimings {
        val config = LocalWhisperSessionConfig(language = "en", noContext = true, singleSegment = true)
        val sessionHandle = native.createSession(runtimeHandle, config)
        check(sessionHandle != 0L) { "Whisper warm-up session could not be created" }
        return try {
            val result = withContext(dispatcher) {
                native.decodePcm16(sessionHandle, ShortArray(options.warmUpSamples), 0, options.warmUpSamples)
            }
            check(result.successful) { result.message ?: "Whisper warm-up failed (${result.code})" }
            result.timings
        } finally {
            native.destroySession(sessionHandle)
        }
    }

    private fun unloadLocked(reason: UnloadReason) {
        val lease = runtime ?: run {
            mutableState.value = WhisperRuntimeState.Unloaded
            return
        }
        mutableState.value = WhisperRuntimeState.Unloading(reason)
        requestAbortAll(AbortReason.RUNTIME_UNLOAD)
        sessions.values.toList().forEach(Session::close)
        sessions.clear()
        native.destroyRuntime(lease.handle)
        WhisperModelManager.markUnloaded(lease.loaded.profile.id)
        runtime = null
        mutableState.value = WhisperRuntimeState.Unloaded
    }

    private inner class Session(
        override val id: String,
        private val nativeHandle: Long,
        override val config: LocalWhisperSessionConfig
    ) : LocalWhisperSession {
        private val sessionClosed = AtomicBoolean(false)

        override suspend fun decode(request: WhisperDecodeRequest): NativeWhisperResult {
            check(!sessionClosed.get()) { "Whisper session is closed" }
            return decodeMutex.withLock {
                check(!sessionClosed.get()) { "Whisper session is closed" }
                val loaded = requireNotNull(runtime?.loaded) { "Whisper runtime is not loaded" }
                mutableState.value = WhisperRuntimeState.Decoding(id, request.mode)
                try {
                    withContext(dispatcher) {
                        val cancellationHandle = currentCoroutineContext().job.invokeOnCompletion { cause ->
                            if (cause is CancellationException) native.requestAbort(nativeHandle)
                        }
                        try {
                            native.decodePcm16(nativeHandle, request.pcm16, request.offset, request.length)
                        } finally {
                            cancellationHandle.dispose()
                        }
                    }
                } finally {
                    if (runtime?.loaded?.profile?.id == loaded.profile.id && !closed.get()) {
                        mutableState.value = WhisperRuntimeState.Ready(loaded)
                    }
                }
            }
        }

        override fun requestAbort(reason: AbortReason) {
            if (!sessionClosed.get()) native.requestAbort(nativeHandle)
        }

        override fun close() {
            if (!sessionClosed.compareAndSet(false, true)) return
            native.requestAbort(nativeHandle)
            sessions.remove(id, this)
            native.destroySession(nativeHandle)
        }
    }
}
