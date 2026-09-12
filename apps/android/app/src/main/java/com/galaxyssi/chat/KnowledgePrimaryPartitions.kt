package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.system.Os
import android.system.OsConstants
import java.io.Closeable
import java.io.File
import java.util.UUID
import org.json.JSONObject

/** Durable immutable partitions. The caller may publish catalog references only after prepareCommit. */
internal class KnowledgePrimaryPartitions(context: Context, private val root: File, private val namespace: String,
    private val partitionBytes: Long = 64L * 1024 * 1024, private val partitionRecords: Long = 65_536) : Closeable {
    private val cipher = AgentRowStorageCipher(context, "knowledge-primary:v1:$namespace")
    private val writers = linkedMapOf<String, KnowledgeSqlite>()
    @Volatile private var writerThread: Thread? = null
    private var failed = false

    init { require(partitionBytes > 0 && partitionRecords > 0) }

    fun activeOnCurrentThread() = Thread.currentThread() === writerThread

    fun begin() { check(writerThread == null); writerThread = Thread.currentThread(); failed = false }

    fun append(catalog: KnowledgeSqlite, key: String, encoded: String) = guarded { appendFrames(catalog, key, encoded) }

    private fun appendFrames(catalog: KnowledgeSqlite, key: String, encoded: String) {
        checkWriter()
        require(key.matches(Regex("[a-f0-9]{64}")) && encoded.isNotEmpty())
        val bucket = key.take(2).toInt(16) and 3
        val partition = partition(catalog, bucket)
        val db = writer(partition)
        val entry = token()
        var offset = 0
        var ordinal = 0
        var bytes = 0L
        while (offset < encoded.length) {
            check(!Thread.currentThread().isInterrupted)
            var end = minOf(offset + KnowledgePrimaryFrameCodec.CHARS, encoded.length)
            if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
            val encrypted = cipher.encrypt(KnowledgePrimaryFrameCodec.compress(encoded.substring(offset, end)),
                aad(key, partition, entry, ordinal))
            db.insertOrThrow("frames", null, ContentValues().apply {
                put("entry_key", entry); put("ordinal", ordinal); put("ciphertext", encrypted)
            })
            bytes = Math.addExact(bytes, encrypted.length.toLong())
            ordinal = Math.addExact(ordinal, 1); offset = end
        }
        val reference = JSONObject().put("codec", 1).put("partition", partition).put("entry", entry)
            .put("chunks", ordinal).put("chars", encoded.length).toString()
        catalog.insertOrThrow("knowledge_primary_refs", null, ContentValues().apply {
            put("item_key", key); put("partition_key", partition)
            put("reference", cipher.encrypt(reference, referenceAad(key)))
        })
        catalog.rawQuery("UPDATE knowledge_primary_partitions SET bytes=bytes+?,records=records+1 WHERE partition_key=?",
            arrayOf(bytes.toString(), partition)).use { it.moveToNext() }
    }

    fun read(catalog: KnowledgeSqlite, key: String): String? {
        val record = catalog.rawQuery("SELECT partition_key,substr(reference,1,2049) FROM knowledge_primary_refs WHERE item_key=?", arrayOf(key)).use {
            if (!it.moveToFirst()) return null
            it.getString(0) to it.getString(1)
        }
        require(record.second.length <= 2048) { "Primary reference is oversized" }
        val reference = JSONObject(requireNotNull(cipher.decrypt(record.second, referenceAad(key))))
        check(reference.getInt("codec") == 1 && reference.getString("partition") == record.first)
        val partition = reference.getString("partition")
        val entry = reference.getString("entry")
        require(validToken(entry))
        val chunks = reference.getInt("chunks")
        val chars = reference.getInt("chars")
        require(chunks > 0 && chars > 0 && chunks.toLong() <= chars.toLong())
        val pending = if (Thread.currentThread() === writerThread) writers[partition] else null
        if (pending == null) readerSlots.acquire()
        val db = try { pending ?: openExisting(partition, readOnly = true) }
        catch (failure: Throwable) { if (pending == null) readerSlots.release(); throw failure }
        return try {
            val result = StringBuilder(minOf(chars, KnowledgePrimaryFrameCodec.CHARS))
            db.rawQuery("SELECT ordinal,substr(ciphertext,1,262145) FROM frames WHERE entry_key=? ORDER BY ordinal", arrayOf(entry)).use { cursor ->
                var next = 0
                while (cursor.moveToNext()) {
                    check(!Thread.currentThread().isInterrupted)
                    check(next < chunks && cursor.getInt(0) == next) { "Primary frames are not contiguous" }
                    val sealed = cursor.getString(1)
                    require(sealed.length <= 262144) { "Primary ciphertext frame is oversized" }
                    val value = requireNotNull(cipher.decrypt(sealed, aad(key, partition, entry, next)))
                    val plain = KnowledgePrimaryFrameCodec.decompress(value)
                    require(result.length.toLong() + plain.length <= chars.toLong())
                    result.append(plain); next++
                }
                check(next == chunks && result.length == chars) { "Primary frames are missing" }
            }
            result.toString()
        } finally { if (pending == null) try { db.close() } finally { readerSlots.release() } }
    }

    /** A partial partition commit is harmless until the separate catalog transaction commits. */
    fun prepareCommit() = guarded { writers.keys.toList().forEach(::flush) }

    fun end() {
        checkWriter()
        var failure: Throwable? = null
        try { writers.values.forEach { db ->
            try { try { db.endTransaction() } finally { db.close() } }
            catch (error: Throwable) { if (failure == null) failure = error else failure!!.addSuppressed(error) }
        } }
        finally { writers.clear(); writerThread = null }
        failure?.let { throw it }
    }

    private fun partition(catalog: KnowledgeSqlite, bucket: Int): String {
        val active = catalog.rawQuery("SELECT partition_key,bytes,records FROM knowledge_primary_partitions WHERE bucket=? AND sealed=0",
            arrayOf(bucket.toString())).use { cursor ->
            if (cursor.moveToFirst()) Triple(cursor.getString(0), cursor.getLong(1), cursor.getLong(2)) else null
        }
        if (active != null) {
            val file = path(active.first)
            check(file.isFile) { "Active primary partition is missing" }
            val physical = Math.addExact(file.length(), File(file.absolutePath + "-wal").length())
            if (active.second < partitionBytes && physical < partitionBytes && active.third < partitionRecords) return active.first
        }
        if (active != null) {
            flush(active.first)
            catalog.rawQuery("UPDATE knowledge_primary_partitions SET sealed=1 WHERE partition_key=?", arrayOf(active.first)).use { it.moveToNext() }
        }
        val id = token()
        create(id)
        catalog.insertOrThrow("knowledge_primary_partitions", null, ContentValues().apply {
            put("partition_key", id); put("bucket", bucket); put("bytes", 0L); put("records", 0L); put("sealed", 0)
        })
        return id
    }

    private fun writer(id: String): KnowledgeSqlite = writers[id] ?: run {
        // Rotation can open more than four files in one large source transaction; flush sealed predecessors.
        if (writers.size >= 4) flush(writers.keys.first())
        val db = openExisting(id, readOnly = false)
        try { db.beginTransaction(); writers[id] = db; db } catch (failure: Throwable) { db.close(); throw failure }
    }

    private fun flush(id: String) {
        val db = writers.remove(id) ?: return
        try { db.setTransactionSuccessful(); db.endTransaction() } finally { db.close() }
    }

    private fun create(id: String) {
        if (!root.isDirectory) { check(root.mkdirs()); sync(requireNotNull(root.parentFile)) }
        val path = path(id)
        check(!path.exists())
        KnowledgeSqlite(path.absolutePath).use { db ->
            // Immutable body files do not need WAL snapshots; the catalog owns logical snapshots.
            db.execSQL("PRAGMA journal_mode=DELETE"); db.execSQL("PRAGMA synchronous=FULL")
            db.execSQL("CREATE TABLE frames(entry_key TEXT NOT NULL,ordinal INTEGER NOT NULL,ciphertext TEXT NOT NULL," +
                "PRIMARY KEY(entry_key,ordinal)) WITHOUT ROWID")
            db.execSQL("PRAGMA user_version=1")
        }
        sync(root)
    }

    private fun openExisting(id: String, readOnly: Boolean): KnowledgeSqlite {
        val file = path(id)
        check(file.isFile) { "Primary partition is missing" }
        val db = KnowledgeSqlite(file.absolutePath)
        try {
            db.execSQL("PRAGMA busy_timeout=5000")
            db.execSQL("PRAGMA cache_size=-2048"); db.execSQL("PRAGMA mmap_size=0")
            db.execSQL(if (readOnly) "PRAGMA query_only=ON" else "PRAGMA synchronous=FULL")
            db.rawQuery("PRAGMA user_version", null).use { check(it.moveToFirst() && it.getInt(0) == 1) }
            return db
        } catch (failure: Throwable) { db.close(); throw failure }
    }

    private fun path(id: String): File { require(validToken(id)); return File(root, "$id.sqlite") }
    internal fun removeRetired(id: String): Long {
        check(writerThread == null)
        val file = path(id)
        var bytes = 0L
        for (suffix in listOf("", "-wal", "-shm", "-journal")) {
            val part = File(file.absolutePath + suffix)
            if (part.exists()) {
                bytes = Math.addExact(bytes, part.length())
                check(part.delete()) { "Retired primary partition could not be removed" }
            }
        }
        if (root.isDirectory) sync(root)
        return bytes
    }
    private fun checkWriter() = check(Thread.currentThread() === writerThread) { "Primary writer ownership mismatch" }
    private fun <T> guarded(block: () -> T): T {
        checkWriter(); check(!failed) { "Primary publication must roll back after a failed write" }
        return try { block() } catch (failure: Throwable) { failed = true; throw failure }
    }
    private fun aad(key: String, partition: String, entry: String, ordinal: Int) =
        "$namespace:primary-frame:v1:$key:$partition:$entry:$ordinal".toByteArray(Charsets.UTF_8)
    private fun referenceAad(key: String) = "$namespace:primary-reference:v1:$key".toByteArray(Charsets.UTF_8)
    private fun token() = UUID.randomUUID().toString().replace("-", "")
    private fun validToken(value: String) = value.matches(Regex("[a-f0-9]{32}"))
    private fun sync(directory: File) {
        val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }
    override fun close() { if (writerThread != null) end() }
    companion object { private val readerSlots = java.util.concurrent.Semaphore(8, true) }
}
