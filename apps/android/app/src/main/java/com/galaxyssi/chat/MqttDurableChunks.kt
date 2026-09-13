package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64

/** Pair-authenticated Signal ciphertext fragments; never plaintext attachment encryption. */
internal class MqttDurableChunks(
    private val database: AgentEncryptedDatabase,
    private val now: () -> Long = System::currentTimeMillis,
    private val maxTransfers: Int = 16,
    private val maxBytes: Long = 32L * 1024 * 1024,
    private val maxPeerTransfers: Int = 8,
    private val maxPeerBytes: Long = 16L * 1024 * 1024
) {
    init {
        require(maxTransfers > 0 && maxBytes > 0 && maxPeerTransfers > 0 && maxPeerBytes > 0)
        database.indexedTransaction { db ->
            db.execSQL("""CREATE TABLE IF NOT EXISTS mqtt_wire_transfers (
                scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, manifest_hash TEXT NOT NULL,
                chunk_count INTEGER NOT NULL, total_bytes INTEGER NOT NULL, stored_bytes INTEGER NOT NULL,
                expires_at INTEGER NOT NULL, wire_hash TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL, target TEXT NOT NULL, store_epoch TEXT NOT NULL,
                revision INTEGER NOT NULL DEFAULT 0, message_id TEXT NOT NULL DEFAULT '',
                PRIMARY KEY(scope_digest,transfer_id))""")
            db.execSQL("CREATE INDEX IF NOT EXISTS mqtt_wire_expiry ON mqtt_wire_transfers(expires_at)")
            db.execSQL("""CREATE TABLE IF NOT EXISTS mqtt_wire_parts (
                scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, chunk_index INTEGER NOT NULL,
                chunk_hash TEXT NOT NULL, data BLOB NOT NULL,
                PRIMARY KEY(scope_digest,transfer_id,chunk_index))""")
        }
    }

    fun accept(authenticatedScope: String, wire: JSONObject): String? {
        val chunk = MqttChunkManifest.parse(wire)
        val scope = scopeKey(authenticatedScope)
        return database.indexedTransaction { db ->
            val args = arrayOf(scope, chunk.transfer)
            val expired = db.rawQuery("SELECT 1 FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=? AND expires_at<=?",
                args + now().toString()).use { it.moveToFirst() }
            if (expired) delete(db, scope, chunk.transfer)
            prune(db)
            val row = db.rawQuery("SELECT manifest_hash,stored_bytes,message_id FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", args)
                .use { if (it.moveToFirst()) Triple(it.getString(0), it.getInt(1), it.getString(2)) else null }
            val stored = if (row == null) {
                quota(db, scope, chunk.total)
                db.execSQL("INSERT INTO mqtt_wire_transfers(scope_digest,transfer_id,manifest_hash,chunk_count,total_bytes,stored_bytes,expires_at,source,target,store_epoch) " +
                    "VALUES(?,?,?,?,?,0,?,?,?,?)", arrayOf(scope, chunk.transfer, chunk.manifestHash, chunk.count, chunk.total,
                        now() + RETENTION_MILLIS, chunk.source, chunk.target, MqttChunkReceipts.newRequest()))
                0
            } else {
                require(row.first == chunk.manifestHash) { "MQTT chunk metadata mismatch" }
                if (row.third.isNotEmpty()) return@indexedTransaction null
                row.second
            }
            val old = db.rawQuery("SELECT chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? AND chunk_index=?",
                arrayOf(scope, chunk.transfer, chunk.index.toString())).use { if (it.moveToFirst()) it.getString(0) to it.getBlob(1) else null }
            if (old != null) {
                require(old.first == chunk.digest) { "Conflicting MQTT chunk duplicate" }
                if (!old.second.contentEquals(chunk.data)) {
                    require(hash(old.second) != old.first) { "Conflicting MQTT chunk duplicate" }
                    db.execSQL("UPDATE mqtt_wire_parts SET data=? WHERE scope_digest=? AND transfer_id=? AND chunk_index=?",
                        arrayOf(chunk.data, scope, chunk.transfer, chunk.index))
                    db.execSQL("UPDATE mqtt_wire_transfers SET revision=revision+1 WHERE scope_digest=? AND transfer_id=?", args)
                }
            } else {
                require(stored + chunk.data.size <= chunk.total) { "MQTT transfer length check failed" }
                db.execSQL("INSERT INTO mqtt_wire_parts VALUES(?,?,?,?,?)", arrayOf(scope, chunk.transfer, chunk.index, chunk.digest, chunk.data))
                db.execSQL("UPDATE mqtt_wire_transfers SET stored_bytes=stored_bytes+?,revision=revision+1 WHERE scope_digest=? AND transfer_id=?",
                    arrayOf(chunk.data.size, scope, chunk.transfer))
            }
            val count = db.rawQuery("SELECT COUNT(*) FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", args)
                .use { check(it.moveToFirst()); it.getInt(0) }
            if (count < chunk.count) return@indexedTransaction null
            val output = ByteArrayOutputStream(chunk.total)
            db.rawQuery("SELECT chunk_index,chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? ORDER BY chunk_index", args).use { cursor ->
                var expected = 0
                while (cursor.moveToNext()) {
                    val bytes = cursor.getBlob(2)
                    require(cursor.getInt(0) == expected++ && hash(bytes) == cursor.getString(1)) { "Stored MQTT chunk integrity check failed" }
                    require(output.size() + bytes.size <= chunk.total) { "MQTT transfer length check failed" }
                    output.write(bytes)
                }
            }
            val assembled = output.toByteArray()
            require(assembled.size == chunk.total && hash(assembled) == chunk.transfer) { "MQTT transfer integrity check failed" }
            val result = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(assembled)).toString()
            val decoded = JSONObject(result)
            require(decoded.optString("from") == chunk.source && decoded.optString("to") == chunk.target) { "MQTT assembled endpoint mismatch" }
            val digest = MqttDeliveryEnvelope.contentHash(decoded)
            db.execSQL("UPDATE mqtt_wire_transfers SET wire_hash=? WHERE scope_digest=? AND transfer_id=?", arrayOf(digest, scope, chunk.transfer))
            result
        }
    }

    fun storedIndices(authenticatedScope: String, transfer: String): List<Int> {
        val scope = scopeKey(authenticatedScope)
        checkedHash(transfer)
        return database.indexedTransaction { db ->
            db.rawQuery("SELECT p.chunk_index FROM mqtt_wire_parts p JOIN mqtt_wire_transfers t " +
                "ON p.scope_digest=t.scope_digest AND p.transfer_id=t.transfer_id WHERE p.scope_digest=? AND p.transfer_id=? " +
                "AND t.expires_at>? ORDER BY p.chunk_index", arrayOf(scope, transfer, now().toString())).use { cursor ->
                buildList { while (cursor.moveToNext()) add(cursor.getInt(0)) }
            }
        }
    }

    /** Caller obtains the proof from the committed business inbox, not a network claim. */
    fun releaseAfterStore(authenticatedScope: String, transfer: String, storedWireHash: String, messageId: String = ""): Boolean {
        val scope = scopeKey(authenticatedScope)
        checkedHash(transfer); checkedHash(storedWireHash)
        return database.indexedTransaction { db ->
            val digest = db.rawQuery("SELECT wire_hash FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", arrayOf(scope, transfer))
                .use { if (it.moveToFirst()) it.getString(0) else null }
            if (digest != storedWireHash) return@indexedTransaction false
            if (messageId.isEmpty()) delete(db, scope, transfer)
            else {
                text(messageId)
                db.delete("mqtt_wire_parts", "scope_digest=? AND transfer_id=?", arrayOf(scope, transfer))
                db.execSQL("UPDATE mqtt_wire_transfers SET message_id=?,stored_bytes=0,revision=revision+1 WHERE scope_digest=? AND transfer_id=?",
                    arrayOf(messageId, scope, transfer))
            }
            true
        }
    }

    private fun quota(db: SQLiteDatabase, scope: String, total: Int) {
        for ((where, args, limit) in listOf(Triple("", emptyArray<String>(), 65536), Triple(" WHERE scope_digest=?", arrayOf(scope), 4096))) {
            db.rawQuery("SELECT COUNT(*) FROM mqtt_wire_transfers$where", args).use {
                check(it.moveToFirst()); require(it.getInt(0) < limit) { "Durable MQTT manifest capacity exceeded" }
            }
        }
        for ((where, args, limits) in listOf(Triple(" WHERE message_id=''", emptyArray<String>(), maxTransfers to maxBytes),
            Triple(" WHERE message_id='' AND scope_digest=?", arrayOf(scope), maxPeerTransfers to maxPeerBytes))) {
            db.rawQuery("SELECT COUNT(*),COALESCE(SUM(total_bytes),0) FROM mqtt_wire_transfers$where", args).use {
                check(it.moveToFirst())
                require(it.getInt(0) < limits.first && it.getLong(1) + total <= limits.second) { "Durable MQTT fragment capacity exceeded" }
            }
        }
    }

    private fun prune(db: SQLiteDatabase) {
        val expired = db.rawQuery("SELECT scope_digest,transfer_id FROM mqtt_wire_transfers WHERE expires_at<=? ORDER BY expires_at LIMIT 256",
            arrayOf(now().toString())).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0) to cursor.getString(1)) } }
        expired.forEach { delete(db, it.first, it.second) }
    }

    private fun delete(db: SQLiteDatabase, scope: String, transfer: String) {
        db.delete("mqtt_wire_parts", "scope_digest=? AND transfer_id=?", arrayOf(scope, transfer))
        db.delete("mqtt_wire_transfers", "scope_digest=? AND transfer_id=?", arrayOf(scope, transfer))
    }

    data class Snapshot(val state: JSONObject, val proof: Pair<String, String>? = null)
    fun snapshot(authenticatedScope: String, query: MqttChunkReceipts.Query): Snapshot {
        val key = arrayOf(scopeKey(authenticatedScope), query.transfer)
        return database.indexedTransaction { db ->
            db.rawQuery("SELECT manifest_hash,chunk_count,store_epoch,revision,message_id,wire_hash FROM mqtt_wire_transfers " +
                "WHERE scope_digest=? AND transfer_id=? AND expires_at>?", key + now().toString()).use { row ->
                if (!row.moveToFirst()) return@indexedTransaction Snapshot(query.response("0".repeat(32), 0, emptyList()))
                require(row.getString(0) == query.manifest && row.getInt(1) == query.count) { "Chunk probe manifest mismatch" }
                val epoch = row.getString(2)
                var revision = row.getLong(3)
                if (row.getString(4).isNotEmpty()) return@indexedTransaction Snapshot(
                    query.response(epoch, revision, (0 until query.count).toList()), row.getString(4) to row.getString(5))
                val valid = mutableListOf<Int>()
                val corrupt = mutableListOf<Int>()
                var stored = 0
                db.rawQuery("SELECT chunk_index,chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? ORDER BY chunk_index", key).use { parts ->
                    while (parts.moveToNext()) {
                        val data = parts.getBlob(2)
                        if (hash(data) == parts.getString(1)) { valid.add(parts.getInt(0)); stored += data.size }
                        else corrupt.add(parts.getInt(0))
                    }
                }
                if (corrupt.isNotEmpty()) {
                    corrupt.forEach { db.delete("mqtt_wire_parts", "scope_digest=? AND transfer_id=? AND chunk_index=?", key + it.toString()) }
                    revision++
                    db.execSQL("UPDATE mqtt_wire_transfers SET stored_bytes=?,revision=?,wire_hash='' WHERE scope_digest=? AND transfer_id=?",
                        arrayOf(stored, revision, key[0], key[1]))
                }
                Snapshot(query.response(epoch, revision, valid))
            }
        }
    }

    fun recoverComplete(authenticatedScope: String, query: MqttChunkReceipts.Query): String? {
        val key = arrayOf(scopeKey(authenticatedScope), query.transfer)
        val part = database.indexedTransaction { db ->
            db.rawQuery("SELECT manifest_hash,chunk_count,total_bytes,source,target,message_id FROM mqtt_wire_transfers " +
                "WHERE scope_digest=? AND transfer_id=? AND expires_at>?", key + now().toString()).use { row ->
                if (!row.moveToFirst() || row.getString(5).isNotEmpty() || row.getString(0) != query.manifest || row.getInt(1) != query.count) return@indexedTransaction null
                val count = db.rawQuery("SELECT COUNT(*) FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", key).use { check(it.moveToFirst()); it.getInt(0) }
                if (count != query.count) return@indexedTransaction null
                db.rawQuery("SELECT chunk_index,chunk_hash,data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? ORDER BY chunk_index DESC LIMIT 1", key).use {
                    check(it.moveToFirst())
                    JSONObject().put("scheme", GalaxySSIMqttWireChunking.SCHEME).put("transfer_id", query.transfer).put("sha256", query.transfer)
                        .put("chunk_count", query.count).put("total_bytes", row.getInt(2)).put("from", row.getString(3)).put("to", row.getString(4))
                        .put("chunk_index", it.getInt(0)).put("chunk_sha256", it.getString(1)).put("data", Base64.getEncoder().encodeToString(it.getBlob(2)))
                }
            }
        } ?: return null
        return accept(authenticatedScope, part)
    }

    companion object {
        const val RETENTION_MILLIS = 8L * 24 * 60 * 60 * 1_000
        private fun hash(bytes: ByteArray) = MqttChunkManifest.hash(bytes)
        internal fun scopeKey(scope: String) = hash(text(scope).toByteArray(Charsets.UTF_8))
        private fun checkedHash(value: Any?) = MqttChunkManifest.checkedHash(value)
        private fun text(value: Any?) = MqttChunkManifest.text(value)
    }
}
