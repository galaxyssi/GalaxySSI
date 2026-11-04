package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import java.io.File
import java.security.SecureRandom
import java.util.UUID
import org.json.JSONObject

/** Confirmed export snapshots are independent from live observations and never replace the health archive. */
internal class HealthRecordExportStore(private val context: Context, private val name: String = "health_record_exports_v1.db",
    directory: File = File(context.filesDir, "health-record-exports-v1")) : Closeable {
    private val helper = Database(context, name); private val db get() = helper.writableDatabase
    val artifacts = HealthPrivateExportFile(directory)
    private fun aad(kind: String, id: String) = "$name|health-record-export-v1|$kind|$id".toByteArray(Charsets.UTF_8)
    private fun pack(kind: String, id: String, j: JSONObject): ByteArray {
        val bytes = j.toString().toByteArray(Charsets.UTF_8)
        return try { AgentStorageCipher.encryptBinary(bytes, aad(kind, id)) } finally { bytes.fill(0) }
    }
    private fun unpack(kind: String, id: String, bytes: ByteArray): JSONObject {
        val plain = AgentStorageCipher.decryptBinary(bytes, aad(kind, id))
        return try { JSONObject(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }
    private fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        return try { block().also { db.setTransactionSuccessful() } } finally { db.endTransaction(); runCatching { context.contentResolver.notifyChange(changes(context, name), null) } }
    }
    private fun put(s: HealthRecordExportSession) {
        val value = ContentValues().apply { put("id", s.id); put("state", s.state.name); put("phase", s.phase); put("dispatch", s.dispatch); put("attempt", s.attempt); put("created_at", s.createdAt); put("payload", pack("session", s.id, s.json())) }
        if (db.update("exports", value, "id=?", arrayOf(s.id)) == 0) db.insertOrThrow("exports", null, value)
    }
    fun create(scope: HealthRecordExportScope): HealthRecordExportSession = HealthRecordExportSession(UUID.randomUUID().toString(), scope, System.currentTimeMillis()).also { put(it) }
    fun session(id: String): HealthRecordExportSession? {
        require(UUID.fromString(id).toString() == id)
        return db.rawQuery("SELECT state,phase,dispatch,attempt,payload FROM exports WHERE id=?", arrayOf(id)).use {
            if (!it.moveToFirst()) null else HealthRecordExportSession.from(unpack("session", id, it.getBlob(4))).also { s ->
                check(s.id == id && s.state.name == it.getString(0) && s.phase == it.getString(1) && s.dispatch == it.getString(2) && s.attempt == it.getString(3))
            }
        }
    }
    fun history(before: Pair<Long, String>? = null): List<HealthRecordExportSession> {
        val where = if (before == null) "" else "WHERE created_at<? OR (created_at=? AND id<?)"
        val args = before?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        return db.rawQuery("SELECT id FROM exports $where ORDER BY created_at DESC,id DESC LIMIT 31", args).use { rows -> buildList { while (rows.moveToNext()) add(requireNotNull(session(rows.getString(0)))) } }
    }
    fun active(after: String = ""): List<HealthRecordExportSession> = db.rawQuery("SELECT id FROM exports WHERE state IN ('PREPARING','QUEUED','GENERATING') AND id>? ORDER BY id LIMIT 100", arrayOf(after))
        .use { rows -> buildList { while (rows.moveToNext()) add(requireNotNull(session(rows.getString(0)))) } }
    fun current(s: HealthRecordExportSession): Boolean = db.rawQuery("SELECT 1 FROM exports WHERE id=? AND dispatch=? AND attempt=? AND phase=? AND state IN ('PREPARING','GENERATING')",
        arrayOf(s.id, s.dispatch, s.attempt, s.phase)).use { it.moveToFirst() }
    fun claimPrepare(id: String, dispatch: String): HealthRecordExportSession? = transaction {
        val s = session(id) ?: return@transaction null
        if (s.dispatch != dispatch || s.phase != "prepare" || s.state != HealthRecordExportState.PREPARING) return@transaction null
        db.delete("export_records", "export_id=?", arrayOf(id))
        s.copy(attempt = UUID.randomUUID().toString(), count = 0, rows = 0, completed = 0, sourceWarnings = 0, estimatedBytes = 0, error = "", preparedAt = 0, confirmedAt = 0, scanned = 0).also(::put)
    }
    fun append(s: HealthRecordExportSession, values: List<Pair<HealthObservation, HealthExportSourceStatus>>, scanned: Int = values.size): HealthRecordExportSession = transaction {
        require(values.size <= 30 && scanned in values.size..30); check(current(s)); val prior = requireNotNull(session(s.id)); var index = prior.count
        var rows = prior.rows; var warnings = prior.sourceWarnings; var estimate = prior.estimatedBytes
        values.forEach { (record, status) ->
            val snapshot = prior.scope.snapshot(record); val sequence = ++index
            val j = snapshot.json().put("source_status_at_preview", status.name)
            db.insertOrThrow("export_records", null, ContentValues().apply {
                put("export_id", s.id); put("sequence", sequence); put("record_id", snapshot.id); put("revision", snapshot.revision)
                put("payload", pack("record", "${s.id}:$sequence:${snapshot.id}:${snapshot.revision}", j))
            })
            rows += HealthRecordExportRows.count(snapshot)
            if (status !in listOf(HealthExportSourceStatus.NONE, HealthExportSourceStatus.AVAILABLE)) warnings++
            val plain = j.toString().toByteArray(Charsets.UTF_8)
            try { estimate = Math.addExact(estimate, plain.size.toLong()) } finally { plain.fill(0) }
        }
        prior.copy(count = index, rows = rows, sourceWarnings = warnings, estimatedBytes = estimate, completed = index, scanned = prior.scanned + scanned).also(::put)
    }
    fun review(s: HealthRecordExportSession) = transaction {
        check(current(s)); val prior = requireNotNull(session(s.id))
        if (prior.count == 0L) put(prior.copy(state = HealthRecordExportState.FAILED, error = "no_records"))
        else put(prior.copy(state = HealthRecordExportState.REVIEW, preparedAt = System.currentTimeMillis()))
    }
    fun items(id: String, after: Long = 0): List<HealthRecordExportItem> = db.rawQuery("SELECT sequence,record_id,revision,payload FROM export_records WHERE export_id=? AND sequence>? ORDER BY sequence LIMIT 31", arrayOf(id, after.toString())).use { cursor -> buildList {
        while (cursor.moveToNext()) {
            val sequence = cursor.getLong(0); val recordId = cursor.getString(1); val revision = cursor.getInt(2)
            val j = unpack("record", "$id:$sequence:$recordId:$revision", cursor.getBlob(3)); val record = HealthObservation.from(j)
            check(record.id == recordId && record.revision == revision && record.profileId == "self" && HealthObservationPolicy.validate(record.draft) == null)
            add(HealthRecordExportItem(sequence, record, HealthExportSourceStatus.valueOf(j.getString("source_status_at_preview"))))
        }
    } }
    fun queue(id: String): HealthRecordExportSession = transaction {
        val s = requireNotNull(session(id)); check(s.state == HealthRecordExportState.REVIEW || s.state == HealthRecordExportState.FAILED && s.phase == "generate")
        check(s.count > 0)
        s.copy(state = HealthRecordExportState.QUEUED, phase = "generate", dispatch = UUID.randomUUID().toString(), completed = 0, error = "", confirmedAt = System.currentTimeMillis()).also(::put)
    }
    fun retryPreparation(id: String): HealthRecordExportSession = transaction {
        val s = requireNotNull(session(id)); check(s.state in listOf(HealthRecordExportState.FAILED, HealthRecordExportState.CANCELLED))
        s.copy(state = HealthRecordExportState.PREPARING, phase = "prepare", dispatch = UUID.randomUUID().toString(), completed = 0, error = "").also(::put)
    }
    fun claimGenerate(id: String, dispatch: String): Pair<HealthRecordExportSession, ByteArray>? {
        var pending: ByteArray? = null
        try {
            val result = transaction {
                val s = session(id) ?: return@transaction null
                if (s.dispatch != dispatch || s.phase != "generate" || s.state !in listOf(HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING)) return@transaction null
                val next = s.copy(state = HealthRecordExportState.GENERATING, attempt = UUID.randomUUID().toString(), completed = 0, artifactBytes = 0, sha256 = "", error = "")
                val key = ByteArray(32).also(SecureRandom()::nextBytes); pending = key; put(next)
                db.update("exports", ContentValues().apply { put("key_payload", AgentStorageCipher.encryptBinary(key, aad("key", "$id:${next.attempt}"))) }, "id=?", arrayOf(id))
                next to key
            }
            pending = null; return result
        } finally { pending?.fill(0) }
    }
    fun advance(s: HealthRecordExportSession, count: Long) = transaction { if (current(s)) put(requireNotNull(session(s.id)).copy(completed = count)) }
    fun generated(s: HealthRecordExportSession, digest: HealthExportDigest) = transaction {
        check(current(s) && artifacts.file(s.id, s.attempt).isFile && digest.bytes > 0 && digest.sha256.matches(Regex("[0-9a-f]{64}")))
        put(requireNotNull(session(s.id)).copy(state = HealthRecordExportState.GENERATED, completed = s.count, artifactBytes = digest.bytes, sha256 = digest.sha256))
    }
    fun failed(s: HealthRecordExportSession, reason: String) = transaction { if (current(s)) put(requireNotNull(session(s.id)).copy(state = HealthRecordExportState.FAILED, error = reason)) }
    fun externalFailure(id: String, dispatch: String, reason: String) = transaction {
        val s = session(id) ?: return@transaction
        if (s.dispatch == dispatch && s.state in listOf(HealthRecordExportState.PREPARING, HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING)) put(s.copy(state = HealthRecordExportState.FAILED, error = reason))
    }
    fun interrupted(s: HealthRecordExportSession) = transaction { if (current(s)) put(requireNotNull(session(s.id)).copy(state = if (s.phase == "prepare") HealthRecordExportState.PREPARING else HealthRecordExportState.QUEUED)) }
    fun cancel(id: String) = transaction {
        val s = requireNotNull(session(id)); if (s.state !in listOf(HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED)) put(s.copy(state = HealthRecordExportState.CANCELLED))
    }
    fun saved(s: HealthRecordExportSession) = transaction {
        val now = requireNotNull(session(s.id)); check(now.attempt == s.attempt && now.state in listOf(HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED)); put(now.copy(state = HealthRecordExportState.SAVED))
    }
    fun artifactAad(s: HealthRecordExportSession) = aad("artifact", "${s.id}:${s.attempt}")
    fun input(s: HealthRecordExportSession): java.io.InputStream {
        check(s.state in listOf(HealthRecordExportState.GENERATED, HealthRecordExportState.SAVED))
        val encrypted = db.rawQuery("SELECT key_payload FROM exports WHERE id=? AND attempt=?", arrayOf(s.id, s.attempt)).use { check(it.moveToFirst()); it.getBlob(0) }
        val key = AgentStorageCipher.decryptBinary(encrypted, aad("key", "${s.id}:${s.attempt}"))
        return try { artifacts.input(s.id, s.attempt, key, artifactAad(s)) } finally { key.fill(0) }
    }
    override fun close() = helper.close()
    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) = db.setForeignKeyConstraintsEnabled(true)
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE exports(id TEXT PRIMARY KEY,state TEXT NOT NULL,phase TEXT NOT NULL,dispatch TEXT NOT NULL,attempt TEXT NOT NULL,created_at INTEGER NOT NULL,payload BLOB NOT NULL,key_payload BLOB)")
            db.execSQL("CREATE INDEX export_history ON exports(created_at DESC,id DESC)"); db.execSQL("CREATE INDEX export_active ON exports(state,id)")
            db.execSQL("CREATE TABLE export_records(export_id TEXT NOT NULL REFERENCES exports(id) ON DELETE CASCADE,sequence INTEGER NOT NULL,record_id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(export_id,sequence),UNIQUE(export_id,record_id))")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { error("Unsupported record-export schema upgrade") }
    }
    companion object { fun changes(context: Context, name: String = "health_record_exports_v1.db") = android.net.Uri.parse("content://${context.packageName}.health-originals/changes/record-exports/" + android.net.Uri.encode(name)) }
}
