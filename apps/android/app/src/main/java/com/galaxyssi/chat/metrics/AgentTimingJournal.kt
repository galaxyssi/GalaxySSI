package com.galaxyssi.chat.metrics

import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

internal class AgentTimingJournal(
    private val file: File,
    queueLimit: Int = 1024,
    private val byteLimit: Long = 2 * 1024 * 1024,
    private val batchWriter: ((List<AgentTimingPoint>) -> Unit)? = null
) : AgentTimingSink, AutoCloseable {
    private val points = ArrayDeque<AgentTimingPoint>()
    private val pending = ArrayBlockingQueue<AgentTimingPoint>(queueLimit.coerceAtLeast(1))
    private val dropped = AtomicLong()
    private val failures = AtomicLong()
    private val invalid = AtomicLong()
    @Volatile private var closed = false
    @Volatile private var loading = true
    private val worker = Thread(::runWriter, "agent-latency-writer").apply { isDaemon = true; start() }

    override fun append(point: AgentTimingPoint) {
        if (closed || !AgentLatencyContract.valid(point)) return
        synchronized(points) {
            points.addLast(point)
            while (points.size > AgentLatencyContract.EVENT_LIMIT) points.removeFirst()
        }
        if (!pending.offer(point)) {
            pending.poll()
            dropped.incrementAndGet()
            if (!pending.offer(point)) dropped.incrementAndGet()
        }
    }

    override fun snapshot(): List<AgentTimingPoint> = synchronized(points) { points.toList() }

    fun health(): Map<String, Any> = mapOf(
        "loading" to loading, "dropped_events" to dropped.get(), "write_failures" to failures.get(),
        "invalid_events" to invalid.get(), "event_limit" to AgentLatencyContract.EVENT_LIMIT,
        "retention" to "bounded_recent_events"
    )

    override fun close() { closed = true; worker.join(5_000) }

    private fun runWriter() {
        val previous = File(file.parentFile, file.nameWithoutExtension + ".previous.jsonl")
        val loaded = ArrayDeque<AgentTimingPoint>()
        for (source in listOf(previous, file)) {
            try {
                if (!source.isFile) continue
                source.bufferedReader().use { reader ->
                    // Bound each record even after an interrupted or corrupt write.
                    val line = StringBuilder()
                    var oversized = false
                    while (true) {
                        val value = reader.read()
                        if (value < 0) break
                        if (value == '\n'.code) {
                            val point = if (oversized) null else decode(line.toString())
                            if (point != null) {
                                loaded.addLast(point)
                                while (loaded.size > AgentLatencyContract.EVENT_LIMIT) loaded.removeFirst()
                            } else invalid.incrementAndGet()
                            line.setLength(0)
                            oversized = false
                        } else if (line.length < 2048) line.append(value.toChar()) else oversized = true
                    }
                    if (line.isNotEmpty() || oversized) invalid.incrementAndGet()
                }
            } catch (_: Exception) { failures.incrementAndGet() }
        }
        synchronized(points) {
            loaded.addAll(points)
            points.clear()
            while (loaded.size > AgentLatencyContract.EVENT_LIMIT) loaded.removeFirst()
            points.addAll(loaded)
        }
        loading = false
        while (!closed || pending.isNotEmpty()) {
            val first = pending.poll(250, TimeUnit.MILLISECONDS) ?: continue
            val batch = mutableListOf(first)
            pending.drainTo(batch, 63)
            try {
                if (batchWriter != null) { batchWriter.invoke(batch); continue }
                file.parentFile?.mkdirs()
                if (file.exists() && file.length() >= byteLimit) {
                    if (previous.exists() && !previous.delete()) error("Cannot rotate Agent timings")
                    check(file.renameTo(previous)) { "Cannot rotate Agent timings" }
                }
                FileOutputStream(file, true).bufferedWriter(Charsets.UTF_8).use { writer ->
                    batch.forEach { writer.write(encode(it).toString()); writer.newLine() }
                }
            } catch (_: Exception) { failures.incrementAndGet() }
        }
    }

    companion object {
        fun encode(point: AgentTimingPoint): JSONObject = JSONObject()
            .put("trace_id", point.traceId).put("clock_id", point.clockId).put("stage", point.stage)
            .put("monotonic_ns", point.monotonicNs).put("wall_clock_ms", point.wallClockMs)
            .put("operation_id", point.operationId).put("provider", point.provider).put("outcome", point.outcome)

        fun decode(line: String): AgentTimingPoint? = runCatching {
            val json = JSONObject(line)
            val monotonic = json.get("monotonic_ns")
            val wall = json.get("wall_clock_ms")
            require((monotonic is Long || monotonic is Int) && (wall is Long || wall is Int))
            AgentTimingPoint(
                json.getString("trace_id"), json.getString("clock_id"), json.getString("stage"),
                (monotonic as Number).toLong(), (wall as Number).toLong(),
                json.optString("operation_id"), json.optString("provider"), json.optString("outcome")
            ).takeIf(AgentLatencyContract::valid)
        }.getOrNull()
    }
}
