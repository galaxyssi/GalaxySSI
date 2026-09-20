package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject
import java.util.UUID

/** Only timing and opaque row keys are plaintext; endpoints, receipts, and wire data are encrypted. */
internal class LinkTransportReceiptJournal(context: Context, private val name: String = DATABASE_NAME) :
    SQLiteOpenHelper(context.applicationContext, name, null, 2) {
    private val cipher = AgentRowStorageCipher(context.applicationContext, name)
    init { setWriteAheadLoggingEnabled(true) }
    override fun onConfigure(db: SQLiteDatabase) { db.execSQL("PRAGMA synchronous=FULL") }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE receipts (id TEXT PRIMARY KEY, next_at INTEGER NOT NULL, attempt TEXT NOT NULL, payload TEXT NOT NULL)")
        db.execSQL("CREATE INDEX receipts_due ON receipts(next_at, id)")
        createReplayCache(db)
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) { createReplayCache(db) }
    private fun createReplayCache(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE IF NOT EXISTS receipt_replays (id TEXT PRIMARY KEY, saved_at INTEGER NOT NULL, payload TEXT NOT NULL)")
        db.execSQL("CREATE INDEX IF NOT EXISTS receipt_replays_age ON receipt_replays(saved_at)")
    }

    @Synchronized fun enqueue(receipt: LinkTransportReceipt, now: Long = System.currentTimeMillis()) {
        val cached = readableDatabase.query("receipt_replays", arrayOf("payload", "saved_at"),
            "id = ? AND saved_at >= ? AND saved_at <= ?", arrayOf(receipt.key, (now - REPLAY_TTL).toString(), now.toString()),
            null, null, null, "1").use { if (it.moveToFirst()) it.getString(0) to it.getLong(1) else null }?.takeIf {
            val value = cipher.decrypt(it.first, receipt.key.toByteArray())?.let(::JSONObject)
                ?: error("Cached transport receipt failed authentication")
            val prepared = value.optLong("prepared_at", -1)
            prepared >= 0 && now >= prepared && now - prepared <= REPLAY_TTL
        }
        // A replay does not replace an in-flight attempt or its already-prepared Signal ciphertext.
        val inserted = writableDatabase.insertWithOnConflict("receipts", null, ContentValues().apply {
            put("id", receipt.key); put("next_at", maxOf(now, (cached?.second ?: 0) + if (cached != null) 2_000 else 0)); put("attempt", "")
            put("payload", cached?.first ?: seal(receipt.key, JSONObject().put("receipt", receipt.json()).put("wire", "")))
        }, SQLiteDatabase.CONFLICT_IGNORE)
        check(inserted != -1L || readableDatabase.query("receipts", arrayOf("id"), "id = ?",
            arrayOf(receipt.key), null, null, null, "1").use { it.moveToFirst() }) {
            "Transport receipt intent could not be persisted"
        }
    }

    @Synchronized fun due(now: Long, limit: Int = 4): List<String> {
        require(limit in 1..32)
        return readableDatabase.query("receipts", arrayOf("id"), "next_at <= ?", arrayOf(now.toString()),
            null, null, "next_at, id", limit.toString()).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
    }

    @Synchronized fun claim(key: String, now: Long): LinkTransportReceiptWork? {
        val db = writableDatabase
        val encoded = db.query("receipts", arrayOf("payload"), "id = ? AND next_at <= ?", arrayOf(key, now.toString()),
            null, null, null, "1").use { if (it.moveToFirst()) it.getString(0) else null } ?: return null
        val attempt = LinkTransportReceiptAttempt(key, UUID.randomUUID().toString())
        check(db.update("receipts", ContentValues().apply {
            put("attempt", attempt.token); put("next_at", now + RETRY_MILLIS)
        }, "id = ? AND next_at <= ?", arrayOf(key, now.toString())) == 1)
        val value = cipher.decrypt(encoded, key.toByteArray())?.let(::JSONObject)
            ?: error("Transport receipt row failed authentication")
        val receipt = LinkTransportReceipt.from(value.getJSONObject("receipt"))
        check(receipt.key == key)
        return LinkTransportReceiptWork(receipt, value.optString("wire"), attempt)
    }

    @Synchronized fun prepared(work: LinkTransportReceiptWork, wire: String, now: Long = System.currentTimeMillis()): Boolean {
        require(wire.isNotBlank() && wire.toByteArray(Charsets.UTF_8).size <= 64 * 1024)
        return writableDatabase.update("receipts", ContentValues().apply {
            put("payload", seal(work.attempt.key, JSONObject().put("receipt", work.receipt.json()).put("wire", wire)
                .put("prepared_at", now)))
        }, "id = ? AND attempt = ?", arrayOf(work.attempt.key, work.attempt.token)) == 1
    }

    @Synchronized fun acknowledge(attempt: LinkTransportReceiptAttempt, now: Long = System.currentTimeMillis()): Boolean {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val payload = db.query("receipts", arrayOf("payload"), "id = ? AND attempt = ?",
                arrayOf(attempt.key, attempt.token), null, null, null, "1").use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: return false
            // A duplicate delivery reuses this exact encrypted receipt, rather
            // than advancing Signal and inventing another logical ACK record.
            db.insertWithOnConflict("receipt_replays", null, ContentValues().apply {
                put("id", attempt.key); put("saved_at", now); put("payload", payload)
            }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
            db.delete("receipts", "id = ? AND attempt = ?", arrayOf(attempt.key, attempt.token))
            db.delete("receipt_replays", "saved_at < ?", arrayOf((now - REPLAY_TTL).toString()))
            db.execSQL("DELETE FROM receipt_replays WHERE id IN (SELECT id FROM receipt_replays ORDER BY saved_at DESC, id LIMIT -1 OFFSET 256)")
            db.setTransactionSuccessful()
            return true
        } finally { db.endTransaction() }
    }

    @Synchronized fun reconnect(now: Long = System.currentTimeMillis()) {
        writableDatabase.execSQL("UPDATE receipts SET next_at = MIN(next_at, ?), attempt = ''", arrayOf(now))
    }

    @Synchronized fun nextDue(): Long? = readableDatabase.rawQuery("SELECT MIN(next_at) FROM receipts", null).use {
        if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
    }

    private fun seal(key: String, value: JSONObject) = cipher.encrypt(value.toString(), key.toByteArray())
    companion object {
        const val DATABASE_NAME = "galaxyssi_transport_receipts.db"
        const val RETRY_MILLIS = 12_000L
        const val REPLAY_TTL = 24 * 60 * 60_000L
    }
}
