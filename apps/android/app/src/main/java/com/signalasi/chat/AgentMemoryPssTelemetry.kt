package com.signalasi.chat

import android.content.Context
import android.os.Debug
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject

enum class AgentMemoryMeasurementKind(val wireName: String) {
    ANDROID_PSS("android_pss")
}

enum class AgentMemoryAttributionMode(val wireName: String) {
    PROCESS_TOTAL("process_total"),
    SHARED_WEIGHTED("shared_weighted")
}

data class AgentMemoryPssReading(
    val totalBytes: Long,
    val nativeBytes: Long = 0L,
    val dalvikBytes: Long = 0L,
    val otherBytes: Long = 0L,
    val measurementKind: AgentMemoryMeasurementKind = AgentMemoryMeasurementKind.ANDROID_PSS
)

data class AgentMemoryPssSample(
    val id: String,
    val sampledAtMillis: Long,
    val processTotalBytes: Long,
    val attributedBytes: Long,
    val nativeBytes: Long,
    val dalvikBytes: Long,
    val otherBytes: Long,
    val measurementKind: String,
    val attributionMode: String,
    val agentId: String = "",
    val sessionId: String = "",
    val conversationId: String = "",
    val providerId: String = "",
    val taskId: String = ""
)

data class AgentMemoryDimensionStats(
    val id: String,
    val currentBytes: Long,
    val peakBytes: Long,
    val averageBytes: Long,
    val sampleCount: Int,
    val lastSampledAtMillis: Long,
    val estimated: Boolean
)

data class AgentMemoryPssSnapshot(
    val measurementKind: String = AgentMemoryMeasurementKind.ANDROID_PSS.wireName,
    val sampledAtMillis: Long = 0L,
    val processCurrentBytes: Long = 0L,
    val processPeakBytes: Long = 0L,
    val nativeBytes: Long = 0L,
    val dalvikBytes: Long = 0L,
    val otherBytes: Long = 0L,
    val sampleCount: Int = 0,
    val byAgent: List<AgentMemoryDimensionStats> = emptyList(),
    val bySession: List<AgentMemoryDimensionStats> = emptyList(),
    val byProvider: List<AgentMemoryDimensionStats> = emptyList(),
    val sessionBudget: AgentSessionMemoryBudgetSnapshot = AgentSessionMemoryBudgetSnapshot()
)

fun interface AgentMemoryPssSampler {
    fun sample(): AgentMemoryPssReading
}

class AndroidAgentMemoryPssSampler : AgentMemoryPssSampler {
    override fun sample(): AgentMemoryPssReading {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        return AgentMemoryPssReading(
            totalBytes = info.totalPss.toLong().coerceAtLeast(0L) * BYTES_PER_KIB,
            nativeBytes = info.nativePss.toLong().coerceAtLeast(0L) * BYTES_PER_KIB,
            dalvikBytes = info.dalvikPss.toLong().coerceAtLeast(0L) * BYTES_PER_KIB,
            otherBytes = info.otherPss.toLong().coerceAtLeast(0L) * BYTES_PER_KIB
        )
    }

    private companion object {
        const val BYTES_PER_KIB = 1024L
    }
}

interface AgentMemoryPssSampleStore {
    fun append(sample: AgentMemoryPssSample)
    fun recent(limit: Int, sinceMillis: Long): List<AgentMemoryPssSample>
    fun prune(beforeMillis: Long, maxSamples: Int)
}

class InMemoryAgentMemoryPssSampleStore : AgentMemoryPssSampleStore {
    private val samples = mutableListOf<AgentMemoryPssSample>()

    @Synchronized
    override fun append(sample: AgentMemoryPssSample) {
        samples += sample
    }

    @Synchronized
    override fun recent(limit: Int, sinceMillis: Long): List<AgentMemoryPssSample> =
        samples.asSequence()
            .filter { it.sampledAtMillis >= sinceMillis }
            .sortedWith(compareBy<AgentMemoryPssSample> { it.sampledAtMillis }.thenBy { it.id })
            .toList()
            .takeLast(limit.coerceAtLeast(1))

    @Synchronized
    override fun prune(beforeMillis: Long, maxSamples: Int) {
        samples.removeAll { it.sampledAtMillis < beforeMillis }
        if (samples.size > maxSamples) {
            samples.subList(0, samples.size - maxSamples).clear()
        }
    }
}

class EncryptedAgentMemoryPssSampleStore(context: Context) : AgentMemoryPssSampleStore {
    private val database = AgentEncryptedDatabase(
        context.applicationContext,
        "signalasi_agent_memory_pss"
    )

    @Synchronized
    override fun append(sample: AgentMemoryPssSample) {
        database.writeString(keyFor(sample), encode(sample).toString())
    }

