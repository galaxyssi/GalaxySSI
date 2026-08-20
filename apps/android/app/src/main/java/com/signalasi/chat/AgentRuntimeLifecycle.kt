package com.signalasi.chat

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.math.min

enum class AgentRuntimeLifecyclePhase(val wireValue: String) {
    BLOCKED("blocked"),
    STOPPED("stopped"),
    STARTING("starting"),
    READY("ready"),
    DEGRADED("degraded"),
    BACKING_OFF("backing_off"),
    STOPPING("stopping")
}

data class AgentRuntimeLifecycleSnapshot(
    val phase: AgentRuntimeLifecyclePhase,
    val controllerId: String = "",
    val reason: String = "",
    val consecutiveFailures: Int = 0,
    val lastTransitionAtMillis: Long = 0L,
    val lastReadyAtMillis: Long = 0L,
    val nextAttemptAtMillis: Long = 0L
)

internal data class AgentRuntimeExecutionLease(
    val generation: Long,
    val lifecycle: AgentRuntimeLifecycleSnapshot
)

/**
 * Serializes automatic guest recovery across conversations. A timeout may only
 * quarantine the runtime generation in which that command started, so a late
 * failure cannot stop a newer healthy guest.
 */
internal class AgentRuntimeRecoveryGate {
    private val lock = ReentrantLock()
    private var generation = 0L
    private var quarantined = false

    fun acquire(ensureReady: () -> AgentRuntimeLifecycleSnapshot): AgentRuntimeExecutionLease = lock.withLock {
        val lifecycle = ensureReady()
        if (lifecycle.phase == AgentRuntimeLifecyclePhase.READY) quarantined = false
        AgentRuntimeExecutionLease(generation, lifecycle)
    }

    fun quarantine(lease: AgentRuntimeExecutionLease, stopRuntime: () -> Unit): Boolean = lock.withLock {
        if (lease.generation != generation || quarantined) return false
        quarantined = true
        generation += 1L
        stopRuntime()
        true
    }
}

internal object AgentOnDeviceRuntimeRecovery {
    private val gate = AgentRuntimeRecoveryGate()

    fun acquire(context: Context): AgentRuntimeExecutionLease = gate.acquire {
        AgentOnDeviceRuntimeLifecycle.ensureRunning(context.applicationContext)
    }

    fun quarantine(context: Context, lease: AgentRuntimeExecutionLease): Boolean = gate.quarantine(lease) {
        AgentOnDeviceRuntimeLifecycle.stop(context.applicationContext)
    }

    fun rebuildPersistentSystem(
        context: Context,
        lease: AgentRuntimeExecutionLease,
        runtimeRoot: File
    ): Boolean = gate.quarantine(lease) {
        AgentOnDeviceRuntimeLifecycle.stop(context.applicationContext)
        AgentRuntimePersistentDisk.quarantine(runtimeRoot)
    }
}

fun interface AgentRuntimeLifecycleClock {
    fun nowMillis(): Long

    companion object {
        val SYSTEM = AgentRuntimeLifecycleClock(System::currentTimeMillis)
    }
}

