package com.galaxyssi.chat

import android.content.Context
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONObject

data class AgentSessionMemoryBaseline(
    val processBytes: Long,
    val capturedAtMillis: Long
)

data class AgentSessionMemoryBudgetSample(
    val id: String,
    val conversationId: String,
    val sampledAtMillis: Long,
    val beforeBytes: Long,
    val afterBytes: Long,
    val incrementalBytes: Long,
    val targetBytes: Long
) {
    val withinBudget: Boolean
        get() = incrementalBytes <= targetBytes
}

data class AgentSessionMemoryBudgetSnapshot(
    val targetBytes: Long = AgentSessionMemoryBudgetMonitor.DEFAULT_TARGET_BYTES,
    val latestIncrementalBytes: Long = 0L,
    val peakIncrementalBytes: Long = 0L,
    val averageIncrementalBytes: Long = 0L,
    val sampleCount: Int = 0,
    val exceededCount: Int = 0,
    val latestConversationId: String = "",
    val latestSampledAtMillis: Long = 0L
) {
    val withinBudget: Boolean
        get() = latestIncrementalBytes <= targetBytes
}

interface AgentSessionMemoryBudgetStore {
    fun append(sample: AgentSessionMemoryBudgetSample)
    fun recent(limit: Int, sinceMillis: Long): List<AgentSessionMemoryBudgetSample>
    fun prune(beforeMillis: Long, maxSamples: Int)
}

class InMemoryAgentSessionMemoryBudgetStore : AgentSessionMemoryBudgetStore {
    private val samples = mutableListOf<AgentSessionMemoryBudgetSample>()

    @Synchronized
    override fun append(sample: AgentSessionMemoryBudgetSample) {
        samples += sample
    }

