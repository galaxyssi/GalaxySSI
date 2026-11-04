package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.io.InputStream
import java.security.SecureRandom
import java.util.UUID

/** Selection and frozen export manifests are per-row encrypted, not an unbounded Intent or JSON array. */
internal class HealthOriginalLibraryStore(private val context: Context, private val originals: HealthOriginalStore,
    private val directory: File = File(context.filesDir, "health-original-exports-v1")) {
    private val db get() = originals.libraryDatabase
    val artifacts = HealthPrivateExportFile(directory)
    private fun valid(id: String) { require(UUID.fromString(id).toString() == id) }
    private fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        return try { block().also { db.setTransactionSuccessful() } } finally { db.endTransaction(); originals.libraryChanged() }
    }
    fun createSelection(): HealthOriginalExportSession = HealthOriginalExportSession(UUID.randomUUID().toString(), HealthOriginalExportState.SELECTING, System.currentTimeMillis()).also { put(it) }
    fun ensureSelection(id: String) = transaction {
        valid(id)
        val existing = session(id)
        if (existing == null) put(HealthOriginalExportSession(id, HealthOriginalExportState.SELECTING, System.currentTimeMillis()))
        else check(existing.state == HealthOriginalExportState.SELECTING)
    }
    fun session(id: String): HealthOriginalExportSession? {
        valid(id)
        return db.rawQuery("SELECT state,attempt,payload FROM library_exports WHERE id=?", arrayOf(id)).use {
            if (!it.moveToFirst()) null else HealthOriginalExportSession.from(originals.libraryUnpack("export", id, it.getBlob(2))).also { s ->
                check(s.id == id && s.state.name == it.getString(0) && s.attempt == it.getString(1))
            }
        }
    }
    private fun put(s: HealthOriginalExportSession) {
        val values = ContentValues().apply { put("id", s.id); put("state", s.state.name); put("attempt", s.attempt); put("created_at", s.createdAt); put("payload", originals.libraryPack("export", s.id, s.json())) }
        if (db.update("library_exports", values, "id=?", arrayOf(s.id)) == 0) db.insertOrThrow("library_exports", null, values)
    }
    fun count(id: String): Long = db.rawQuery("SELECT COUNT(*) FROM library_export_items WHERE session_id=?", arrayOf(id)).use { it.moveToFirst(); it.getLong(0) }
    fun selected(id: String, page: List<HealthOriginal>): Set<String> {
        if (page.isEmpty()) return emptySet()
        require(page.size <= 30)
        return db.rawQuery("SELECT original_id FROM library_export_items WHERE session_id=? AND original_id IN (${page.joinToString(",") { "?" }})",
            (listOf(id) + page.map { it.id }).toTypedArray()).use { buildSet { while (it.moveToNext()) add(it.getString(0)) } }
    }
    fun select(id: String, values: List<String>, selected: Boolean) = transaction {
        check(session(id)?.state == HealthOriginalExportState.SELECTING)
        require(values.size <= 30)
        values.forEach { original -> valid(original)
            if (selected) {
                require(originals.original(original)?.reviewOnly == false)
                db.insertWithOnConflict("library_export_items", null, ContentValues().apply { put("session_id", id); put("original_id", original) }, SQLiteDatabase.CONFLICT_IGNORE)
            }
            else db.delete("library_export_items", "session_id=? AND original_id=?", arrayOf(id, original))
        }
    }
    fun clearSelection(id: String) = transaction {
        check(session(id)?.state == HealthOriginalExportState.SELECTING)
        db.delete("library_export_items", "session_id=?", arrayOf(id))
    }
    fun prepare(id: String): HealthOriginalExportSession = transaction {
        val s = requireNotNull(session(id)); check(s.state == HealthOriginalExportState.SELECTING)
        var count = 0L; var size = 0L; var missing = 0L
        db.rawQuery("SELECT original_id FROM library_export_items WHERE session_id=? ORDER BY original_id", arrayOf(id)).use { rows -> while (rows.moveToNext()) {
            val original = requireNotNull(originals.original(rows.getString(0)))
            check(!original.reviewOnly)
            count++; size = Math.addExact(size, original.size); if (!originals.present(original)) missing++
            db.update("library_export_items", ContentValues().apply { put("snapshot", originals.libraryPack("export-item", "$id:${original.id}", original.json())) },
                "session_id=? AND original_id=?", arrayOf(id, original.id))
        } }
        require(count > 0)
        s.copy(state = HealthOriginalExportState.REVIEW, count = count, sourceBytes = size, missing = missing).also(::put)
    }
    fun items(id: String, after: String = ""): List<HealthOriginal> = db.rawQuery(
        "SELECT original_id,snapshot FROM library_export_items WHERE session_id=? AND original_id>? ORDER BY original_id LIMIT 31", arrayOf(id, after)
    ).use { rows -> buildList { while (rows.moveToNext()) {
        val original = HealthOriginal.from(originals.libraryUnpack("export-item", "$id:${rows.getString(0)}", rows.getBlob(1)))
        check(original.id == rows.getString(0)); add(original)
    } } }
    fun queue(id: String): HealthOriginalExportSession = transaction {
        val s = requireNotNull(session(id)); check(s.state in listOf(HealthOriginalExportState.REVIEW, HealthOriginalExportState.FAILED)); check(s.count > 0 && s.missing == 0L)
        s.copy(state = HealthOriginalExportState.QUEUED, error = "", completed = 0, dispatch = UUID.randomUUID().toString()).also(::put)
    }
    fun edit(id: String) = transaction {
        val s = requireNotNull(session(id)); check(s.state in listOf(HealthOriginalExportState.REVIEW, HealthOriginalExportState.FAILED, HealthOriginalExportState.CANCELLED))
        db.update("library_export_items", ContentValues().apply { putNull("snapshot") }, "session_id=?", arrayOf(id))
        put(s.copy(state = HealthOriginalExportState.SELECTING, count = 0, sourceBytes = 0, missing = 0, completed = 0, error = ""))
    }
    fun cannotStart(id: String, dispatch: String, reason: String = "background_unavailable") = transaction {
        val s = session(id) ?: return@transaction
        if (s.dispatch == dispatch && s.state in listOf(HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING)) put(s.copy(state = HealthOriginalExportState.FAILED, error = reason))
    }
    fun cancel(id: String) = transaction {
        val s = requireNotNull(session(id)); if (s.state !in listOf(HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED)) put(s.copy(state = HealthOriginalExportState.CANCELLED))
    }
    fun active(after: String = ""): List<String> = db.rawQuery("SELECT id FROM library_exports WHERE state IN ('QUEUED','GENERATING') AND id>? ORDER BY id LIMIT 100", arrayOf(after))
        .use { buildList { while (it.moveToNext()) add(it.getString(0)) } }
    fun latest(): HealthOriginalExportSession? = db.rawQuery("SELECT id FROM library_exports WHERE state<>'SELECTING' ORDER BY created_at DESC,id DESC LIMIT 1", null)
        .use { if (it.moveToFirst()) session(it.getString(0)) else null }
    fun claim(id: String, dispatch: String? = null): Pair<HealthOriginalExportSession, ByteArray>? {
        var pending: ByteArray? = null
        try {
            val result = transaction {
                val s = session(id) ?: return@transaction null
                if (s.state !in listOf(HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING) || dispatch != null && s.dispatch != dispatch) return@transaction null
                val next = s.copy(state = HealthOriginalExportState.GENERATING, attempt = UUID.randomUUID().toString(), completed = 0, archiveBytes = 0, sha256 = "", error = "")
                val key = ByteArray(32).also(SecureRandom()::nextBytes); pending = key
                put(next); db.update("library_exports", ContentValues().apply { put("key_payload", AgentStorageCipher.encryptBinary(key, originals.libraryKeyAad("$id:${next.attempt}"))) }, "id=?", arrayOf(id))
                next to key
            }
            pending = null; return result
        } finally { pending?.fill(0) }
    }
    fun current(id: String, attempt: String) = db.rawQuery("SELECT 1 FROM library_exports WHERE id=? AND attempt=? AND state='GENERATING'", arrayOf(id, attempt)).use { it.moveToFirst() }
    fun advance(s: HealthOriginalExportSession, completed: Long) = transaction { if (current(s.id, s.attempt)) put(requireNotNull(session(s.id)).copy(completed = completed)) }
    fun generated(s: HealthOriginalExportSession, size: Long, hash: String) = transaction {
        check(current(s.id, s.attempt)); check(file(s).isFile)
        put(requireNotNull(session(s.id)).copy(state = HealthOriginalExportState.GENERATED, completed = s.count, archiveBytes = size, sha256 = hash))
    }
    fun failed(s: HealthOriginalExportSession, reason: String) = transaction {
        if (current(s.id, s.attempt)) put(requireNotNull(session(s.id)).copy(state = HealthOriginalExportState.FAILED, error = reason))
    }
    fun interrupted(s: HealthOriginalExportSession) = transaction {
        if (current(s.id, s.attempt)) put(requireNotNull(session(s.id)).copy(state = HealthOriginalExportState.QUEUED))
    }
    fun saved(s: HealthOriginalExportSession) = transaction {
        val latest = requireNotNull(session(s.id)); check(latest.attempt == s.attempt && latest.state in listOf(HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED))
        put(latest.copy(state = HealthOriginalExportState.SAVED))
    }
    fun file(s: HealthOriginalExportSession, partial: Boolean = false): File {
        return artifacts.file(s.id, s.attempt, partial)
    }
    fun aad(s: HealthOriginalExportSession) = "health-original-export-v1|${s.id}|${s.attempt}".toByteArray(Charsets.UTF_8)
    fun input(s: HealthOriginalExportSession): InputStream {
        check(s.state in listOf(HealthOriginalExportState.GENERATED, HealthOriginalExportState.SAVED))
        val encrypted = db.rawQuery("SELECT key_payload FROM library_exports WHERE id=? AND attempt=?", arrayOf(s.id, s.attempt)).use { check(it.moveToFirst()); it.getBlob(0) }
        val key = AgentStorageCipher.decryptBinary(encrypted, originals.libraryKeyAad("${s.id}:${s.attempt}"))
        return try { artifacts.input(s.id, s.attempt, key, aad(s)) } finally { key.fill(0) }
    }
    fun cleanupAbandoned(s: HealthOriginalExportSession) {
        artifacts.cleanup(s.id, s.attempt)
    }
    companion object {
        fun createSchema(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE library_exports(id TEXT PRIMARY KEY,state TEXT NOT NULL,attempt TEXT NOT NULL,created_at INTEGER NOT NULL,payload BLOB NOT NULL,key_payload BLOB)")
            db.execSQL("CREATE INDEX library_export_state ON library_exports(state,id)")
            db.execSQL("CREATE TABLE library_export_items(session_id TEXT NOT NULL REFERENCES library_exports(id) ON DELETE CASCADE,original_id TEXT NOT NULL REFERENCES originals(id),snapshot BLOB,PRIMARY KEY(session_id,original_id))")
        }
    }
}
