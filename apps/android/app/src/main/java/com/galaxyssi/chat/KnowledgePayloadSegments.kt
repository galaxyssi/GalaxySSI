package com.galaxyssi.chat

import android.content.ContentValues
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.charset.CodingErrorAction

/** Compressed, authenticated payload files; source SQLite publishes only bounded references. */
internal class KnowledgePayloadSegments(root: File, private val namespace: String) {
    val leases = KnowledgeSegmentLeases(File(root.absolutePath + ".lock"))
    internal val catalog = AgentMemorySegmentCatalog(File(root.absolutePath + ".catalog.db"))
    internal val files = MemorySegmentFile(root, AgentStorageCipher::encryptBinary, AgentStorageCipher::decryptBinary,
        syncDirectory = ::sync, register = { catalog.register(it); sync(requireNotNull(root.parentFile)) })

    fun append(db: KnowledgeSqlite, key: String, encoded: String) {
        val reference = files.append(aad(key)) { output ->
            val records = BackupRecordStream.Writer(output)
            records.record("knowledge-payload", key) { payload ->
                val encoder = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                OutputStreamWriter(payload, encoder).use { it.write(encoded) }
            }
            records.finish()
        }
        db.insertOrThrow("knowledge_payloads", null, encodeReference(key, reference))
    }

    internal fun encodeReference(key: String, reference: MemorySegmentFile.Reference): ContentValues {
        val plain = reference.bytes()
        val cipher = try { AgentStorageCipher.encryptBinary(plain, referenceAad(key)) } finally { plain.fill(0) }
        return try {
            ContentValues().apply {
                put("item_key", key); put("segment", reference.segment.toString()); put("bytes", reference.length)
                put("reference", Base64.encodeToString(cipher, Base64.NO_WRAP))
            }
        } finally { cipher.fill(0) }
    }

    internal fun decodeReference(key: String, value: String): MemorySegmentFile.Reference {
        require(value.length <= 256) { "Invalid knowledge payload reference size" }
        val cipher = Base64.decode(value, Base64.NO_WRAP)
        val plain = try { AgentStorageCipher.decryptBinary(cipher, referenceAad(key)) } finally { cipher.fill(0) }
        return try { MemorySegmentFile.Reference.parse(plain) } finally { plain.fill(0) }
    }

    fun read(db: KnowledgeSqlite, key: String): String? = leases.access {
        val reference = db.rawQuery("SELECT reference,segment,bytes FROM knowledge_payloads WHERE item_key=?", arrayOf(key)).use { c ->
            if (!c.moveToFirst()) return@access null
            val parsed = decodeReference(key, c.getString(0))
            parsed.also { check(it.segment.toString() == c.getString(1) && it.length == c.getLong(2)) { "Knowledge payload membership mismatch" } }
        }
        files.readPinned(reference, aad(key)) { input ->
            var result: String? = null
            val count = BackupRecordStream.read(input) { section, recordKey, payload ->
                check(section == "knowledge-payload" && recordKey == key && result == null) { "Knowledge payload identity mismatch" }
                val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                result = InputStreamReader(payload, decoder).use { it.readText() }
            }
            check(count == 1L) { "Knowledge payload record count mismatch" }
            checkNotNull(result)
        }
    }

    /** Exclusive lease and SQLite writer reservation are held before checking references. */
    data class Reclaimed(val bytes: Long, val complete: Boolean)
    fun reclaim(db: KnowledgeSqlite, limit: Int = 2, checkActive: () -> Unit = {}): Reclaimed =
        KnowledgePayloadCompaction(this).run(db, limit, checkActive)

    internal fun seal() = files.seal()
    internal fun aad(key: String) = "$namespace:knowledge-payload:v1:$key".toByteArray(Charsets.UTF_8)
    internal fun copyAad(key: String) = "$namespace:knowledge-payload-copy:v1:$key".toByteArray(Charsets.UTF_8)
    private fun referenceAad(key: String) = "$namespace:knowledge-payload-reference:v1:$key".toByteArray(Charsets.UTF_8)

    companion object {
        const val INLINE_CHARS = 8192
        const val LARGE_STORE_ROWS = 16384L
        fun create(db: KnowledgeSqlite) {
            db.execSQL("CREATE TABLE knowledge_payloads(item_key TEXT PRIMARY KEY REFERENCES knowledge_items(item_key) ON DELETE CASCADE," +
                "reference TEXT NOT NULL,segment TEXT NOT NULL,bytes INTEGER NOT NULL CHECK(typeof(bytes)='integer' AND bytes>0))")
            db.execSQL("CREATE INDEX knowledge_payload_segment ON knowledge_payloads(segment,item_key)")
            db.execSQL("CREATE TABLE knowledge_payload_migration(id INTEGER PRIMARY KEY CHECK(id=1),after_item TEXT NOT NULL," +
                "all_rows INTEGER NOT NULL CHECK(all_rows IN (0,1)),complete INTEGER NOT NULL CHECK(complete IN (0,1)))")
            db.execSQL("INSERT INTO knowledge_payload_migration VALUES(1,'',0,0)")
        }
        private fun sync(directory: File) {
            val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
            try { check(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)); Os.fsync(fd) } finally { Os.close(fd) }
        }
    }
}