internal class AgentRuntimeLifecycleStateMachine(
    private val clock: AgentRuntimeLifecycleClock = AgentRuntimeLifecycleClock.SYSTEM,
    initial: AgentRuntimeLifecycleSnapshot = AgentRuntimeLifecycleSnapshot(
        phase = AgentRuntimeLifecyclePhase.STOPPED,
        reason = "Runtime has not been started"
    )
) {
    private var current = initial

    @Synchronized
    fun snapshot(): AgentRuntimeLifecycleSnapshot = current

    @Synchronized
    fun blocked(reason: String): AgentRuntimeLifecycleSnapshot = transition(
        phase = AgentRuntimeLifecyclePhase.BLOCKED,
        reason = reason,
        failures = current.consecutiveFailures,
        nextAttemptAtMillis = 0L
    )

    @Synchronized
    fun stopped(reason: String, resetFailures: Boolean): AgentRuntimeLifecycleSnapshot = transition(
        phase = AgentRuntimeLifecyclePhase.STOPPED,
        reason = reason,
        failures = if (resetFailures) 0 else current.consecutiveFailures,
        nextAttemptAtMillis = 0L
    )

    @Synchronized
    fun beginStart(controllerId: String, force: Boolean): AgentRuntimeLifecycleSnapshot {
        val now = clock.nowMillis()
        if (!force && current.phase == AgentRuntimeLifecyclePhase.BACKING_OFF && current.nextAttemptAtMillis > now) {
            return current
        }
        return transition(
            phase = AgentRuntimeLifecyclePhase.STARTING,
            reason = "Waiting for the guest health handshake",
            controllerId = controllerId,
            failures = current.consecutiveFailures,
            nextAttemptAtMillis = 0L
        )
    }

    @Synchronized
    fun ready(
        controllerId: String,
        reason: String = "Guest runtime health handshake completed"
    ): AgentRuntimeLifecycleSnapshot {
        val now = clock.nowMillis()
        current = AgentRuntimeLifecycleSnapshot(
            phase = AgentRuntimeLifecyclePhase.READY,
            controllerId = controllerId,
            reason = reason,
            consecutiveFailures = 0,
            lastTransitionAtMillis = now,
            lastReadyAtMillis = now,
            nextAttemptAtMillis = 0L
        )
        return current
    }

    @Synchronized
    fun degraded(controllerId: String, reason: String): AgentRuntimeLifecycleSnapshot = transition(
        phase = AgentRuntimeLifecyclePhase.DEGRADED,
        reason = reason,
        controllerId = controllerId,
        failures = current.consecutiveFailures,
        nextAttemptAtMillis = 0L
    )

    @Synchronized
    fun failed(controllerId: String, reason: String): AgentRuntimeLifecycleSnapshot {
        val failures = (current.consecutiveFailures + 1).coerceAtMost(MAX_FAILURES)
        val multiplier = 1L shl (failures - 1).coerceAtMost(MAX_BACKOFF_SHIFT)
        val delay = min(MAX_BACKOFF_MILLIS, BASE_BACKOFF_MILLIS * multiplier)
        return transition(
            phase = AgentRuntimeLifecyclePhase.BACKING_OFF,
            reason = reason,
            controllerId = controllerId,
            failures = failures,
            nextAttemptAtMillis = clock.nowMillis() + delay
        )
    }

    @Synchronized
    fun stopping(controllerId: String): AgentRuntimeLifecycleSnapshot = transition(
        phase = AgentRuntimeLifecyclePhase.STOPPING,
        reason = "Stopping the guest runtime",
        controllerId = controllerId,
        failures = current.consecutiveFailures,
        nextAttemptAtMillis = 0L
    )

    private fun transition(
        phase: AgentRuntimeLifecyclePhase,
        reason: String,
        controllerId: String = current.controllerId,
        failures: Int,
        nextAttemptAtMillis: Long
    ): AgentRuntimeLifecycleSnapshot {
        current = current.copy(
            phase = phase,
            controllerId = controllerId,
            reason = reason,
            consecutiveFailures = failures,
            lastTransitionAtMillis = clock.nowMillis(),
            nextAttemptAtMillis = nextAttemptAtMillis
        )
        return current
    }

    companion object {
        private const val BASE_BACKOFF_MILLIS = 1_000L
        private const val MAX_BACKOFF_MILLIS = 60_000L
        private const val MAX_BACKOFF_SHIFT = 6
        private const val MAX_FAILURES = 1_000
    }
}

class AgentRuntimeEngineLaunchSpec internal constructor(
    val engineFile: File,
    val baseImageFile: File,
    val socketFile: File,
    val packsDirectory: File,
    val workspacesDirectory: File,
    val architecture: String,
    val packAttachments: List<AgentRuntimePackAttachment> = emptyList(),
    internal val sessionKey: ByteArray,
    val systemDiskFile: File = File(workspacesDirectory.parentFile, "system/signalasi-system.raw")
) {
    override fun toString(): String =
        "AgentRuntimeEngineLaunchSpec(engine=${engineFile.name}, architecture=$architecture, sessionKey=[redacted])"

    internal fun clearSecrets() = sessionKey.fill(0)
}

data class AgentRuntimePackAttachment(
    val packId: String,
    val version: String,
    val capabilities: Set<String> = emptySet(),
    val imageFile: File
)

