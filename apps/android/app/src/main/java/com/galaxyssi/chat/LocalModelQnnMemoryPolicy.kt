package com.galaxyssi.chat

import android.os.Debug
import android.os.Process
import java.io.Closeable
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

internal data class LocalModelQnnMemoryAdmission(
    val allowed: Boolean,
    val effectiveContextTokens: Int,
    val requiredAvailableBytes: Long,
    val availableBytes: Long,
    val reason: String = ""
)

internal object LocalModelQnnMemoryPolicy {
    const val PROCESS_LIMIT_BYTES = Lfm25QnnDeploymentManifest.MAX_PROCESS_BYTES
    const val WATCHDOG_LIMIT_BYTES = PROCESS_LIMIT_BYTES - 256L * 1024L * 1024L
    private const val DEVICE_HEADROOM_BYTES = 512L * 1024L * 1024L

    fun appliesTo(profile: LocalModelRuntimeProfile): Boolean =
        profile.id == Lfm25QnnDeploymentManifest.MODEL_ID

    fun effectiveContextTokens(profile: LocalModelRuntimeProfile, requested: Int): Int =
        if (appliesTo(profile)) {
            requested.coerceIn(512, Lfm25QnnDeploymentManifest.MAX_CONTEXT_LIMIT)
        } else {
            requested.coerceIn(512, profile.maximumContextTokens.coerceAtLeast(512))
        }

    fun admission(
        profile: LocalModelRuntimeProfile,
        manifest: Lfm25QnnDeploymentManifest,
        requestedContextTokens: Int,
        availableBytes: Long
    ): LocalModelQnnMemoryAdmission {
        if (!appliesTo(profile)) {
            return LocalModelQnnMemoryAdmission(
                allowed = true,
                effectiveContextTokens = effectiveContextTokens(profile, requestedContextTokens),
                requiredAvailableBytes = 0L,
                availableBytes = availableBytes.coerceAtLeast(0L)
            )
        }
        val context = effectiveContextTokens(profile, requestedContextTokens)
            .coerceAtMost(manifest.maximumContextTokens)
        val required = (manifest.profiledPeakBytes + DEVICE_HEADROOM_BYTES)
            .coerceAtMost(Long.MAX_VALUE)
        val available = availableBytes.coerceAtLeast(0L)
        val reason = when {
            manifest.profiledPeakBytes > Lfm25QnnDeploymentManifest.MAX_PROFILED_PEAK_BYTES ->
                "The signed deployment exceeds the LFM2.5 process-memory budget"
            available < required ->
                "LFM2.5 needs ${formatMiB(required)} available memory including system headroom; " +
                    "only ${formatMiB(available)} is available"
            else -> ""
        }
        return LocalModelQnnMemoryAdmission(
            allowed = reason.isEmpty(),
            effectiveContextTokens = context,
            requiredAvailableBytes = required,
            availableBytes = available,
            reason = reason
        )
    }

    fun requireLaunchable(
        profile: LocalModelRuntimeProfile,
        manifest: Lfm25QnnDeploymentManifest,
        requestedContextTokens: Int,
        availableBytes: Long
    ): LocalModelQnnMemoryAdmission = admission(
        profile,
        manifest,
        requestedContextTokens,
        availableBytes
    ).also { decision ->
        check(decision.allowed) { decision.reason }
    }

    private fun formatMiB(bytes: Long): String = "${bytes / (1024L * 1024L)} MiB"
}

internal fun interface LocalModelProcessMemoryReader {
    fun currentBytes(): Long
}

internal object AndroidLocalModelProcessMemoryReader : LocalModelProcessMemoryReader {
    override fun currentBytes(): Long {
        val pssBytes = Debug.getPss().coerceAtLeast(0L) * 1024L
        val nativeBytes = Debug.getNativeHeapAllocatedSize().coerceAtLeast(0L)
        val rssBytes = readProcStatusBytes("VmRSS")
        return maxOf(pssBytes, nativeBytes, rssBytes)
    }

    private fun readProcStatusBytes(name: String): Long = runCatching {
        File("/proc/self/status").useLines { lines ->
            val line = lines.firstOrNull { it.startsWith("$name:") } ?: return@useLines 0L
            line.substringAfter(':').trim().substringBefore(' ').toLong() * 1024L
        }
    }.getOrDefault(0L)
}

internal class LocalModelRuntimeMemoryWatchdog private constructor(
    private val running: AtomicBoolean,
    private val thread: Thread?,
    val peakBytes: AtomicLong
) : Closeable {
    override fun close() {
        running.set(false)
        thread?.interrupt()
        thread?.takeIf { Thread.currentThread() !== it }?.let { worker ->
            runCatching { worker.join(STOP_JOIN_MILLIS) }
        }
    }

    companion object {
        fun start(
            profile: LocalModelRuntimeProfile,
            reader: LocalModelProcessMemoryReader = AndroidLocalModelProcessMemoryReader,
            onLimit: (Long) -> Unit = { Process.killProcess(Process.myPid()) }
        ): LocalModelRuntimeMemoryWatchdog {
            if (!LocalModelQnnMemoryPolicy.appliesTo(profile)) {
                return LocalModelRuntimeMemoryWatchdog(AtomicBoolean(false), null, AtomicLong(0L))
            }
            val running = AtomicBoolean(true)
            val peak = AtomicLong(0L)
            val worker = Thread({
                while (running.get()) {
                    val current = runCatching(reader::currentBytes).getOrDefault(0L).coerceAtLeast(0L)
                    peak.accumulateAndGet(current, ::maxOf)
                    if (current >= LocalModelQnnMemoryPolicy.WATCHDOG_LIMIT_BYTES) {
                        running.set(false)
                        onLimit(current)
                        break
                    }
                    try {
                        Thread.sleep(SAMPLE_INTERVAL_MILLIS)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }, "GalaxySSI-LFM-Memory-Guard").apply {
                isDaemon = true
                start()
            }
            return LocalModelRuntimeMemoryWatchdog(running, worker, peak)
        }

        private const val SAMPLE_INTERVAL_MILLIS = 25L
        private const val STOP_JOIN_MILLIS = 250L
    }
}
