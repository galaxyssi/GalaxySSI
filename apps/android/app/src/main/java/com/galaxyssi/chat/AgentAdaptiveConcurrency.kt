package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock as withCoroutineLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.concurrent.withLock as withBlockingLock
import kotlin.math.floor

internal enum class AgentConcurrencyWorkload {
    READ_REASONING,
    NATIVE_READ_IO,
    NATIVE_MUTATION
}

internal data class AgentAdaptiveConcurrencySignals(
    val logicalProcessorCount: Int,
    val totalMemoryBytes: Long,
    val availableMemoryBytes: Long,
    val lowMemory: Boolean,
    val thermalStatus: Int,
    val cpuLoadPercent: Int?
)

/** Computes admission capacity without terminating work that is already running. */
internal object AgentAdaptiveConcurrencyPolicy {
    const val MIN_CONCURRENCY = 1
    const val DEFAULT_CONCURRENCY = 4
    const val MAX_CONCURRENCY = 64

    fun limit(
        signals: AgentAdaptiveConcurrencySignals,
        workload: AgentConcurrencyWorkload
    ): Int {
        if (signals.lowMemory) return MIN_CONCURRENCY
        val processors = signals.logicalProcessorCount.coerceAtLeast(1)
        val cpuMultiplier = when (workload) {
            AgentConcurrencyWorkload.READ_REASONING -> 2
            AgentConcurrencyWorkload.NATIVE_READ_IO -> 8
            AgentConcurrencyWorkload.NATIVE_MUTATION -> 4
        }
        val bytesPerTask = when (workload) {
            AgentConcurrencyWorkload.READ_REASONING -> 256L * MIB
            AgentConcurrencyWorkload.NATIVE_READ_IO -> 64L * MIB
            AgentConcurrencyWorkload.NATIVE_MUTATION -> 128L * MIB
        }
        val cpuBound = processors.toLong() * cpuMultiplier
        val memoryBound = if (signals.availableMemoryBytes > 0L) {
            signals.availableMemoryBytes / bytesPerTask
        } else {
            cpuBound
        }
        val unpressured = minOf(cpuBound, memoryBound)
            .coerceIn(MIN_CONCURRENCY.toLong(), MAX_CONCURRENCY.toLong())
            .toInt()
        val thermalScale = when {
            signals.thermalStatus >= THERMAL_STATUS_CRITICAL -> 0.10
            signals.thermalStatus >= THERMAL_STATUS_SEVERE -> 0.25
            signals.thermalStatus >= THERMAL_STATUS_MODERATE -> 0.50
            signals.thermalStatus >= THERMAL_STATUS_LIGHT -> 0.75
            else -> 1.0
        }
        val cpuScale = when (signals.cpuLoadPercent ?: 0) {
            in 90..Int.MAX_VALUE -> 0.25
            in 75..89 -> 0.50
            in 60..74 -> 0.75
            else -> 1.0
        }
        return floor(unpressured * minOf(thermalScale, cpuScale))
            .toInt()
            .coerceIn(MIN_CONCURRENCY, MAX_CONCURRENCY)
    }

    private const val MIB = 1024L * 1024L
    private const val THERMAL_STATUS_LIGHT = 1
    private const val THERMAL_STATUS_MODERATE = 2
    private const val THERMAL_STATUS_SEVERE = 3
    private const val THERMAL_STATUS_CRITICAL = 4
}

/** Android-backed signal sampler shared by task and native-tool admission. */
internal object AgentAdaptiveConcurrencyRuntime {
    @Volatile private var appContext: Context? = null
    @Volatile private var cachedSignals: AgentAdaptiveConcurrencySignals? = null
    @Volatile private var cachedAtElapsedMillis: Long = 0L
    private val sampleLock = Any()
    private val cpuSampler = AgentCpuLoadSampler()

    fun initialize(context: Context) {
        if (appContext != null) return
        synchronized(sampleLock) {
            if (appContext == null) appContext = context.applicationContext
        }
    }

    fun currentLimit(workload: AgentConcurrencyWorkload): Int {
        val context = appContext ?: return AgentAdaptiveConcurrencyPolicy.DEFAULT_CONCURRENCY
        return AgentAdaptiveConcurrencyPolicy.limit(signals(context), workload)
    }

