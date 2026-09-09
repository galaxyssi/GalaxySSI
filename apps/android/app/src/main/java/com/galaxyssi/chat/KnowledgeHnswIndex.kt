package com.galaxyssi.chat

import com.github.jelmerk.hnswlib.core.DistanceFunctions
import com.github.jelmerk.hnswlib.core.Item
import com.github.jelmerk.hnswlib.core.hnsw.HnswIndex
import java.io.Closeable

internal data class KnowledgeVectorMatch(val key: String, val revision: String, val start: Int,
    val end: Int, val similarity: Double)

/** Transient ANN graph. SQL remains authoritative; never serialize this plaintext graph. */
internal class KnowledgeHnswIndex(private val dimensions: Int, capacity: Int, budgetBytes: Long) : Closeable {
    private class Entry(val key: String, val revision: String, val ordinal: Int, val start: Int,
        val end: Int, val values: FloatArray) : Item<String, FloatArray> {
        override fun id() = "$key:$ordinal"
        override fun vector() = values
        override fun dimensions() = values.size
    }
    private val owned = ArrayList<Entry>()
    private var graph: HnswIndex<String, FloatArray, Entry, Float>?
    init {
        require(dimensions in 1..8192 && capacity >= 0 && budgetBytes > 0)
        // Admission estimate includes vector, graph edges, IDs and JVM objects, not a hard RSS guarantee.
        require(estimatedBytes(dimensions, capacity) <= budgetBytes) { "Semantic index exceeds memory budget" }
        graph = HnswIndex.newBuilder(dimensions, DistanceFunctions.FLOAT_COSINE_DISTANCE, capacity.coerceAtLeast(1))
            .withM(16).withEfConstruction(160).withEf(128).build<String, Entry>()
    }
    @Synchronized fun add(key: String, revision: String, row: KnowledgeStoredVector) {
        checkNotNull(graph) { "Semantic index is closed" }
        require(key.isNotBlank() && revision.isNotBlank() && row.ordinal >= 0 && row.start >= 0 && row.end > row.start)
        validate(row.values)
        val entry = Entry(key, revision, row.ordinal, row.start, row.end, row.values.copyOf())
        try {
            check(!graph!!.get(entry.id()).isPresent) { "Duplicate semantic vector" }
            check(graph!!.add(entry)) { "Semantic vector was not indexed" }
            owned.add(entry)
        } catch (error: Throwable) { entry.values.fill(0f); throw error }
    }
    @Synchronized fun search(query: FloatArray, limit: Int): List<KnowledgeVectorMatch> {
        val index = checkNotNull(graph) { "Semantic index is closed" }
        require(limit in 1..256)
        validate(query)
        return index.findNearest(query, limit).map {
            val row = it.item()
            KnowledgeVectorMatch(row.key, row.revision, row.start, row.end, (1.0 - it.distance()).coerceIn(-1.0, 1.0))
        }
    }
    @Synchronized fun size(): Int = owned.size
    @Synchronized override fun close() {
        owned.forEach { it.values.fill(0f) }
        owned.clear()
        graph = null
    }
    private fun validate(values: FloatArray) {
        require(values.size == dimensions && values.all(Float::isFinite))
        require(kotlin.math.abs(values.sumOf { it.toDouble() * it } - 1.0) < 0.001) { "Invalid normalized vector" }
    }
    companion object {
        fun estimatedBytes(dimensions: Int, count: Int): Long = 65536L + count.toLong() * (dimensions * 4L + 2048L)
    }
}