    @Synchronized
    override fun recent(
        limit: Int,
        sinceMillis: Long
    ): List<AgentSessionMemoryBudgetSample> = samples.asSequence()
        .filter { it.sampledAtMillis >= sinceMillis }
        .sortedWith(compareBy<AgentSessionMemoryBudgetSample> { it.sampledAtMillis }.thenBy { it.id })
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

class EncryptedAgentSessionMemoryBudgetStore(context: Context) :
    AgentSessionMemoryBudgetStore {
    private val database = AgentEncryptedDatabase(
        context.applicationContext,
        "galaxyssi_agent_session_memory_budget"
    )

    @Synchronized
    override fun append(sample: AgentSessionMemoryBudgetSample) {
        database.writeString(keyFor(sample), encode(sample).toString())
    }

    @Synchronized
    override fun recent(
        limit: Int,
        sinceMillis: Long
    ): List<AgentSessionMemoryBudgetSample> = database.entries(SAMPLE_PREFIX)
        .asSequence()
        .mapNotNull { (_, value) -> decode(value) }
        .filter { it.sampledAtMillis >= sinceMillis }
        .sortedWith(compareBy<AgentSessionMemoryBudgetSample> { it.sampledAtMillis }.thenBy { it.id })
        .toList()
        .takeLast(limit.coerceAtLeast(1))

    @Synchronized
    override fun prune(beforeMillis: Long, maxSamples: Int) {
        val entries = database.keys(SAMPLE_PREFIX)
            .map { key ->
                key to (
                    key.removePrefix(SAMPLE_PREFIX)
                        .substringBefore(':')
                        .toLongOrNull()
                        ?: Long.MIN_VALUE
                    )
            }
            .sortedWith(compareBy<Pair<String, Long>> { it.second }.thenBy { it.first })
        val retained = entries.filter { it.second >= beforeMillis }
        val overflow = (retained.size - maxSamples.coerceAtLeast(1)).coerceAtLeast(0)
        database.removeAll(buildList {
            entries.filter { it.second < beforeMillis }.forEach { add(it.first) }
            retained.take(overflow).forEach { add(it.first) }
        })
    }

    private fun keyFor(sample: AgentSessionMemoryBudgetSample): String =
        "$SAMPLE_PREFIX${sample.sampledAtMillis.toString().padStart(13, '0')}:${sample.id}"

    private fun encode(sample: AgentSessionMemoryBudgetSample): JSONObject = JSONObject()
        .put("id", sample.id)
        .put("conversation_id", sample.conversationId)
        .put("sampled_at_millis", sample.sampledAtMillis)
        .put("before_bytes", sample.beforeBytes)
        .put("after_bytes", sample.afterBytes)
        .put("incremental_bytes", sample.incrementalBytes)
        .put("target_bytes", sample.targetBytes)

    private fun decode(value: String): AgentSessionMemoryBudgetSample? = runCatching {
        val source = JSONObject(value)
        AgentSessionMemoryBudgetSample(
            id = source.getString("id"),
            conversationId = source.optString("conversation_id"),
            sampledAtMillis = source.getLong("sampled_at_millis"),
            beforeBytes = source.optLong("before_bytes").coerceAtLeast(0L),
            afterBytes = source.optLong("after_bytes").coerceAtLeast(0L),
            incrementalBytes = source.optLong("incremental_bytes").coerceAtLeast(0L),
            targetBytes = source.optLong(
                "target_bytes",
                AgentSessionMemoryBudgetMonitor.DEFAULT_TARGET_BYTES
            ).coerceAtLeast(1L)
        )
    }.getOrNull()

    private companion object {
        const val SAMPLE_PREFIX = "sample:"
    }
}

class AgentSessionMemoryBudgetMonitor(
    private val sampler: AgentMemoryPssSampler,
    private val store: AgentSessionMemoryBudgetStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val targetBytes: Long = DEFAULT_TARGET_BYTES,
    private val retentionMillis: Long = DEFAULT_RETENTION_MILLIS,
    private val maxSamples: Int = DEFAULT_MAX_SAMPLES
) {
    private var history = store.recent(maxSamples, clock() - retentionMillis).toMutableList()
    @Volatile private var cachedSnapshot = aggregate(history, targetBytes)

    fun begin(): AgentSessionMemoryBaseline {
        val reading = sampler.sample()
        return AgentSessionMemoryBaseline(
            processBytes = reading.totalBytes.coerceAtLeast(0L),
            capturedAtMillis = clock()
        )
    }

    @Synchronized
    fun complete(
        conversationId: String,
        baseline: AgentSessionMemoryBaseline
    ): AgentSessionMemoryBudgetSnapshot {
        val after = sampler.sample().totalBytes.coerceAtLeast(0L)
        val sampledAt = clock()
        val sample = AgentSessionMemoryBudgetSample(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId.trim(),
            sampledAtMillis = sampledAt,
            beforeBytes = baseline.processBytes.coerceAtLeast(0L),
            afterBytes = after,
            incrementalBytes = (after - baseline.processBytes).coerceAtLeast(0L),
            targetBytes = targetBytes
        )
        store.append(sample)
        history += sample
        val cutoff = sampledAt - retentionMillis
        history = history.asSequence()
            .filter { it.sampledAtMillis >= cutoff }
            .sortedWith(compareBy<AgentSessionMemoryBudgetSample> { it.sampledAtMillis }.thenBy { it.id })
            .toList()
            .takeLast(maxSamples)
            .toMutableList()
        store.prune(cutoff, maxSamples)
        return aggregate(history, targetBytes).also { cachedSnapshot = it }
    }

    fun snapshot(): AgentSessionMemoryBudgetSnapshot = cachedSnapshot

    companion object {
        const val DEFAULT_TARGET_BYTES = 20L * 1024L * 1024L
        const val DEFAULT_RETENTION_MILLIS = 30L * 24L * 60L * 60L * 1_000L
        const val DEFAULT_MAX_SAMPLES = 512

        fun aggregate(
            samples: List<AgentSessionMemoryBudgetSample>,
            targetBytes: Long = DEFAULT_TARGET_BYTES
        ): AgentSessionMemoryBudgetSnapshot {
            if (samples.isEmpty()) {
                return AgentSessionMemoryBudgetSnapshot(targetBytes = targetBytes)
            }
            val ordered = samples.sortedWith(
                compareBy<AgentSessionMemoryBudgetSample> { it.sampledAtMillis }.thenBy { it.id }
            )
            val latest = ordered.last()
            return AgentSessionMemoryBudgetSnapshot(
                targetBytes = targetBytes,
                latestIncrementalBytes = latest.incrementalBytes,
                peakIncrementalBytes = ordered.maxOf(AgentSessionMemoryBudgetSample::incrementalBytes),
                averageIncrementalBytes = ordered.sumOf(AgentSessionMemoryBudgetSample::incrementalBytes) /
                    ordered.size.coerceAtLeast(1),
                sampleCount = ordered.size,
                exceededCount = ordered.count { it.incrementalBytes > targetBytes },
                latestConversationId = latest.conversationId,
                latestSampledAtMillis = latest.sampledAtMillis
            )
        }
    }
}

object AgentSessionMemoryBudgetRuntime {
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "GalaxySSI-Session-Memory-Budget").apply { isDaemon = true }
    }
    @Volatile private var monitor: AgentSessionMemoryBudgetMonitor? = null
    @Volatile private var initializing = false

    @Synchronized
    fun start(context: Context) {
        if (monitor != null || initializing) return
        initializing = true
        val applicationContext = context.applicationContext
        executor.execute {
            val startedAt = android.os.SystemClock.elapsedRealtime()
            val initialized = runCatching {
                AgentSessionMemoryBudgetMonitor(
                    sampler = AndroidAgentMemoryPssSampler(),
                    store = EncryptedAgentSessionMemoryBudgetStore(applicationContext)
                )
            }
            synchronized(this) {
                initialized.onSuccess { monitor = it }
                initializing = false
            }
            initialized
                .onSuccess {
                    android.util.Log.i(
                        "GalaxySSIStartup",
                        "session_memory_budget_ready total=${android.os.SystemClock.elapsedRealtime() - startedAt}ms"
                    )
                }
                .onFailure { error ->
                    android.util.Log.w("GalaxySSIStartup", "session_memory_budget_init_failed", error)
                }
        }
    }

    fun begin(): AgentSessionMemoryBaseline? = monitor?.let {
        runCatching(it::begin).getOrNull()
    }

    fun complete(conversationId: String, baseline: AgentSessionMemoryBaseline?) {
        val activeMonitor = monitor ?: return
        val activeBaseline = baseline ?: return
        executor.execute {
            runCatching { activeMonitor.complete(conversationId, activeBaseline) }
        }
    }

    fun snapshot(): AgentSessionMemoryBudgetSnapshot =
        monitor?.snapshot() ?: AgentSessionMemoryBudgetSnapshot()
}
