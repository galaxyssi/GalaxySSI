package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.util.UUID

/** An isolated encrypted restore workspace. Formal memory is untouched until the archive validates. */
internal class MemoryBackupStaging(context: Context) : Closeable {
    private val id = UUID.randomUUID().toString()
    private val indexKey = BackupStagingTokenKey()
    private val directory = File(context.cacheDir, "memory-backup-staging").apply { check(isDirectory || mkdirs()) }
    private val file = File(directory, "$id.db")
    private val sql = SQLiteDatabase.openOrCreateDatabase(file, null)
    private val cipher = AgentRowStorageCipher(context, "memory-backup-staging-v1:${context.filesDir.absolutePath}")
    private var begun = false
    private var ended = false
    private var verified = false
    private var prepared = false
    private var rows = 0L
    private var active = 0L
    private var deletions = 0L
    private var next = 0L

    init {
        try {
        sql.execSQL("PRAGMA cache_size=-2048")
        sql.execSQL("PRAGMA synchronous=FULL")
        sql.execSQL("CREATE TABLE records(seq INTEGER PRIMARY KEY,kind TEXT NOT NULL,token TEXT NOT NULL UNIQUE," +
            "position INTEGER,g TEXT NOT NULL,s TEXT NOT NULL,body TEXT NOT NULL)")
        sql.execSQL("CREATE UNIQUE INDEX memory_backup_positions ON records(position) WHERE kind='memory-row'")
        sql.execSQL("CREATE INDEX memory_backup_order ON records(kind,position,seq)")
        sql.execSQL("CREATE INDEX memory_backup_sequence ON records(kind,seq)")
        sql.execSQL("CREATE INDEX memory_backup_groups ON records(g,s)")
        sql.execSQL("CREATE TABLE suppression(token TEXT PRIMARY KEY,cutoff INTEGER NOT NULL)")
        sql.beginTransaction()
        } catch (failure: Throwable) {
            try { sql.close() } finally { indexKey.close(); SQLiteDatabase.deleteDatabase(file) }
            throw failure
        }
    }

    fun accept(section: String, key: String, input: InputStream) {
        check(!verified && !ended) { "Unexpected data after memory backup end" }
        val json = readBackupJson(input)
        when (section) {
            "memory" -> when (key) {
                "begin" -> { check(!begun && json.getInt("schema") == 1); begun = true }
                "end" -> {
                    check(begun && json.getLong("rows") == rows && json.getLong("active") == active && json.getLong("deletions") == deletions) {
                        "Memory backup section count mismatch"
                    }
                    ended = true
                }
                else -> error("Unknown memory backup section")
            }
            "memory-row" -> {
                check(begun) { "Missing memory backup beginning" }
                val itemJson = json.getJSONObject("item")
                val identity = AgentMemoryCausalDeletionPolicy.backupSuppressionKeys(itemJson)
                check(key == AgentPersonalMemoryRows.key(identity.id) && json.getLong("position") >= 0) { "Memory backup row identity mismatch" }
                val item = AgentMemoryItemCodec.decode(itemJson) ?: error("Invalid memory backup item")
                check(itemJson.getString("kind") == item.kind.name && itemJson.getString("scope") == item.scope.name &&
                    itemJson.getString("status") == item.status.name) { "Unsupported memory backup classification" }
                // Freeze codec defaults once; index maintenance must not generate a new timestamp on each read.
                json.put("item", AgentMemoryItemCodec.encode(item))
                val conflict = item.status == AgentMemoryStatus.CONFLICTED
                val group = if (conflict) token("group", item.conflictGroupId) else ""
                val scope = if (conflict) token("scope", listOf(item.kind.name, item.scope.name, item.scopeId, item.key)
                    .joinToString("") { "${it.length}:$it" }) else ""
                insert(section, key, json, json.getLong("position"), group, scope)
                rows = Math.addExact(rows, 1)
                if (item.status == AgentMemoryStatus.ACTIVE) active = Math.addExact(active, 1)
            }
            "memory-deletion" -> {
                check(begun) { "Missing memory backup beginning" }
                val deletion = AgentMemoryCausalDeletionPolicy.decode(json) ?: error("Invalid memory backup deletion")
                check(key == deletion.id) { "Memory backup deletion identity mismatch" }
                insert(section, key, json, null, "", "")
                addBarrier(deletion)
                deletions = Math.addExact(deletions, 1)
            }
            else -> error("Unknown memory backup record type")
        }
    }

    fun validateArchive() {
        check(begun && ended && !verified)
        sql.setTransactionSuccessful()
        sql.endTransaction()
        verified = true
    }

    fun addLocalDeletion(record: AgentMemoryDeletionTombstone) {
        check(verified && !prepared)
        if (!sql.inTransaction()) sql.beginTransaction()
        addBarrier(record)
    }

    fun prepare() {
        check(verified && !prepared)
        if (!sql.inTransaction()) sql.beginTransaction()
        try {
            visit("memory-row") { seq, raw ->
                val keys = AgentMemoryCausalDeletionPolicy.backupSuppressionKeys(raw.getJSONObject("item"))
                val tokens = arrayOf(token("deleted-id", keys.id), token("deleted-fingerprint", keys.exact), token("deleted-fingerprint", keys.legacy))
                val suppressed = sql.rawQuery("SELECT token,cutoff FROM suppression WHERE token IN (?,?,?)", tokens).use { c ->
                    var found = false
                    while (c.moveToNext()) if (c.getString(0) == tokens[0] || keys.timestamp <= c.getLong(1)) found = true
                    found
                }
                if (suppressed) sql.delete("records", "seq=?", arrayOf(seq.toString()))
            }
            sql.execSQL("CREATE TABLE scoped_groups(g TEXT,s TEXT,n INTEGER,PRIMARY KEY(g,s))")
            sql.execSQL("INSERT INTO scoped_groups SELECT g,s,count(*) FROM records WHERE g!='' GROUP BY g,s")
            sql.execSQL("CREATE TABLE original_groups(g TEXT PRIMARY KEY,n INTEGER)")
            sql.execSQL("INSERT INTO original_groups SELECT g,count(*) FROM scoped_groups GROUP BY g")
            sql.setTransactionSuccessful()
        } finally { sql.endTransaction() }
        prepared = true
    }