    @Synchronized
    override fun recent(limit: Int, sinceMillis: Long): List<AgentMemoryPssSample> =
        database.keys(SAMPLE_PREFIX)
            .asSequence()
            .mapNotNull { key ->
                val timestamp = key.removePrefix(SAMPLE_PREFIX)
                    .substringBefore(':')
                    .toLongOrNull()
                    ?: return@mapNotNull null
                key to timestamp
            }
            .filter { (_, timestamp) -> timestamp >= sinceMillis }
            .sortedWith(compareBy<Pair<String, Long>> { it.second }.thenBy { it.first })
            .toList()
            .takeLast(limit.coerceAtLeast(1))
            .map { it.first }
            .let(database::readStrings)
            .values
            .mapNotNull(::decode)
            .sortedWith(compareBy<AgentMemoryPssSample> { it.sampledAtMillis }.thenBy { it.id })

    @Synchronized
    override fun prune(beforeMillis: Long, maxSamples: Int) {
        val entries = database.keys(SAMPLE_PREFIX)
            .map { key ->
                key to key.removePrefix(SAMPLE_PREFIX)
                    .substringBefore(':')
                    .toLongOrNull()
                    .orEmptyTimestamp()
            }
            .sortedWith(compareBy<Pair<String, Long>> { it.second }.thenBy { it.first })
        val retained = entries.filter { it.second >= beforeMillis }
        val overflow = (retained.size - maxSamples.coerceAtLeast(1)).coerceAtLeast(0)
        val removeKeys = buildList {
            entries.filter { it.second < beforeMillis }.forEach { add(it.first) }
            retained.take(overflow).forEach { add(it.first) }
        }
        database.removeAll(removeKeys)
    }

    private fun Long?.orEmptyTimestamp(): Long = this ?: Long.MIN_VALUE

    private fun keyFor(sample: AgentMemoryPssSample): String =
        "$SAMPLE_PREFIX${sample.sampledAtMillis.toString().padStart(13, '0')}:${sample.id}"

    private fun encode(sample: AgentMemoryPssSample): JSONObject = JSONObject()
        .put("id", sample.id)
        .put("sampled_at_millis", sample.sampledAtMillis)
        .put("process_total_bytes", sample.processTotalBytes)
        .put("attributed_bytes", sample.attributedBytes)
        .put("native_bytes", sample.nativeBytes)
        .put("dalvik_bytes", sample.dalvikBytes)
        .put("other_bytes", sample.otherBytes)
        .put("measurement_kind", sample.measurementKind)
        .put("attribution_mode", sample.attributionMode)
        .put("agent_id", sample.agentId)
        .put("session_id", sample.sessionId)
        .put("conversation_id", sample.conversationId)
        .put("provider_id", sample.providerId)
        .put("task_id", sample.taskId)

    private fun decode(value: String): AgentMemoryPssSample? = runCatching {
        val source = JSONObject(value)
        AgentMemoryPssSample(
            id = source.getString("id"),
            sampledAtMillis = source.getLong("sampled_at_millis"),
            processTotalBytes = source.optLong("process_total_bytes").coerceAtLeast(0L),
            attributedBytes = source.optLong("attributed_bytes").coerceAtLeast(0L),
            nativeBytes = source.optLong("native_bytes").coerceAtLeast(0L),
            dalvikBytes = source.optLong("dalvik_bytes").coerceAtLeast(0L),
            otherBytes = source.optLong("other_bytes").coerceAtLeast(0L),
            measurementKind = source.optString("measurement_kind")
                .ifBlank { AgentMemoryMeasurementKind.ANDROID_PSS.wireName },
            attributionMode = source.optString("attribution_mode")
                .ifBlank { AgentMemoryAttributionMode.PROCESS_TOTAL.wireName },
            agentId = source.optString("agent_id"),
            sessionId = source.optString("session_id"),
            conversationId = source.optString("conversation_id"),
            providerId = source.optString("provider_id"),
            taskId = source.optString("task_id")
        )
    }.getOrNull()

    private companion object {
        const val SAMPLE_PREFIX = "sample:"
    }
}

object AgentMemoryPssAggregation {
    fun snapshot(samples: List<AgentMemoryPssSample>): AgentMemoryPssSnapshot {
        if (samples.isEmpty()) return AgentMemoryPssSnapshot()
        val ordered = samples.sortedWith(
            compareBy<AgentMemoryPssSample> { it.sampledAtMillis }.thenBy { it.id }
        )
        val latestAt = ordered.last().sampledAtMillis
        val latest = ordered.last()
        return AgentMemoryPssSnapshot(
            measurementKind = latest.measurementKind,
            sampledAtMillis = latestAt,
            processCurrentBytes = ordered
                .filter { it.sampledAtMillis == latestAt }
                .maxOfOrNull(AgentMemoryPssSample::processTotalBytes)
                ?: latest.processTotalBytes,
            processPeakBytes = ordered.maxOf(AgentMemoryPssSample::processTotalBytes),
            nativeBytes = latest.nativeBytes,
            dalvikBytes = latest.dalvikBytes,
            otherBytes = latest.otherBytes,
            sampleCount = ordered.size,
            byAgent = aggregate(ordered, AgentMemoryPssSample::agentId),
            bySession = aggregate(ordered, AgentMemoryPssSample::sessionId),
            byProvider = aggregate(ordered, AgentMemoryPssSample::providerId)
        )
    }

