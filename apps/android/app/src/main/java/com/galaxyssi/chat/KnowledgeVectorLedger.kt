package com.galaxyssi.chat

import android.content.ContentValues
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class KnowledgeVectorJob(
    val key: String, val revision: String, val item: AgentKnowledgeItem,
    val next: Int, val count: Int, val complete: Boolean
)
internal data class KnowledgeStoredVector(val ordinal: Int, val start: Int, val end: Int, val values: FloatArray) : Closeable {
    override fun close() { values.fill(0f) }
}
internal data class KnowledgeVectorPage(val revision: String, val total: Int, val rows: List<KnowledgeStoredVector>) : Closeable {
    override fun close() { rows.forEach { it.close() } }
}

/** Derived rows share the source transaction and cascade on every source replacement/deletion. */
internal class KnowledgeVectorLedger(
    private val storage: AgentKnowledgeDatabase, private val namespace: String, val spec: KnowledgeVectorSpec
) {
    internal val modelKey by lazy { storage.key("vector-model", spec.identity) }
    private data class Checkpoint(val key: String, val revision: String, val next: Int, val count: Int,
        val complete: Boolean, val length: Int)
    private fun KnowledgeVectorJob.checkpoint() = Checkpoint(key, revision, next, count, complete, item.content.length)

    fun nextJob(): KnowledgeVectorJob? = storage.transaction { db ->
        register(db)
        val key = db.rawQuery("SELECT item_key FROM knowledge_vector_queue WHERE model_key=? " +
            "ORDER BY item_key LIMIT 1", arrayOf(modelKey)).use { if (it.moveToFirst()) it.getString(0) else null }
            ?: return@transaction null
        val item = requireNotNull(storage.read(db, key))
        val revision = requireNotNull(revision(db, key))
        state(db, key, revision)?.let {
            check(it.length == item.content.length && !it.complete) { "Invalid queued vector checkpoint" }
            return@transaction KnowledgeVectorJob(key, revision, item, it.next, it.count, it.complete)
        }
        val job = KnowledgeVectorJob(key, revision, item, 0, 0, false)
        db.insertOrThrow("knowledge_vector_docs", null, marker(job).apply { put("item_key", key); put("model_key", modelKey) })
        job
    }

    fun append(job: KnowledgeVectorJob, chunk: KnowledgeEmbeddingChunk, vector: FloatArray): Boolean = storage.transaction { db ->
        if (!isCurrent(db, job)) return@transaction false
        require(chunk.start >= job.next && chunk.start < chunk.end && chunk.end <= job.item.content.length)
        require(chunk.next > job.next && chunk.next <= chunk.end)
        require(chunk.text == job.item.content.substring(chunk.start, chunk.end))
        require(vector.size == spec.dimensions)
        checkVector(vector)
        val bytes = ByteBuffer.allocate(8 + vector.size * 4).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(chunk.start).putInt(chunk.end).apply { vector.forEach { putFloat(it) } }.array()
        val encrypted = try { AgentStorageCipher.encryptBinary(bytes, aad(job.checkpoint(), "chunk", job.count.toString())) }
            finally { bytes.fill(0) }
        try {
            db.insertOrThrow("knowledge_vectors", null, ContentValues().apply {
                put("item_key", job.key); put("model_key", modelKey); put("ordinal", job.count); put("ciphertext", encrypted)
            })
            val next = job.copy(next = chunk.next, count = job.count + 1, complete = chunk.next == job.item.content.length)
            db.update("knowledge_vector_docs", marker(next), "item_key=? AND model_key=?", arrayOf(job.key, modelKey))
            if (next.complete) db.delete("knowledge_vector_queue", "item_key=? AND model_key=?", arrayOf(job.key, modelKey))
        } finally { encrypted.fill(0) }
        true
    }

    fun finishWhitespace(job: KnowledgeVectorJob): Boolean = storage.transaction { db ->
        if (!isCurrent(db, job)) return@transaction false
        check(job.item.content.substring(job.next).isBlank()) { "Cannot finish before all content is indexed" }
        db.update("knowledge_vector_docs", marker(job.copy(next = job.item.content.length, complete = true)),
            "item_key=? AND model_key=?", arrayOf(job.key, modelKey))
        db.delete("knowledge_vector_queue", "item_key=? AND model_key=?", arrayOf(job.key, modelKey))
        true
    }

    fun unregister() = storage.transaction { it.delete("knowledge_vector_models", "model_key=?", arrayOf(modelKey)) }

    private fun register(db: KnowledgeSqlite) {
        val present = db.rawQuery("SELECT 1 FROM knowledge_vector_models WHERE model_key=?", arrayOf(modelKey)).use { it.moveToFirst() }
        if (present) return
        db.insertOrThrow("knowledge_vector_models", null, ContentValues().apply { put("model_key", modelKey) })
        db.rawQuery("INSERT INTO knowledge_vector_queue(model_key,item_key) SELECT ?,item_key FROM knowledge_items",
            arrayOf(modelKey)).use { it.moveToNext() }
    }

    /** Only complete documents are visible, with bounded, authenticated vector pages. */
    fun page(itemId: String, fromOrdinal: Int = 0, limit: Int = 64): KnowledgeVectorPage? =
        pageByKey(storage.key("id", itemId), fromOrdinal, limit)

    internal fun pageByKey(key: String, fromOrdinal: Int = 0, limit: Int = 64): KnowledgeVectorPage? = storage.access { db ->
        require(fromOrdinal >= 0 && limit in 1..256)
        val revision = revision(db, key) ?: return@access null
        val job = state(db, key, revision)?.takeIf { it.complete } ?: return@access null
        val rows = mutableListOf<KnowledgeStoredVector>()
        try {
            db.rawQuery("SELECT ordinal,ciphertext,length(ciphertext) FROM knowledge_vectors WHERE item_key=? AND model_key=? " +
                "AND ordinal>=? ORDER BY ordinal LIMIT ?", arrayOf(key, modelKey, fromOrdinal.toString(), limit.toString())).use { cursor ->
                while (cursor.moveToNext()) {
                    val ordinal = cursor.checkedInt(0)
                    check(ordinal == fromOrdinal + rows.size && ordinal < job.count) { "Vector chunk order mismatch" }
                    check(cursor.getLong(2) == 37L + spec.dimensions * 4L) { "Invalid encrypted vector size" }
                    val encrypted = cursor.getBlob(1)
                    val bytes = try { AgentStorageCipher.decryptBinary(encrypted, aad(job, "chunk", ordinal.toString())) }
                        finally { encrypted.fill(0) }
                    try {
                        check(bytes.size == 8 + spec.dimensions * 4) { "Vector dimensions mismatch" }
                        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                        val start = buffer.int
                        val end = buffer.int
                        check(start in 0 until end && end <= job.length) { "Vector provenance mismatch" }
                        val vector = FloatArray(spec.dimensions) { buffer.float }
                        try { checkVector(vector) } catch (error: Throwable) { vector.fill(0f); throw error }
                        rows += KnowledgeStoredVector(ordinal, start, end, vector)
                    } finally { bytes.fill(0) }
                }
            }
            check(rows.size == minOf(limit, (job.count - fromOrdinal).coerceAtLeast(0))) { "Vector chunks are missing" }
            KnowledgeVectorPage(revision, job.count, rows)
        } catch (error: Throwable) { rows.forEach { it.close() }; throw error }
    }

    private fun isCurrent(db: KnowledgeSqlite, job: KnowledgeVectorJob): Boolean {
        if (job.complete || revision(db, job.key) != job.revision) return false
        val state = state(db, job.key, job.revision) ?: return false
        check(state.length == job.item.content.length)
        return state.next == job.next && state.count == job.count && !state.complete
    }

    private fun revision(db: KnowledgeSqlite, key: String): String? = db.rawQuery(
        "SELECT header FROM knowledge_items WHERE item_key=?", arrayOf(key)).use {
        if (it.moveToFirst()) AgentNativeJsonCodec.sha256(it.getString(0)) else null
    }

    private fun state(db: KnowledgeSqlite, key: String, revision: String): Checkpoint? =
        db.rawQuery("SELECT revision,dimensions,next_offset,chunk_count,complete,seal,content_length,length(seal) FROM knowledge_vector_docs " +
            "WHERE item_key=? AND model_key=?", arrayOf(key, modelKey)).use {
            if (!it.moveToFirst()) return null
            check(it.getString(0) == revision && it.checkedInt(1) == spec.dimensions) { "Stale vector document metadata" }
            val job = Checkpoint(key, revision, it.checkedInt(2), it.checkedInt(3), it.checkedInt(4) == 1, it.checkedInt(6))
            check(it.checkedInt(4) in 0..1 && job.next in 0..job.length)
            check(it.getLong(7) == 29L) { "Invalid vector checkpoint size" }
            val seal = it.getBlob(5)
            val clear = try { AgentStorageCipher.decryptBinary(seal, markerAad(job)) } finally { seal.fill(0) }
            try { check(clear.isEmpty()) { "Invalid vector checkpoint" } } finally { clear.fill(0) }
            job
        }

    private fun marker(job: KnowledgeVectorJob) = ContentValues().apply {
        put("revision", job.revision); put("dimensions", spec.dimensions)
        put("content_length", job.item.content.length)
        put("next_offset", job.next); put("chunk_count", job.count); put("complete", if (job.complete) 1 else 0)
        put("seal", AgentStorageCipher.encryptBinary(byteArrayOf(), markerAad(job.checkpoint())))
    }

    private fun aad(job: Checkpoint, kind: String, detail: String) = listOf(
        "knowledge-vector:v1", namespace, job.key, modelKey, job.revision, spec.dimensions.toString(), kind, detail
    ).joinToString("\u0000").toByteArray(Charsets.UTF_8)
    private fun markerAad(job: Checkpoint) = aad(job, "checkpoint", "${job.next}:${job.count}:${job.complete}:${job.length}")
    private fun KnowledgeCursor.checkedInt(index: Int): Int = getLong(index).also {
        check(it in 0..Int.MAX_VALUE.toLong()) { "Vector metadata integer overflow" }
    }.toInt()

    companion object {
        fun create(db: KnowledgeSqlite) {
            db.execSQL("CREATE TABLE knowledge_vector_models (model_key TEXT PRIMARY KEY)")
            db.execSQL("CREATE TABLE knowledge_vector_docs (item_key TEXT NOT NULL REFERENCES knowledge_items(item_key) " +
                "ON DELETE CASCADE,model_key TEXT NOT NULL REFERENCES knowledge_vector_models(model_key) ON DELETE CASCADE," +
                "revision TEXT NOT NULL,dimensions INTEGER NOT NULL," +
                "next_offset INTEGER NOT NULL,chunk_count INTEGER NOT NULL,complete INTEGER NOT NULL,seal BLOB NOT NULL," +
                "content_length INTEGER NOT NULL," +
                "PRIMARY KEY(item_key,model_key))")
            db.execSQL("CREATE INDEX knowledge_vector_pending ON knowledge_vector_docs(model_key,complete,item_key)")
            db.execSQL("CREATE TABLE knowledge_vectors (item_key TEXT NOT NULL,model_key TEXT NOT NULL," +
                "ordinal INTEGER NOT NULL,ciphertext BLOB NOT NULL,PRIMARY KEY(item_key,model_key,ordinal)," +
                "FOREIGN KEY(item_key,model_key) REFERENCES knowledge_vector_docs(item_key,model_key) ON DELETE CASCADE)")
            db.execSQL("CREATE TABLE knowledge_vector_queue (model_key TEXT NOT NULL REFERENCES knowledge_vector_models(model_key) " +
                "ON DELETE CASCADE,item_key TEXT NOT NULL REFERENCES knowledge_items(item_key) ON DELETE CASCADE," +
                "PRIMARY KEY(model_key,item_key))")
            db.execSQL("CREATE TRIGGER knowledge_vector_source_insert AFTER INSERT ON knowledge_items BEGIN " +
                "INSERT INTO knowledge_vector_queue(model_key,item_key) SELECT model_key,NEW.item_key FROM knowledge_vector_models; END")
        }
        private fun checkVector(vector: FloatArray) {
            val squared = vector.sumOf { it.toDouble() * it }
            require(vector.all { it.isFinite() } && kotlin.math.abs(squared - 1.0) < 0.001) { "Invalid normalized vector" }
        }
    }
}
