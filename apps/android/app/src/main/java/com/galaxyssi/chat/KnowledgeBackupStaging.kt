package com.galaxyssi.chat

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.util.UUID

/** Encrypted disk rows replace both the incoming array and the old/new mutation lists. */
internal class KnowledgeBackupStaging(context: Context) : Closeable {
    private val id = UUID.randomUUID().toString()
    private val index = BackupStagingTokenKey()
    private val directory = File(context.cacheDir, "knowledge-backup-staging").apply { check(isDirectory || mkdirs()) }
    internal val file = File(directory, "$id.db")
    private val sql = SQLiteDatabase.openOrCreateDatabase(file, null)
    private val cipher = AgentRowStorageCipher(context, "knowledge-backup-staging:${context.filesDir.absolutePath}")
    private var begun = false
    private var ended = false
    private var verified = false
    private var prepared = false
    private var next = 0L
    private var rows = 0L
    init {
        try {
            sql.execSQL("PRAGMA cache_size=-2048")
            sql.execSQL("PRAGMA synchronous=FULL")
            sql.execSQL("CREATE TABLE records(seq INTEGER PRIMARY KEY,token TEXT NOT NULL UNIQUE,incoming TEXT,previous TEXT)")
            sql.beginTransaction()
        } catch (failure: Throwable) { try { sql.close() } finally { index.close(); SQLiteDatabase.deleteDatabase(file) }; throw failure }
    }
    fun accept(section: String, key: String, input: InputStream) {
        check(!verified && !ended) { "Unexpected data after knowledge backup end" }
        val json = KnowledgeLegacyBackupReader.record(input)
        when (section) {
            "knowledge" -> when (key) {
                "begin" -> { check(!begun && json.getInt("schema") == 1); begun = true }
                "end" -> { check(begun && json.getLong("rows") == rows) { "Knowledge backup count mismatch" }; ended = true }
                else -> error("Unknown knowledge backup boundary")
            }
            "knowledge-row" -> {
                check(begun) { "Missing knowledge backup beginning" }
                val item = KnowledgeBackupRecords.decode(json)
                check(key == KnowledgeBackupRecords.key(item.id)) { "Knowledge backup identity mismatch" }
                add(item)
            }
            else -> error("Unknown knowledge backup section")
        }
    }
    fun acceptLegacy(input: InputStream) {
        check(!begun && !verified)
        begun = true
        KnowledgeLegacyBackupReader.read(input) { json ->
            require(json.optString("id").isNotBlank()) { "Knowledge backup has no stable ID" }
            add(requireNotNull(AgentKnowledgeCodec.decodeItem(json)) { "Invalid legacy knowledge backup item" })
        }
        ended = true
    }
    internal fun acceptSource(source: String, items: Sequence<AgentKnowledgeItem>): Long {
        check(!begun && !verified)
        begun = true
        for (item in items) {
            check(!Thread.currentThread().isInterrupted)
            if (item.source != source || item.title.isBlank() || item.content.isBlank()) continue
            require(item.id.isNotBlank()) { "Knowledge item has no stable ID" }
            // Preserve first-valid-ID wins without a corpus-sized plaintext set.
            if (position(item.id) == null) add(item)
        }
        ended = true
        validateArchive()
        return rows
    }
    private fun position(id: String): Long? =
        sql.rawQuery("SELECT seq FROM records WHERE token=?", arrayOf(index.token("item", id))).use {
            if (it.moveToFirst()) it.getLong(0) else null
        }
    internal fun item(id: String, previous: Boolean): AgentKnowledgeItem? {
        check(prepared)
        return position(id)?.let { read(it, if (previous) "previous" else "incoming") }
    }
    internal fun previous(): Sequence<AgentKnowledgeItem> = sequence {
        check(prepared)
        for (seq in positions()) read(seq, "previous")?.let { yield(it) }
    }
    private fun add(item: AgentKnowledgeItem) {
        val seq = next
        val token = index.token("item", item.id)
        val body = encrypt(item, seq, "incoming")
        sql.execSQL("INSERT INTO records(seq,token,incoming) VALUES(?,?,?)", arrayOf(seq, token, body))
        next = Math.addExact(next, 1); rows = Math.addExact(rows, 1)
    }
    fun validateArchive() {
        check(begun && ended && !verified)
        sql.setTransactionSuccessful(); sql.endTransaction(); verified = true
    }
    fun rememberPrevious(item: AgentKnowledgeItem) {
        check(verified && !prepared)
        if (!sql.inTransaction()) sql.beginTransaction()
        val token = index.token("item", item.id)
        val existing = sql.rawQuery("SELECT seq,previous IS NOT NULL FROM records WHERE token=?", arrayOf(token)).use {
            if (!it.moveToFirst()) null else { check(it.getInt(1) == 0); it.getLong(0) }
        }
        val seq = existing ?: next
        if (existing == null) {
            sql.execSQL("INSERT INTO records(seq,token,previous) VALUES(?,?,?)", arrayOf(seq, token, encrypt(item, seq, "previous")))
            next = Math.addExact(next, 1)
        } else sql.execSQL("UPDATE records SET previous=? WHERE seq=?", arrayOf(encrypt(item, seq, "previous"), seq))
    }
    fun finishPrevious() {
        check(verified && !prepared)
        if (sql.inTransaction()) { sql.setTransactionSuccessful(); sql.endTransaction() }
        prepared = true
    }
    fun incoming(): Sequence<AgentKnowledgeItem> = sequence {
        check(verified)
        for (seq in positions()) read(seq, "incoming")?.let { yield(it) }
    }
    fun changes(includeUnchanged: Boolean = false): Sequence<Pair<AgentKnowledgeItem?, AgentKnowledgeItem?>> = sequence {
        check(prepared)
        for (seq in positions()) {
            val before = read(seq, "previous")
            val after = read(seq, "incoming")
            check(before == null || after == null || before.id == after.id)
            if (includeUnchanged || before != after) yield(before to after)
        }
    }
    private fun positions(): Sequence<Long> = sequence {
        var after = -1L
        while (true) {
            val page = sql.rawQuery("SELECT seq FROM records WHERE seq>? ORDER BY seq LIMIT 64", arrayOf(after.toString()))
                .use { c -> buildList { while (c.moveToNext()) add(c.getLong(0)) } }
            if (page.isEmpty()) break
            yieldAll(page); after = page.last()
        }
    }
    private fun read(seq: Long, column: String): AgentKnowledgeItem? {
        require(column == "incoming" || column == "previous")
        val length = sql.rawQuery("SELECT length($column) FROM records WHERE seq=?", arrayOf(seq.toString())).use {
            check(it.moveToFirst()); if (it.isNull(0)) return null else it.getLong(0)
        }
        val body = StringBuilder()
        var offset = 1L
        while (offset <= length) {
            val part = sql.rawQuery("SELECT substr($column,?,262144) FROM records WHERE seq=?", arrayOf(offset.toString(), seq.toString()))
                .use { check(it.moveToFirst()); it.getString(0) }
            check(part.isNotEmpty()); body.append(part); offset += part.length
        }
        val item = KnowledgeBackupRecords.decode(JSONObject(cipher.decrypt(body.toString(), aad(seq, column))
            ?: error("Staged knowledge failed authentication")))
        val token = sql.rawQuery("SELECT token FROM records WHERE seq=?", arrayOf(seq.toString())).use { check(it.moveToFirst()); it.getString(0) }
        check(token == index.token("item", item.id)) { "Staged knowledge identity mismatch" }
        return item
    }
    private fun encrypt(item: AgentKnowledgeItem, seq: Long, column: String) =
        cipher.encrypt(AgentKnowledgeCodec.encodeItem(item).toString(), aad(seq, column))
    private fun aad(seq: Long, column: String) = "knowledge-stage:$id:$seq:$column".toByteArray(Charsets.UTF_8)
    override fun close() {
        try { if (sql.inTransaction()) sql.endTransaction() }
        finally { try { sql.close() } finally { index.close(); SQLiteDatabase.deleteDatabase(file) } }
    }
}