    private fun signals(context: Context): AgentAdaptiveConcurrencySignals {
        val now = SystemClock.elapsedRealtime()
        cachedSignals?.takeIf { now - cachedAtElapsedMillis < SAMPLE_TTL_MILLIS }?.let { return it }
        return synchronized(sampleLock) {
            cachedSignals?.takeIf { now - cachedAtElapsedMillis < SAMPLE_TTL_MILLIS } ?: sample(context).also {
                cachedSignals = it
                cachedAtElapsedMillis = now
            }
        }
    }

    private fun sample(context: Context): AgentAdaptiveConcurrencySignals {
        val activity = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        runCatching { activity?.getMemoryInfo(memory) }
        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching { context.getSystemService(PowerManager::class.java)?.currentThermalStatus }
                .getOrNull()
                ?: 0
        } else {
            0
        }
        return AgentAdaptiveConcurrencySignals(
            logicalProcessorCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1),
            totalMemoryBytes = memory.totalMem.coerceAtLeast(0L),
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L),
            lowMemory = memory.lowMemory || activity?.isLowRamDevice == true,
            thermalStatus = thermal.coerceAtLeast(0),
            cpuLoadPercent = cpuSampler.sample()
        )
    }

    private const val SAMPLE_TTL_MILLIS = 1_000L
}

/** A cancellable coroutine gate whose capacity may change between admissions. */
internal class AgentAdaptiveCoroutinePermitGate(
    private val limitProvider: () -> Int,
    private val maximum: Int = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY
) {
    private val stateLock = Mutex()
    private val changed = Channel<Unit>(Channel.CONFLATED)
    private var active = 0

    suspend fun acquire() {
        while (true) {
            val acquired = stateLock.withCoroutineLock {
                val limit = limitProvider().coerceIn(1, maximum)
                if (active < limit) {
                    active += 1
                    if (active < limit) changed.trySend(Unit)
                    true
                } else {
                    false
                }
            }
            if (acquired) return
            withTimeoutOrNull(RECHECK_MILLIS) { changed.receive() }
        }
    }

    suspend fun release() {
        stateLock.withCoroutineLock {
            check(active > 0) { "Adaptive concurrency permit released without an owner" }
            active -= 1
        }
        changed.trySend(Unit)
    }

    private companion object {
        const val RECHECK_MILLIS = 1_000L
    }
}

/** Blocking equivalent used by synchronous native-tool execution. */
internal class AgentAdaptiveBlockingPermitGate(
    private val limitProvider: () -> Int,
    private val maximum: Int = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY
) {
    private val lock = ReentrantLock(true)
    private val changed = lock.newCondition()
    private var active = 0

    fun acquire(checkpoint: () -> Unit) {
        while (true) {
            checkpoint()
            try {
                lock.withBlockingLock {
                    val limit = limitProvider().coerceIn(1, maximum)
                    if (active < limit) {
                        active += 1
                        if (active < limit) changed.signal()
                        return
                    }
                    changed.await(RECHECK_MILLIS, TimeUnit.MILLISECONDS)
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                throw AgentNativeToolCancelledException()
            }
        }
    }

    fun release() {
        lock.withBlockingLock {
            check(active > 0) { "Adaptive concurrency permit released without an owner" }
            active -= 1
            changed.signalAll()
        }
    }

    private companion object {
        const val RECHECK_MILLIS = 100L
    }
}

private class AgentCpuLoadSampler {
    private var previousTotal = 0L
    private var previousIdle = 0L

    @Synchronized
    fun sample(): Int? {
        val counters = runCatching {
            File("/proc/stat").useLines { lines ->
                val fields = lines.firstOrNull { it.startsWith("cpu ") }
                    ?.trim()
                    ?.split(Regex("\\s+"))
                    ?.drop(1)
                    ?.map(String::toLong)
                    ?: return@useLines null
                if (fields.size < 4) return@useLines null
                val idle = fields[3] + fields.getOrElse(4) { 0L }
                fields.sum() to idle
            }
        }.getOrNull() ?: return null
        val totalDelta = counters.first - previousTotal
        val idleDelta = counters.second - previousIdle
        previousTotal = counters.first
        previousIdle = counters.second
        if (totalDelta <= 0L) return null
        return (((totalDelta - idleDelta).coerceAtLeast(0L) * 100L) / totalDelta)
            .toInt()
            .coerceIn(0, 100)
    }
}