    private fun aggregate(
        samples: List<AgentMemoryPssSample>,
        key: (AgentMemoryPssSample) -> String
    ): List<AgentMemoryDimensionStats> = samples.asSequence()
        .filter { key(it).isNotBlank() }
        .groupBy(key)
        .map { (id, values) ->
            val ordered = values.sortedWith(
                compareBy<AgentMemoryPssSample> { it.sampledAtMillis }.thenBy { it.id }
            )
            AgentMemoryDimensionStats(
                id = id,
                currentBytes = if (ordered.last().sampledAtMillis == samples.last().sampledAtMillis) {
                    ordered.last().attributedBytes
                } else {
                    0L
                },
                peakBytes = ordered.maxOf(AgentMemoryPssSample::attributedBytes),
                averageBytes = ordered.sumOf(AgentMemoryPssSample::attributedBytes) /
                    ordered.size.coerceAtLeast(1),
                sampleCount = ordered.size,
                lastSampledAtMillis = ordered.last().sampledAtMillis,
                estimated = ordered.any {
                    it.attributionMode != AgentMemoryAttributionMode.PROCESS_TOTAL.wireName
                }
            )
        }
        .sortedWith(
            compareByDescending<AgentMemoryDimensionStats> { it.currentBytes }
                .thenByDescending { it.peakBytes }
                .thenBy { it.id.lowercase(Locale.ROOT) }
        )
        .toList()
}

class AgentMemoryPssMonitor(
    private val sampler: AgentMemoryPssSampler,
    private val store: AgentMemoryPssSampleStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val retentionMillis: Long = DEFAULT_RETENTION_MILLIS,
    private val maxSamples: Int = DEFAULT_MAX_SAMPLES
) {
    private var history = store.recent(
        minOf(maxSamples, STARTUP_HYDRATION_SAMPLE_LIMIT),
        clock() - retentionMillis
    ).toMutableList()
    private var capturesSincePrune = 0
    @Volatile private var cachedSnapshot = AgentMemoryPssAggregation.snapshot(history)

    @Synchronized
    fun capture(activeWorkspaces: List<AgentWorkspace>): AgentMemoryPssSnapshot {
        val reading = sampler.sample()
        val sampledAt = clock()
        val active = activeWorkspaces
            .filterNot { it.cancellationRequested }
            .distinctBy { it.taskId }
        val samples = if (active.isEmpty()) {
            listOf(sampleFor(reading, sampledAt, null, 0L))
        } else {
            val attributed = reading.totalBytes / active.size.coerceAtLeast(1)
            active.map { workspace -> sampleFor(reading, sampledAt, workspace, attributed) }
        }
        samples.forEach(store::append)
        history += samples
        val cutoff = sampledAt - retentionMillis
        history = history
            .filter { it.sampledAtMillis >= cutoff }
            .sortedWith(compareBy<AgentMemoryPssSample> { it.sampledAtMillis }.thenBy { it.id })
            .takeLast(maxSamples)
            .toMutableList()
        capturesSincePrune += 1
        if (capturesSincePrune >= PRUNE_EVERY_CAPTURES) {
            store.prune(cutoff, maxSamples)
            capturesSincePrune = 0
        }
        return AgentMemoryPssAggregation.snapshot(history).also { cachedSnapshot = it }
    }

    fun snapshot(): AgentMemoryPssSnapshot = cachedSnapshot

    private fun sampleFor(
        reading: AgentMemoryPssReading,
        sampledAt: Long,
        workspace: AgentWorkspace?,
        attributedBytes: Long
    ): AgentMemoryPssSample {
        val agentId = workspace?.agentId.orEmpty().ifBlank {
            if (workspace == null) "" else "signalasi-mobile"
        }
        return AgentMemoryPssSample(
            id = UUID.randomUUID().toString(),
            sampledAtMillis = sampledAt,
            processTotalBytes = reading.totalBytes,
            attributedBytes = attributedBytes.coerceAtLeast(0L),
            nativeBytes = reading.nativeBytes,
            dalvikBytes = reading.dalvikBytes,
            otherBytes = reading.otherBytes,
            measurementKind = reading.measurementKind.wireName,
            attributionMode = if (workspace == null) {
                AgentMemoryAttributionMode.PROCESS_TOTAL.wireName
            } else {
                AgentMemoryAttributionMode.SHARED_WEIGHTED.wireName
            },
            agentId = agentId,
            sessionId = workspace?.sessionId.orEmpty(),
            conversationId = workspace?.conversationId.orEmpty(),
            providerId = providerIdForAgent(agentId),
            taskId = workspace?.taskId.orEmpty()
        )
    }

    companion object {
        const val DEFAULT_RETENTION_MILLIS = 24L * 60L * 60L * 1_000L
        const val DEFAULT_MAX_SAMPLES = 4_096
        private const val STARTUP_HYDRATION_SAMPLE_LIMIT = 256
        private const val PRUNE_EVERY_CAPTURES = 24

        fun providerIdForAgent(agentId: String): String {
            val clean = agentId.trim().lowercase(Locale.ROOT)
            if (clean.isBlank()) return ""
            val explicit = listOf("provider:", "model:", "cloud:", "local-model:")
                .firstOrNull(clean::startsWith)
            if (explicit != null) return clean.removePrefix(explicit).substringBefore(':')
            return when (clean) {
                "signalasi-mobile", "mobile", "on-device" -> "on-device"
                else -> clean.substringBefore(':')
            }
        }
    }
}

