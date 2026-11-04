package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import org.json.JSONObject

internal enum class HealthBackupGeneration { GENERATING, READY, FAILED, CANCELLED, INTERRUPTED }
internal enum class HealthBackupSave { NONE, SAVING, VERIFIED, FAILED, CANCELLED, INTERRUPTED }
internal data class HealthBackupHistoryCursor(val created: Long, val id: String)
internal data class HealthBackupReceipt(
    val id: String, val created: Long, val first: Long, val last: Long, val records: Long, val originals: Int, val missing: Int,
    val generation: HealthBackupGeneration = HealthBackupGeneration.GENERATING,
    val size: Long = 0, val hash: String = "", val save: HealthBackupSave = HealthBackupSave.NONE, val savedAt: Long = 0
) {
    init {
        require(HealthProfilePolicy.uuid(id) && created > 0 && first >= 0 && last >= first && records >= 0 && originals >= 0 && missing in 0..originals)
        require((size == 0L && hash.isEmpty() || size > 0L && hash.matches(Regex("[0-9a-f]{64}"))) && savedAt >= 0L)
        require(generation != HealthBackupGeneration.READY || size > 0L)
    }
    val artifact get() = if (size > 0L) HealthBackupArtifact(id, size, hash, missing) else null
    fun json() = JSONObject().put("first", first).put("last", last).put("records", records).put("originals", originals)
        .put("missing", missing).put("generation", generation.name).put("size", size).put("hash", hash)
        .put("save", save.name).put("savedAt", savedAt)
    companion object {
        fun from(id: String, created: Long, value: JSONObject) = HealthBackupReceipt(id, created,
            value.getLong("first"), value.getLong("last"), value.getLong("records"), value.getInt("originals"), value.getInt("missing"),
            HealthBackupGeneration.valueOf(value.getString("generation")), value.getLong("size"), value.getString("hash"),
            HealthBackupSave.valueOf(value.getString("save")), value.getLong("savedAt"))
    }
}
internal data class HealthBackupHistoryItem(val receipt: HealthBackupReceipt, val available: Boolean)
internal data class HealthBackupHistoryPage(val rows: List<HealthBackupHistoryItem>, val next: HealthBackupHistoryCursor?)

internal class HealthBackupHistoryStore(context: Context, private val name: String) : Closeable {
    private val helper = object : SQLiteOpenHelper(context.applicationContext, name, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE backups(id TEXT PRIMARY KEY,created INTEGER NOT NULL,payload BLOB NOT NULL)")
            db.execSQL("CREATE INDEX backup_history_page ON backups(created DESC,id DESC)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = error("Unsupported backup history upgrade")
    }
    private fun aad(id: String, created: Long) = "$name|health-backup-history-v1|$id|$created".toByteArray(Charsets.UTF_8)
    private fun read(row: Cursor): HealthBackupReceipt {
        val id = row.getString(0)
        val created = row.getLong(1)
        val plain = AgentStorageCipher.decryptBinary(row.getBlob(2), aad(id, created))
        return try { HealthBackupReceipt.from(id, created, JSONObject(String(plain, Charsets.UTF_8))) } finally { plain.fill(0) }
    }
    fun get(id: String): HealthBackupReceipt? = helper.readableDatabase.rawQuery(
        "SELECT id,created,payload FROM backups WHERE id=?", arrayOf(id)
    ).use { if (it.moveToFirst()) read(it) else null }

    fun page(before: HealthBackupHistoryCursor?): List<HealthBackupReceipt> {
        val where = if (before == null) "" else "WHERE created<? OR (created=? AND id<?)"
        val args = before?.let { arrayOf(it.created.toString(), it.created.toString(), it.id) }
        return helper.readableDatabase.rawQuery("SELECT id,created,payload FROM backups $where ORDER BY created DESC,id DESC LIMIT 31", args)
            .use { rows -> buildList { while (rows.moveToNext()) add(read(rows)) } }
    }

    fun put(receipt: HealthBackupReceipt) {
        val plain = receipt.json().toString().toByteArray(Charsets.UTF_8)
        val encrypted = try { AgentStorageCipher.encryptBinary(plain, aad(receipt.id, receipt.created)) } finally { plain.fill(0) }
        try {
            check(helper.writableDatabase.insertWithOnConflict("backups", null, ContentValues().apply {
                put("id", receipt.id); put("created", receipt.created); put("payload", encrypted)
            }, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
        } finally { encrypted.fill(0) }
    }
    override fun close() = helper.close()
}
