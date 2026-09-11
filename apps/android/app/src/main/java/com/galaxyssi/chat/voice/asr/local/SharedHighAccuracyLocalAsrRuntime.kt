package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal object SharedHighAccuracyLocalAsrRuntime {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var pool: SharedHighAccuracyAsrPool? = null

    @Synchronized fun acquire(context: Context): SharedHighAccuracyAsrClient {
        val application = context.applicationContext
        return (pool ?: SharedHighAccuracyAsrPool(scope) {
            HighAccuracyLocalAsrController.create(application, scope)
        }.also { pool = it }).acquire()
    }

    @Synchronized fun snapshot(): SharedHighAccuracyAsrSnapshot? = pool?.snapshot()
}

internal data class SharedHighAccuracyAsrSnapshot(
    val clients: Int,
    val controllerCreations: Int,
    val loadedControllers: Int,
    val activeOwner: Long?
)

/** Window leases share a model but never an active recording or its result callbacks. */
internal class SharedHighAccuracyAsrPool(
    private val scope: CoroutineScope,
    private val idleReleaseMs: Long = 30_000L,
    private val factory: () -> HighAccuracyLocalAsrController
) {
    private data class ClientState(var foreground: Boolean = false)
    private data class Recording(val owner: Long, val generation: Long, var turn: HighAccuracyLocalAsrTurn? = null)
    private val lock = Any()
    private val lifecycle = Mutex()
    private val clients = linkedMapOf<Long, ClientState>()
    private val status = MutableStateFlow(QnnAsrPreparationStatus.IDLE)
    private var nextId = 0L
    private var generation = 0L
    private var controllerCreations = 0
    private var controller: HighAccuracyLocalAsrController? = null
    private var retiring = false
    private var recording: Recording? = null
    private var microphoneGranted = false
    private var prepareJob: Job? = null
    private var idleJob: Job? = null
    private var statusJob: Job? = null
    val preparationStatus = status.asStateFlow()

    fun acquire(): SharedHighAccuracyAsrClient = synchronized(lock) {
        idleJob?.cancel()
        idleJob = null
        val id = ++nextId
        clients[id] = ClientState()
        SharedHighAccuracyAsrClient(this, id)
    }

    fun snapshot(): SharedHighAccuracyAsrSnapshot = synchronized(lock) {
        SharedHighAccuracyAsrSnapshot(clients.size, controllerCreations, if (controller != null || retiring) 1 else 0,
            recording?.owner)
    }

    fun prepare(id: Long) = synchronized(lock) {
        // A recording is already prepared, even though the engine is no longer in Ready state.
        if (id !in clients || recording != null) return@synchronized
        if (controller?.isReady() == true || prepareJob?.isActive == true) return@synchronized
        prepareJob = scope.launch {
            lifecycle.withLock {
                val current = synchronized(lock) {
                    if (clients.isEmpty()) return@withLock
                    controller ?: factory().also {
                        controller = it
                        controllerCreations++
                        refreshEnvironmentLocked()
                        statusJob = scope.launch { it.preparationStatus.collect { value -> status.value = value } }
                    }
                }
                try {
                    current.prepareNow()
                    status.value = current.preparationStatus.value
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    status.value = status.value.copy(phase = QnnAsrPreparationPhase.FALLBACK,
                        reasonCode = "qnn_prepare_failed")
                }
            }
        }
    }

    fun isReady(id: Long): Boolean = synchronized(lock) { id in clients && controller?.isReady() == true }

    fun start(
        id: Long,
        config: AsrConfig,
        profile: String,
        onPartial: (AsrEvent.Partial) -> Unit
    ): HighAccuracyLocalAsrTurn? = synchronized(lock) {
        if (id !in clients || recording != null) return@synchronized null
        val current = controller
        if (current == null || !current.isReady()) {
            prepare(id)
            return@synchronized null
        }
        val claim = Recording(id, ++generation)
        recording = claim
        refreshEnvironmentLocked()
        val turn = try {
            current.startOwnedTurnIfReady(config, profile, { partial ->
                val owned = synchronized(lock) { id in clients && recording === claim }
                if (owned) onPartial(partial)
            }, {
                synchronized(lock) {
                    if (recording === claim) {
                        recording = null
                        refreshEnvironmentLocked()
                    }
                }
            })
        } catch (error: Exception) {
            if (recording === claim) recording = null
            refreshEnvironmentLocked()
            throw error
        }
        if (turn == null) {
            if (recording === claim) recording = null
            refreshEnvironmentLocked()
        } else claim.turn = turn
        turn
    }

    fun foreground(id: Long, foreground: Boolean) = synchronized(lock) {
        val client = clients[id] ?: return@synchronized
        client.foreground = foreground
        refreshEnvironmentLocked()
    }

    fun microphonePermission(id: Long, granted: Boolean) = synchronized(lock) {
        if (id !in clients) return@synchronized
        microphoneGranted = granted
        controller?.onMicrophonePermissionChanged(granted)
    }

    fun cancel(id: Long) {
        val turn = synchronized(lock) {
            recording?.takeIf { it.owner == id }?.also { recording = null }?.turn
        }
        turn?.cancel()
        synchronized(lock) { refreshEnvironmentLocked() }
    }

    fun release(id: Long) {
        val turn = synchronized(lock) {
            if (clients.remove(id) == null) return
            recording?.takeIf { it.owner == id }?.also { recording = null }?.turn
        }
        turn?.cancel()
        synchronized(lock) {
            refreshEnvironmentLocked()
            if (clients.isNotEmpty()) return
            idleJob?.cancel()
            idleJob = scope.launch {
                delay(idleReleaseMs)
                // Serialize destruction with preparation without blocking the Activity thread.
                lifecycle.withLock {
                    val retired = synchronized(lock) {
                        if (clients.isNotEmpty()) return@withLock
                        statusJob?.cancel()
                        statusJob = null
                        controller.also {
                            retiring = it != null
                            controller = null
                            status.value = QnnAsrPreparationStatus.IDLE
                        }
                    }
                    try { retired?.close() } finally { synchronized(lock) { retiring = false } }
                }
            }
        }
    }

    private fun refreshEnvironmentLocked() {
        val foreground = recording?.let { clients[it.owner]?.foreground == true }
            ?: clients.values.any { it.foreground }
        controller?.onAppForegroundChanged(foreground)
        controller?.onMicrophonePermissionChanged(microphoneGranted)
    }
}

internal class SharedHighAccuracyAsrClient internal constructor(
    private val pool: SharedHighAccuracyAsrPool,
    internal val ownerId: Long
) : AutoCloseable {
    val preparationStatus get() = pool.preparationStatus
    fun prepareAsync() = pool.prepare(ownerId)
    fun isReady() = pool.isReady(ownerId)
    fun onAppForegroundChanged(foreground: Boolean) = pool.foreground(ownerId, foreground)
    fun onMicrophonePermissionChanged(granted: Boolean) = pool.microphonePermission(ownerId, granted)
    fun startTurnIfReady(config: AsrConfig, modelProfileId: String, onPartial: (AsrEvent.Partial) -> Unit) =
        pool.start(ownerId, config, modelProfileId, onPartial)
    fun cancelActive() = pool.cancel(ownerId)
    override fun close() = pool.release(ownerId)
}
