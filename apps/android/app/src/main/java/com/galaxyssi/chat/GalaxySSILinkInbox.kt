package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** Signal ratchet writes and accept() share the same encrypted database transaction. */
internal class GalaxySSILinkInbox(
    private val database: AgentEncryptedDatabase,
    private val now: () -> Long = System::currentTimeMillis,
    private val maxPendingBytes: Long = 64L * 1024 * 1024,
    private val maxRecords: Int = 100_000,
    private val maxPeerPendingBytes: Long = 16L * 1024 * 1024,
    private val maxPeerRecords: Int = 20_000
) {
    data class Peer(val scope: String, val endpoint: String, val phone: Boolean)
    enum class Stage { STORED, PENDING, COMPLETED }
    data class Accepted(val recordKey: String, val stage: Stage, val payload: JSONObject)
    data class Pending(val recordKey: String, val peer: Peer, val messageId: String,
                       val payload: String, val createdAt: Long)
    data class Replay(val messageId: String, val receiptRequired: Boolean, val completed: Boolean,
                      val contentHash: String, val recordKey: String)
    class ContentConflict : IllegalArgumentException("Conflicting authenticated message content")
    class CapacityExceeded : IllegalStateException("Durable inbox capacity exceeded")

    init {
        require(maxPendingBytes > 0 && maxRecords > 0 && maxPeerPendingBytes > 0 && maxPeerRecords > 0)
        database.indexedTransaction { db ->
            db.execSQL("""CREATE TABLE IF NOT EXISTS link_inbox_records (
                record_key TEXT PRIMARY KEY NOT NULL, scope_digest TEXT NOT NULL,
                message_id TEXT NOT NULL, content_hash TEXT NOT NULL, created_at INTEGER NOT NULL,
                retain_until INTEGER NOT NULL, completed INTEGER NOT NULL, payload_bytes INTEGER NOT NULL,
                receipt_required INTEGER NOT NULL, UNIQUE(scope_digest,message_id))""")
            db.execSQL("CREATE INDEX IF NOT EXISTS link_inbox_pending ON link_inbox_records(completed,record_key)")
            db.execSQL("CREATE INDEX IF NOT EXISTS link_inbox_expiry ON link_inbox_records(completed,retain_until,record_key)")
            db.execSQL("CREATE TABLE IF NOT EXISTS link_inbox_usage (scope_digest TEXT PRIMARY KEY NOT NULL, " +
                "record_count INTEGER NOT NULL CHECK(record_count>=0), pending_bytes INTEGER NOT NULL CHECK(pending_bytes>=0))")
            db.execSQL("""CREATE TABLE IF NOT EXISTS link_inbox_ciphertexts (
                scope_digest TEXT NOT NULL, ciphertext_digest TEXT NOT NULL, record_key TEXT NOT NULL,
                PRIMARY KEY(scope_digest,ciphertext_digest))""")
            db.execSQL("CREATE INDEX IF NOT EXISTS link_inbox_cipher_record ON link_inbox_ciphertexts(record_key)")
        }
    }

    fun accept(peer: Peer, messageId: String, contentHash: String, payload: JSONObject,
               ciphertextDigest: String = "", receiptRequired: Boolean = false): Accepted {
        require(peer.scope.isNotBlank() && peer.scope.length <= 512 && peer.endpoint.isNotBlank())
        require(messageId.isNotBlank() && messageId.length <= 256 && HASH.matches(contentHash))
        require(ciphertextDigest.isEmpty() || HASH.matches(ciphertextDigest))
        require(payload.optString("message_id") == messageId)
        val scope = MqttImmutableContent.sha256(peer.scope)
        val key = MqttImmutableContent.sha256("$scope\u0000$messageId")
        val stamped = JSONObject(payload.toString()).put(MqttImmutableContent.RECORD_KEY, key)
        val encoded = JSONObject().put("scope", peer.scope).put("endpoint", peer.endpoint)
            .put("phone", peer.phone).put("message_id", messageId).put("payload", stamped).toString()
        val size = encoded.toByteArray(Charsets.UTF_8).size
        require(size <= 2 * 1024 * 1024 + 4_096) { "Inbound payload exceeds limit" }
        return database.indexedTransaction { db ->
            val existing = record(db, key)
            if (existing != null && (existing.contentHash != contentHash || existing.messageId != messageId ||
                    existing.receiptRequired != receiptRequired)) throw ContentConflict()
            if (existing == null) {
                checkQuota(db, "", maxRecords, maxPendingBytes, size)
                checkQuota(db, scope, maxPeerRecords, maxPeerPendingBytes, size)
                database.writeString(payloadKey(key), encoded)
                db.execSQL("""INSERT INTO link_inbox_records
                    (record_key,scope_digest,message_id,content_hash,created_at,retain_until,completed,payload_bytes,receipt_required)
                    VALUES(?,?,?,?,?,?,0,?,?)""", arrayOf(key, scope, messageId, contentHash, now(), now() + RETENTION_MILLIS,
                    size, if (receiptRequired) 1 else 0))
                adjustUsage(db, "", 1, size)
                adjustUsage(db, scope, 1, size)
            } else if (!existing.completed) {
                readPending(key, existing.messageId, existing.createdAt)
            }
            if (ciphertextDigest.isNotEmpty()) {
                val knownCipher = db.rawQuery("SELECT record_key FROM link_inbox_ciphertexts WHERE scope_digest=? AND ciphertext_digest=?",
                    arrayOf(scope, ciphertextDigest)).use { if (it.moveToFirst()) it.getString(0) else null }
                if (knownCipher == null) {
                    db.rawQuery("SELECT COUNT(*) FROM link_inbox_ciphertexts WHERE record_key=?", arrayOf(key)).use {
                        check(it.moveToFirst())
                        if (it.getInt(0) >= 8) throw CapacityExceeded()
                    }
                }
                db.execSQL("INSERT OR IGNORE INTO link_inbox_ciphertexts(scope_digest,ciphertext_digest,record_key) VALUES(?,?,?)",
                    arrayOf(scope, ciphertextDigest, key))
                val bound = db.rawQuery("SELECT record_key FROM link_inbox_ciphertexts WHERE scope_digest=? AND ciphertext_digest=?",
                    arrayOf(scope, ciphertextDigest)).use { check(it.moveToFirst()); it.getString(0) }
                check(bound == key) { "Signal ciphertext is bound to another message" }
            }
            payload.put(MqttImmutableContent.RECORD_KEY, key)
            Accepted(key, when { existing == null -> Stage.STORED; existing.completed -> Stage.COMPLETED; else -> Stage.PENDING }, stamped)
        }
    }

    fun replay(peerScope: String, ciphertextDigest: String): Replay? {
        require(HASH.matches(ciphertextDigest))
        return database.indexedTransaction { db ->
            val key = db.rawQuery("SELECT record_key FROM link_inbox_ciphertexts WHERE scope_digest=? AND ciphertext_digest=?",
                arrayOf(MqttImmutableContent.sha256(peerScope), ciphertextDigest)).use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: return@indexedTransaction null
            val value = checkNotNull(record(db, key)) { "Signal replay points to a missing durable inbox record" }
            if (!value.completed) readPending(key, value.messageId, value.createdAt)
            Replay(value.messageId, value.receiptRequired, value.completed, value.contentHash, key)
        }
    }

    fun complete(payload: JSONObject): Boolean {
        val key = payload.optString(MqttImmutableContent.RECORD_KEY)
        if (!HASH.matches(key)) return false
        return database.indexedTransaction { db ->
            val value = record(db, key) ?: return@indexedTransaction false
            check(value.messageId == payload.optString("message_id")) { "Inbox completion identity mismatch" }
            if (!value.completed) {
                adjustUsage(db, "", 0, -value.payloadBytes)
                adjustUsage(db, value.scopeDigest, 0, -value.payloadBytes)
                db.execSQL("UPDATE link_inbox_records SET completed=1,payload_bytes=0 WHERE record_key=?", arrayOf(key))
                database.remove(payloadKey(key))
            }
            true
        }
    }

    fun isPending(payload: JSONObject): Boolean = database.indexedTransaction { db ->
        val value = record(db, payload.optString(MqttImmutableContent.RECORD_KEY))
        value != null && !value.completed && value.messageId == payload.optString("message_id")
    }

    fun pending(afterKey: String = "", limit: Int = 16, byteLimit: Int = 4 * 1024 * 1024): List<Pending> {
        require(limit in 1..64 && byteLimit > 0)
        return database.indexedTransaction { db ->
            val rows = db.rawQuery("SELECT record_key,message_id,created_at,payload_bytes FROM link_inbox_records " +
                "WHERE completed=0 AND record_key>? ORDER BY record_key LIMIT ?", arrayOf(afterKey, limit.toString())).use { cursor ->
                buildList {
                    var bytes = 0L
                    while (cursor.moveToNext()) {
                        val size = cursor.getInt(3)
                        if (isNotEmpty() && bytes + size > byteLimit) break
                        bytes += size
                        add(Triple(cursor.getString(0), cursor.getString(1), cursor.getLong(2)))
                    }
                }
            }
            rows.map { (key, message, createdAt) -> readPending(key, message, createdAt) }
        }
    }

    private fun readPending(key: String, message: String, createdAt: Long): Pending {
        val wrapper = JSONObject(database.readString(payloadKey(key), ""))
        check(wrapper.getString("message_id") == message) { "Durable inbox body identity mismatch" }
        val payload = wrapper.getJSONObject("payload")
        check(payload.getString(MqttImmutableContent.RECORD_KEY) == key && payload.getString("message_id") == message)
        val peer = Peer(wrapper.getString("scope"), wrapper.getString("endpoint"), wrapper.getBoolean("phone"))
        check(MqttImmutableContent.sha256("${MqttImmutableContent.sha256(peer.scope)}\u0000$message") == key)
        return Pending(key, peer, message, payload.toString(), createdAt)
    }

    /** Never evict pending accepted work merely to admit newer traffic. */
    fun pruneCompleted(limit: Int = 256): Int = database.indexedTransaction { db ->
        require(limit in 1..1_024)
        val keys = db.rawQuery("SELECT record_key FROM link_inbox_records WHERE completed=1 AND retain_until<? LIMIT ?",
            arrayOf(now().toString(), limit.toString())).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
        keys.forEach { remove(db, it) }
        keys.size
    }

    fun forget(peerScope: String): Int = database.indexedTransaction { db ->
        val keys = db.rawQuery("SELECT record_key FROM link_inbox_records WHERE scope_digest=?",
            arrayOf(MqttImmutableContent.sha256(peerScope))).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }
        keys.forEach { remove(db, it) }
        keys.size
    }

    fun clear() = database.indexedTransaction { db ->
        db.execSQL("DELETE FROM link_inbox_ciphertexts")
        db.execSQL("DELETE FROM link_inbox_records")
        db.execSQL("DELETE FROM link_inbox_usage")
        database.removeAll(database.keys(PAYLOAD_PREFIX))
    }

    private fun remove(db: SQLiteDatabase, key: String) {
        val value = record(db, key) ?: return
        adjustUsage(db, "", -1, -value.payloadBytes)
        adjustUsage(db, value.scopeDigest, -1, -value.payloadBytes)
        db.execSQL("DELETE FROM link_inbox_ciphertexts WHERE record_key=?", arrayOf(key))
        db.execSQL("DELETE FROM link_inbox_records WHERE record_key=?", arrayOf(key))
        database.remove(payloadKey(key))
    }

    private fun checkQuota(db: SQLiteDatabase, scope: String, records: Int, bytes: Long, incomingBytes: Int) {
        db.rawQuery("SELECT record_count,pending_bytes FROM link_inbox_usage WHERE scope_digest=?", arrayOf(scope)).use {
            if (it.moveToFirst()) {
                if (it.getLong(0) >= records || it.getLong(1) + incomingBytes > bytes) throw CapacityExceeded()
            } else if (incomingBytes > bytes) throw CapacityExceeded()
        }
    }

    private fun adjustUsage(db: SQLiteDatabase, scope: String, records: Int, bytes: Int) {
        db.execSQL("INSERT OR IGNORE INTO link_inbox_usage(scope_digest,record_count,pending_bytes) VALUES(?,0,0)", arrayOf(scope))
        db.execSQL("UPDATE link_inbox_usage SET record_count=record_count+?,pending_bytes=pending_bytes+? WHERE scope_digest=?",
            arrayOf(records, bytes, scope))
        if (records < 0) db.execSQL("DELETE FROM link_inbox_usage WHERE scope_digest=? AND record_count=0", arrayOf(scope))
    }

    private data class Record(val messageId: String, val contentHash: String, val createdAt: Long,
                              val completed: Boolean, val receiptRequired: Boolean,
                              val scopeDigest: String, val payloadBytes: Int)
    private fun record(db: SQLiteDatabase, key: String): Record? = db.rawQuery(
        "SELECT message_id,content_hash,created_at,completed,receipt_required,scope_digest,payload_bytes FROM link_inbox_records WHERE record_key=?", arrayOf(key)).use {
        if (!it.moveToFirst()) null else Record(it.getString(0), it.getString(1), it.getLong(2), it.getInt(3) != 0,
            it.getInt(4) != 0, it.getString(5), it.getInt(6))
    }

    private fun payloadKey(key: String) = PAYLOAD_PREFIX + key
    companion object {
        private val HASH = Regex("[a-f0-9]{64}")
        private const val PAYLOAD_PREFIX = "rx:payload:"
        internal const val RETENTION_MILLIS = 8L * 24 * 60 * 60 * 1_000
    }
}