interface AgentRuntimeEngineController {
    val controllerId: String
    fun isRunning(): Boolean
    fun start(spec: AgentRuntimeEngineLaunchSpec)
    fun stop()
}

object AgentRuntimeEngineControllerRegistry {
    @Volatile private var active: AgentRuntimeEngineController? = null

    @Synchronized
    fun register(controller: AgentRuntimeEngineController) {
        active = controller
    }

    @Synchronized
    fun unregister(controller: AgentRuntimeEngineController) {
        if (active === controller) active = null
    }

    fun current(): AgentRuntimeEngineController? = active

    @Synchronized
    fun currentOrInstall(context: Context): AgentRuntimeEngineController = active
        ?: AgentQemuRuntimeEngineController(context.applicationContext).also { active = it }
}

private class AgentRuntimeLifecycleStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun load(): AgentRuntimeLifecycleSnapshot? = database.readString(KEY_SNAPSHOT, "")
        .takeIf(String::isNotBlank)
        ?.let { raw ->
            runCatching {
                val value = JSONObject(raw)
                AgentRuntimeLifecycleSnapshot(
                    phase = AgentRuntimeLifecyclePhase.valueOf(value.getString("phase")),
                    controllerId = value.optString("controller_id"),
                    reason = value.optString("reason"),
                    consecutiveFailures = value.optInt("consecutive_failures").coerceAtLeast(0),
                    lastTransitionAtMillis = value.optLong("last_transition_at_millis").coerceAtLeast(0L),
                    lastReadyAtMillis = value.optLong("last_ready_at_millis").coerceAtLeast(0L),
                    nextAttemptAtMillis = value.optLong("next_attempt_at_millis").coerceAtLeast(0L)
                )
            }.getOrNull()
        }

    @Synchronized
    fun save(snapshot: AgentRuntimeLifecycleSnapshot) {
        database.writeString(KEY_SNAPSHOT, JSONObject()
            .put("phase", snapshot.phase.name)
            .put("controller_id", snapshot.controllerId)
            .put("reason", snapshot.reason)
            .put("consecutive_failures", snapshot.consecutiveFailures)
            .put("last_transition_at_millis", snapshot.lastTransitionAtMillis)
            .put("last_ready_at_millis", snapshot.lastReadyAtMillis)
            .put("next_attempt_at_millis", snapshot.nextAttemptAtMillis)
            .toString())
    }

    companion object {
        private const val DATABASE = "signalasi_runtime_lifecycle_v1"
        private const val KEY_SNAPSHOT = "snapshot"
    }
}

object AgentOnDeviceRuntimeLifecycle {
    @Volatile private var machine: AgentRuntimeLifecycleStateMachine? = null
    @Volatile private var stateStore: AgentRuntimeLifecycleStore? = null
    private val startLock = ReentrantLock()
    private val operationGeneration = AtomicLong(0L)

    fun inspect(context: Context): AgentRuntimeLifecycleSnapshot = inspectInternal(
        context.applicationContext,
        bridgeProbeCompleted = false,
        knownBridgeReady = false
    )

    /** Returns the last persisted in-process state without probing or starting the guest. */
    internal fun cached(context: Context): AgentRuntimeLifecycleSnapshot =
        machine(context.applicationContext).snapshot()

    internal fun inspectAfterBridgeProbe(
        context: Context,
        health: AgentRuntimeBridgeHealth?
    ): AgentRuntimeLifecycleSnapshot = inspectInternal(
        context.applicationContext,
        bridgeProbeCompleted = true,
        knownBridgeReady = health?.ready == true
    )