object AgentMemoryPssRuntime {
    private val executor = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "SignalASI-Agent-Memory-PSS").apply { isDaemon = true }
    }
    @Volatile private var monitor: AgentMemoryPssMonitor? = null
    @Volatile private var workspaces: (() -> List<AgentWorkspace>)? = null
    @Volatile private var scheduled = false
    @Volatile private var initializing = false
    private val captureQueued = java.util.concurrent.atomic.AtomicBoolean(false)
    private val pendingWorkspaces = java.util.concurrent.ConcurrentLinkedQueue<AgentWorkspace>()

    @Synchronized
    fun start(context: Context, activeWorkspaces: () -> List<AgentWorkspace>) {
        workspaces = activeWorkspaces
        if (monitor != null) {
            scheduleCaptureLoop()
            return
        }
        if (initializing) return
        initializing = true
        val applicationContext = context.applicationContext
        executor.schedule({
            val startedAt = android.os.SystemClock.elapsedRealtime()
            AgentSessionMemoryBudgetRuntime.start(applicationContext)
            val initialized = runCatching {
                AgentMemoryPssMonitor(
                    sampler = AndroidAgentMemoryPssSampler(),
                    store = EncryptedAgentMemoryPssSampleStore(applicationContext)
                )
            }
            synchronized(this) {
                initialized.onSuccess { monitor = it }
                initializing = false
            }
            initialized
                .onSuccess {
                    android.util.Log.i(
                        "SignalASIStartup",
                        "agent_memory_pss_ready total=${android.os.SystemClock.elapsedRealtime() - startedAt}ms"
                    )
                    scheduleCaptureLoop()
                }
                .onFailure { error ->
                    android.util.Log.w("SignalASIStartup", "agent_memory_pss_init_failed", error)
                }
        }, STARTUP_INITIALIZATION_DELAY_SECONDS, TimeUnit.SECONDS)
    }

    @Synchronized
    private fun scheduleCaptureLoop() {
        if (scheduled || monitor == null) return
        scheduled = true
        executor.scheduleWithFixedDelay(
            { captureSafely() },
            0L,
            SAMPLE_INTERVAL_SECONDS,
            TimeUnit.SECONDS
        )
    }

    fun requestCapture(workspace: AgentWorkspace? = null) {
        workspace?.let(pendingWorkspaces::add)
        if (!captureQueued.compareAndSet(false, true)) return
        executor.execute {
            try {
                captureSafely()
            } finally {
                captureQueued.set(false)
                if (pendingWorkspaces.isNotEmpty()) requestCapture()
            }
        }
    }

    fun snapshot(): AgentMemoryPssSnapshot {
        requestCapture()
        return (monitor?.snapshot() ?: AgentMemoryPssSnapshot()).copy(
            sessionBudget = AgentSessionMemoryBudgetRuntime.snapshot()
        )
    }

    private fun captureSafely() {
        val currentMonitor = monitor ?: return
        val observed = buildList {
            while (true) {
                val workspace = pendingWorkspaces.poll() ?: break
                add(workspace)
            }
        }
        val active = runCatching { workspaces?.invoke().orEmpty() }.getOrDefault(emptyList())
        val combined = (active + observed)
            .groupBy(AgentWorkspace::taskId)
            .map { (_, candidates) ->
                candidates.maxWithOrNull(
                    compareBy<AgentWorkspace> { it.revision }.thenBy { it.updatedAtMillis }
                ) ?: candidates.last()
            }
        runCatching { currentMonitor.capture(combined) }
    }

    private const val STARTUP_INITIALIZATION_DELAY_SECONDS = 5L
    private const val SAMPLE_INTERVAL_SECONDS = 5L
}
