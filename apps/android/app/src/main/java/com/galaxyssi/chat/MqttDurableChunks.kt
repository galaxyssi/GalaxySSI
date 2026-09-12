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
                PRIMARY KEY(scope_digest,transfer_id))""")
            db.execSQL("CREATE INDEX IF NOT EXISTS mqtt_wire_expiry ON mqtt_wire_transfers(expires_at)")
            db.execSQL("""CREATE TABLE IF NOT EXISTS mqtt_wire_parts (
                scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, chunk_index INTEGER NOT NULL,
                chunk_hash TEXT NOT NULL, data BLOB NOT NULL,
                PRIMARY KEY(scope_digest,transfer_id,chunk_index))""")
        }
    }

    fun accept(authenticatedScope: String, wire: JSONObject): String? {
        val chunk = Chunk.parse(wire)
        val scope = scopeKey(authenticatedScope)
        return database.indexedTransaction { db ->
            prune(db)
            val args = arrayOf(scope, chunk.transfer)
            val row = db.rawQuery("SELECT manifest_hash,stored_bytes FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", args)
                .use { if (it.moveToFirst()) it.getString(0) to it.getInt(1) else null }
            val stored = if (row == null) {
                quota(db, scope, chunk.total)
                db.execSQL("INSERT INTO mqtt_wire_transfers(scope_digest,transfer_id,manifest_hash,chunk_count,total_bytes,stored_bytes,expires_at) " +
                    "VALUES(?,?,?,?,?,0,?)", arrayOf(scope, chunk.transfer, chunk.manifestHash, chunk.count, chunk.total, now() + RETENTION_MILLIS))
                0
            } else {
                require(row.first == chunk.manifestHash) { "MQTT chunk metadata mismatch" }
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
                }
            } else {
                require(stored + chunk.data.size <= chunk.total) { "MQTT transfer length check failed" }
                db.execSQL("INSERT INTO mqtt_wire_parts VALUES(?,?,?,?,?)", arrayOf(scope, chunk.transfer, chunk.index, chunk.digest, chunk.data))
                db.execSQL("UPDATE mqtt_wire_transfers SET stored_bytes=stored_bytes+? WHERE scope_digest=? AND transfer_id=?",
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
    fun releaseAfterStore(authenticatedScope: String, transfer: String, storedWireHash: String): Boolean {
        val scope = scopeKey(authenticatedScope)
        checkedHash(transfer); checkedHash(storedWireHash)
        return database.indexedTransaction { db ->
            val digest = db.rawQuery("SELECT wire_hash FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", arrayOf(scope, transfer))
                .use { if (it.moveToFirst()) it.getString(0) else null }
            if (digest != storedWireHash) return@indexedTransaction false
            delete(db, scope, transfer)
            true
        }
    }

    private fun quota(db: SQLiteDatabase, scope: String, total: Int) {
        for ((where, args, limits) in listOf(Triple("", emptyArray<String>(), maxTransfers to maxBytes),
            Triple(" WHERE scope_digest=?", arrayOf(scope), maxPeerTransfers to maxPeerBytes))) {
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

    internal data class Chunk(val transfer: String, val manifestHash: String, val count: Int, val total: Int,
        val index: Int, val digest: String, val data: ByteArray, val source: String, val target: String) {
        companion object {
            fun parse(wire: JSONObject): Chunk {
                require(GalaxySSIMqttWireChunking.isChunk(wire)) { "Not a GalaxySSI MQTT chunk" }
                val transfer = checkedHash(wire.opt("transfer_id"))
                require(transfer == checkedHash(wire.opt("sha256"))) { "Invalid MQTT transfer identity" }
                val digest = checkedHash(wire.opt("chunk_sha256"))
                val count = integer(wire, "chunk_count", 1, GalaxySSIMqttWireChunking.MAX_CHUNK_COUNT)
                val total = integer(wire, "total_bytes", count, GalaxySSIMqttWireChunking.MAX_REASSEMBLED_BYTES)
                val index = integer(wire, "chunk_index", 0, count - 1)
                val source = text(wire.opt("from")); val target = text(wire.opt("to"))
                val encoded = wire.opt("data")
                require(encoded is String && encoded.length in 1..4 * ((GalaxySSIMqttWireChunking.DEFAULT_CHUNK_DATA_BYTES + 2) / 3)) {
                    "Invalid MQTT chunk encoding"
                }
                val data = Base64.getDecoder().decode(encoded)
                require(data.isNotEmpty() && data.size <= minOf(GalaxySSIMqttWireChunking.DEFAULT_CHUNK_DATA_BYTES, total) &&
                    hash(data) == digest && Base64.getEncoder().encodeToString(data) == encoded) { "MQTT chunk integrity check failed" }
                val canonical = ByteArrayOutputStream().apply {
                    write("GalaxySSI/WireChunkManifest/v1\u0000".toByteArray(Charsets.US_ASCII))
                    for (value in listOf(transfer, count.toString(), total.toString(), source, target)) {
                        val bytes = value.toByteArray(Charsets.UTF_8)
                        write("${bytes.size}:".toByteArray(Charsets.US_ASCII)); write(bytes)
                    }
                }.toByteArray()
                return Chunk(transfer, hash(canonical), count, total, index, digest, data, source, target)
            }
        }
    }

    companion object {
        const val RETENTION_MILLIS = 8L * 24 * 60 * 60 * 1_000
        private val HASH = Regex("[a-f0-9]{64}")
        private fun hash(bytes: ByteArray) = GalaxySSIMqttWireChunking.sha256(bytes)
        private fun scopeKey(scope: String) = hash(text(scope).toByteArray(Charsets.UTF_8))
        private fun checkedHash(value: Any?): String {
            require(value is String && HASH.matches(value)) { "Invalid MQTT chunk hash" }
            return value
        }
        private fun text(value: Any?, maximum: Int = 512): String {
            require(value is String && value.isNotEmpty() && value.toByteArray(Charsets.UTF_8).size <= maximum &&
                value.none { it.code < 32 || it.code == 127 }) { "Invalid MQTT chunk identity" }
            require(value.indices.none { index ->
                (value[index].isHighSurrogate() && (index == value.lastIndex || !value[index + 1].isLowSurrogate())) ||
                    (value[index].isLowSurrogate() && (index == 0 || !value[index - 1].isHighSurrogate()))
            })
            return value
        }
        private fun integer(wire: JSONObject, key: String, minimum: Int, maximum: Int): Int {
            val value = wire.opt(key)
            require(value is Int || value is Long) { "Invalid MQTT chunk counters" }
            return (value as Number).toLong().also { require(it in minimum.toLong()..maximum.toLong()) }.toInt()
        }
    }
}