    @Synchronized
    private fun inspectInternal(
        context: Context,
        bridgeProbeCompleted: Boolean,
        knownBridgeReady: Boolean
    ): AgentRuntimeLifecycleSnapshot {
        val appContext = context.applicationContext
        val state = machine(appContext)
        val controller = AgentRuntimeEngineControllerRegistry.currentOrInstall(appContext)
        val bridgeReady = if (bridgeProbeCompleted) {
            knownBridgeReady
        } else {
            AgentOnDeviceRuntimeSupervisor.discover(appContext)
                ?.let { runCatching { it.health().ready }.getOrDefault(false) } == true
        }
        if (bridgeReady) {
            return persist(appContext, state.ready(controller?.controllerId.orEmpty()))
        }
        val prerequisite = runCatching { AgentOnDeviceRuntimeManager(appContext).runtimeBootstrapFiles() }
        if (prerequisite.isFailure) {
            return persist(
                appContext,
                state.blocked(prerequisite.exceptionOrNull()?.message ?: "Runtime prerequisites are unavailable")
            )
        }
        val running = runCatching(controller::isRunning).getOrDefault(false)
        val current = state.snapshot()
        if (running) {
            return persist(
                appContext,
                if (current.phase == AgentRuntimeLifecyclePhase.STARTING) current else {
                    state.degraded(controller.controllerId, "Runtime engine is running, but the guest bridge is not healthy")
                }
            )
        }
        if (current.phase == AgentRuntimeLifecyclePhase.BACKING_OFF &&
            current.nextAttemptAtMillis > System.currentTimeMillis()
        ) return current
        return persist(appContext, state.stopped("Runtime engine is stopped", resetFailures = false))
    }

    fun start(context: Context, force: Boolean = false): AgentRuntimeLifecycleSnapshot {
        return startLock.withLock {
            val appContext = context.applicationContext
            inspect(appContext).takeIf { it.phase == AgentRuntimeLifecyclePhase.READY }?.let { return@withLock it }
            val controller = AgentRuntimeEngineControllerRegistry.currentOrInstall(appContext)
            val files = runCatching { AgentOnDeviceRuntimeManager(appContext).runtimeBootstrapFiles() }
                .getOrElse { error ->
                    return@withLock persist(
                        appContext,
                        machine(appContext).blocked(error.message ?: "Runtime prerequisites are unavailable")
                    )
                }
            val generation = operationGeneration.get()
            val state = machine(appContext)
            val starting = state.beginStart(controller.controllerId, force)
            persist(appContext, starting)
            if (starting.phase == AgentRuntimeLifecyclePhase.BACKING_OFF) return@withLock starting

            val bootStore = AgentRuntimePackBootStore(appContext)
            val desired = files.packAttachments
            val primary = launchAndAwait(appContext, controller, files, desired, generation)
            if (primary == LaunchOutcome.READY) {
                bootStore.recordHealthy(desired)
                return@withLock persist(appContext, state.ready(controller.controllerId))
            }
            if (primary == LaunchOutcome.INTERRUPTED) return@withLock machine(appContext).snapshot()

            val fallback = AgentRuntimePackBootPolicy.fallbackAttachments(desired, bootStore.lastHealthyVersions())
            if (fallback != desired) {
                val fallbackOutcome = launchAndAwait(appContext, controller, files, fallback, generation)
                if (fallbackOutcome == LaunchOutcome.READY) {
                    val excluded = desired.filterNot { candidate ->
                        fallback.any { it.packId == candidate.packId && it.version == candidate.version }
                    }
                    bootStore.quarantine(excluded)
                    bootStore.recordHealthy(fallback)
                    val names = excluded.joinToString { it.packId }
                    return@withLock persist(
                        appContext,
                        state.ready(controller.controllerId, "Guest recovered after disabling runtime pack: $names")
                    )
                }
                if (fallbackOutcome == LaunchOutcome.INTERRUPTED) return@withLock machine(appContext).snapshot()
            }
            persist(appContext, state.failed(controller.controllerId, "Guest health handshake timed out"))
        }
    }