    fun items(): Sequence<JSONObject> = sequence {
        check(prepared)
        var position = -1L
        while (true) {
            val page = sql.rawQuery("SELECT seq,position,g,s FROM records WHERE kind='memory-row' AND position>? ORDER BY position LIMIT 128",
                arrayOf(position.toString())).use { c -> buildList { while (c.moveToNext()) add(arrayOf(c.getString(0), c.getString(1), c.getString(2), c.getString(3))) } }
            if (page.isEmpty()) break
            for (row in page) {
                val itemJson = read(row[0].toLong()).getJSONObject("item")
                if (row[2].isNotEmpty()) {
                    val item = AgentMemoryItemCodec.decode(itemJson) ?: error("Invalid staged memory item")
                    sql.rawQuery("SELECT s.n,o.n FROM scoped_groups s JOIN original_groups o ON o.g=s.g WHERE s.g=? AND s.s=?",
                        arrayOf(row[2], row[3])).use { c ->
                        check(c.moveToFirst())
                        if (c.getLong(0) == 1L) itemJson.put("status", "ACTIVE").put("conflict_group_id", "")
                        else if (c.getLong(1) > 1L || item.conflictGroupId.isBlank())
                            itemJson.put("conflict_group_id", AgentMemoryIdentity.normalizedConflictId(item.conflictGroupId, item))
                    }
                }
                yield(itemJson)
            }
            position = page.last()[1].toLong()
        }
    }

    fun additionalRows(): Sequence<Pair<String, String>> = sequence {
        check(prepared)
        var after = -1L
        while (true) {
            val ids = idsAfter("memory-deletion", after)
            if (ids.isEmpty()) break
            for (seq in ids) {
                val json = read(seq)
                val record = AgentMemoryCausalDeletionPolicy.decode(json) ?: error("Invalid staged memory deletion")
                yield(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + record.id to json.toString())
                yieldAll(AgentMemoryRetractionOutbox.references(record).asSequence().map { it.key to it.value })
            }
            after = ids.last()
        }
    }

    private fun insert(kind: String, key: String, json: JSONObject, position: Long?, group: String, scope: String) {
        val seq = next
        next = Math.addExact(next, 1)
        val encrypted = cipher.encrypt(json.toString(), aad(seq))
        sql.execSQL("INSERT INTO records VALUES(?,?,?,?,?,?,?)", arrayOf(seq, kind, token("record:$kind", key), position, group, scope, encrypted))
    }

    private fun addBarrier(record: AgentMemoryDeletionTombstone) {
        fun add(domain: String, key: String, cutoff: Long) {
            val indexed = token(domain, key)
            sql.execSQL("INSERT OR IGNORE INTO suppression VALUES(?,?)", arrayOf(indexed, cutoff))
            sql.execSQL("UPDATE suppression SET cutoff=max(cutoff,?) WHERE token=?", arrayOf(cutoff, indexed))
        }
        record.memoryIds.forEach { add("deleted-id", it, Long.MAX_VALUE) }
        record.semanticFingerprints.forEach { add("deleted-fingerprint", it, record.deletedAtMillis) }
    }

    private fun visit(kind: String, block: (Long, JSONObject) -> Unit) {
        var after = -1L
        while (true) {
            val ids = idsAfter(kind, after)
            if (ids.isEmpty()) break
            ids.forEach { block(it, read(it)) }
            after = ids.last()
        }
    }

    private fun idsAfter(kind: String, after: Long): List<Long> = sql.rawQuery("SELECT seq FROM records WHERE kind=? AND seq>? ORDER BY seq LIMIT 128",
        arrayOf(kind, after.toString())).use { c -> buildList { while (c.moveToNext()) add(c.getLong(0)) } }

    private fun read(seq: Long): JSONObject {
        val length = sql.rawQuery("SELECT length(body) FROM records WHERE seq=?", arrayOf(seq.toString())).use { c -> check(c.moveToFirst()); c.getInt(0) }
        val text = StringBuilder(length)
        var offset = 1
        while (offset <= length) {
            val chunk = sql.rawQuery("SELECT substr(body,?,262144) FROM records WHERE seq=?", arrayOf(offset.toString(), seq.toString()))
                .use { c -> check(c.moveToFirst()); c.getString(0) }
            check(chunk.isNotEmpty()); text.append(chunk); offset += chunk.length
        }
        return JSONObject(cipher.decrypt(text.toString(), aad(seq)) ?: error("Staged memory failed authentication"))
    }

    private fun token(domain: String, value: String) = indexKey.token(domain, value)
    private fun aad(seq: Long) = "backup-stage:$id:$seq".toByteArray(Charsets.UTF_8)

    override fun close() {
        try { if (sql.inTransaction()) sql.endTransaction() }
        finally { try { sql.close() } finally { indexKey.close(); SQLiteDatabase.deleteDatabase(file) } }
    }
}
