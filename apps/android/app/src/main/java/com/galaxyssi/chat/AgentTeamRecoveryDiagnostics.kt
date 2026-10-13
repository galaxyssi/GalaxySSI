package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.Collections
import java.util.IdentityHashMap

internal enum class TeamRecoveryTraceStage {
    CHECKPOINT_READ, CHECKPOINT_WRITE, INTERRUPTED, RESUME_ATTEMPT,
    RESUME_READY, RESUME_BLOCKED, RESUME_FAILURE, AWAIT_FAILURE, WATCH_FAILURE,
    RECOVERY_DEFERRED, RECOVERY_STOPPED
}

internal enum class TeamRecoveryTraceSource { NONE, PERIODIC, USER_RESUME, WATCH_RELEASE }

/** Debug metadata only: never retain exception messages, goals, checkpoint bodies, or raw run IDs. */
internal class TeamRecoveryTraceRecorder(
    private val enabled: Boolean,
    private val clock: () -> Long = System::nanoTime,
    private val emit: (String) -> Unit,
    private val intervalNanos: Long = 5_000_000_000L,
    private val capacity: Int = 128
) {
    private data class Stats(var count: Long = 0, var elapsedNanos: Long = 0,
        var maxNanos: Long = 0, var lastEmitted: Long? = null, var failure: String = "")
    private val counters = LinkedHashMap<String, Stats>(16, 0.75f, true)

    init { require(intervalNanos > 0 && capacity > 0) }

    fun record(runId: String, stage: TeamRecoveryTraceStage,
        source: TeamRecoveryTraceSource = TeamRecoveryTraceSource.NONE,
        elapsedNanos: Long = 0, failure: Throwable? = null,
        sequence: Long? = null, completedChildren: Int? = null) {
        if (!enabled) return
        // Diagnostics must never change task completion, cancellation, or exception propagation.
        runCatching {
            val digest = MessageDigest.getInstance("SHA-256").digest(runId.toByteArray(Charsets.UTF_8))
            val run = buildString(12) {
                repeat(6) {
                    val value = digest[it].toInt() and 0xff
                    append("0123456789abcdef"[value ushr 4])
                    append("0123456789abcdef"[value and 15])
                }
            }
            val fault = failure?.let(::failureSites).orEmpty()
            val now = clock()
            val line = synchronized(counters) {
                val key = "$run:$stage:$source"
                val stats = counters.getOrPut(key) { Stats() }
                stats.count++
                stats.elapsedNanos += elapsedNanos.coerceAtLeast(0)
                stats.maxNanos = maxOf(stats.maxNanos, elapsedNanos)
                val changedFailure = fault.isNotEmpty() && stats.failure != fault
                stats.failure = fault
                while (counters.size > capacity) counters.remove(counters.keys.first())
                if (stats.lastEmitted != null && !changedFailure && now - stats.lastEmitted!! < intervalNanos) null
                else {
                    stats.lastEmitted = now
                    "run=$run stage=$stage source=$source count=${stats.count} " +
                        "total_ms=${stats.elapsedNanos / 1_000_000} max_ms=${stats.maxNanos / 1_000_000}" +
                        (sequence?.let { " sequence=$it" } ?: "") +
                        (completedChildren?.let { " completed=$it" } ?: "") +
                        (if (fault.isBlank()) "" else " causes=$fault")
                }
            }
            if (line != null) emit(line)
        }
    }

    fun <T> measure(runId: String, stage: TeamRecoveryTraceStage, block: () -> T): T {
        if (!enabled) return block()
        val started = runCatching(clock).getOrNull()
        var failure: Throwable? = null
        try { return block() }
        catch (error: Throwable) { failure = error; throw error }
        finally {
            val elapsed = started?.let { runCatching { clock() - it }.getOrDefault(0) } ?: 0
            record(runId, stage, elapsedNanos = elapsed, failure = failure)
        }
    }

    internal fun retainedCounters(): Int = synchronized(counters) { counters.size }

    private fun failureSites(failure: Throwable): String {
        val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
        val causes = mutableListOf<String>()
        var current: Throwable? = failure
        while (current != null && causes.size < 8 && seen.add(current)) {
            val error = current
            val frames = error.stackTrace.filter { it.className.startsWith("com.galaxyssi.") }
                .ifEmpty { error.stackTrace.take(3) }.take(6)
            causes += error.javaClass.simpleName + frames.joinToString(prefix = "[", postfix = "]", separator = ";") {
                "${it.className}.${it.methodName}:${it.lineNumber}"
            }
            current = error.cause
        }
        return causes.joinToString("<-")
    }
}

internal object AgentTeamRecoveryDiagnostics {
    private val recorder = TeamRecoveryTraceRecorder(BuildConfig.DEBUG,
        emit = { android.util.Log.i("GalaxySSITeamRecovery", it) })

    fun record(runId: String, stage: TeamRecoveryTraceStage,
        source: TeamRecoveryTraceSource = TeamRecoveryTraceSource.NONE, failure: Throwable? = null,
        sequence: Long? = null, completedChildren: Int? = null) =
        recorder.record(runId, stage, source, failure = failure, sequence = sequence, completedChildren = completedChildren)

    fun <T> measure(runId: String, stage: TeamRecoveryTraceStage, block: () -> T): T =
        recorder.measure(runId, stage, block)
}