    private fun launchAndAwait(
        context: Context,
        controller: AgentRuntimeEngineController,
        files: AgentRuntimeBootstrapFiles,
        attachments: List<AgentRuntimePackAttachment>,
        generation: Long
    ): LaunchOutcome {
        runCatching(controller::stop)
        AgentOnDeviceRuntimeSupervisor.reset()
        files.socketFile.delete()
        val spec = AgentRuntimeEngineLaunchSpec(
            engineFile = files.engineFile,
            baseImageFile = files.baseImageFile,
            systemDiskFile = files.systemDiskFile,
            socketFile = files.socketFile,
            packsDirectory = files.packsDirectory,
            workspacesDirectory = files.workspacesDirectory,
            architecture = files.architecture,
            packAttachments = attachments,
            sessionKey = AgentRuntimeSessionKeyStore(context).getOrCreate()
        )
        val launch = runCatching { controller.start(spec) }
        spec.clearSecrets()
        if (launch.isFailure) return LaunchOutcome.FAILED
        val deadline = System.currentTimeMillis() + STARTUP_TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            if (operationGeneration.get() != generation) {
                runCatching(controller::stop)
                return LaunchOutcome.INTERRUPTED
            }
            val bridge = AgentOnDeviceRuntimeSupervisor.discover(context)
            if (bridge != null && runCatching { bridge.health().ready }.getOrDefault(false)) {
                return LaunchOutcome.READY
            }
            try {
                Thread.sleep(HEALTH_POLL_MILLIS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                runCatching(controller::stop)
                return LaunchOutcome.INTERRUPTED
            }
        }
        runCatching(controller::stop)
        AgentOnDeviceRuntimeSupervisor.reset()
        return LaunchOutcome.FAILED
    }

    fun ensureRunning(context: Context, maxAttempts: Int = DEFAULT_AUTO_ATTEMPTS): AgentRuntimeLifecycleSnapshot {
        require(maxAttempts in 1..MAX_AUTO_ATTEMPTS)
        val generation = operationGeneration.get()
        var result = inspect(context)
        repeat(maxAttempts) {
            if (operationGeneration.get() != generation) return inspect(context)
            if (result.phase in setOf(AgentRuntimeLifecyclePhase.READY, AgentRuntimeLifecyclePhase.BLOCKED)) {
                return result
            }
            val waitMillis = (result.nextAttemptAtMillis - System.currentTimeMillis()).coerceAtLeast(0L)
            if (waitMillis > 0L) Thread.sleep(waitMillis)
            if (operationGeneration.get() != generation) return inspect(context)
            result = start(context)
        }
        return result
    }

    @Synchronized
    fun stop(context: Context): AgentRuntimeLifecycleSnapshot {
        val appContext = context.applicationContext
        operationGeneration.incrementAndGet()
        val state = machine(appContext)
        val controller = AgentRuntimeEngineControllerRegistry.current()
        persist(appContext, state.stopping(controller?.controllerId.orEmpty()))
        val stopped = runCatching { controller?.stop() }
        AgentOnDeviceRuntimeSupervisor.reset()
        runCatching { AgentOnDeviceRuntimeManager(appContext).runtimeSocketFile().delete() }
        return persist(
            appContext,
            if (stopped.isSuccess) {
                state.stopped("Runtime stopped by the user", resetFailures = true)
            } else {
                state.degraded(
                    controller?.controllerId.orEmpty(),
                    stopped.exceptionOrNull()?.message ?: "Runtime engine did not stop cleanly"
                )
            }
        )
    }

    fun restart(context: Context): AgentRuntimeLifecycleSnapshot {
        stop(context)
        return start(context, force = true)
    }

    @Synchronized
    private fun machine(context: Context): AgentRuntimeLifecycleStateMachine = machine
        ?: AgentRuntimeLifecycleStateMachine(initial = store(context).load()
            ?: AgentRuntimeLifecycleSnapshot(
                phase = AgentRuntimeLifecyclePhase.STOPPED,
                reason = "Runtime has not been started"
            )).also { machine = it }

    private fun persist(context: Context, snapshot: AgentRuntimeLifecycleSnapshot): AgentRuntimeLifecycleSnapshot {
        store(context).save(snapshot)
        return snapshot
    }

    @Synchronized
    private fun store(context: Context): AgentRuntimeLifecycleStore = stateStore
        ?: AgentRuntimeLifecycleStore(context.applicationContext).also { stateStore = it }

    private enum class LaunchOutcome { READY, FAILED, INTERRUPTED }

    // Leave enough time for a known-good pack fallback before a command-level timeout fires.
    private const val STARTUP_TIMEOUT_MILLIS = 60_000L
    private const val HEALTH_POLL_MILLIS = 200L
    private const val DEFAULT_AUTO_ATTEMPTS = 3
    private const val MAX_AUTO_ATTEMPTS = 8
}
