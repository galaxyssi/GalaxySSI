package com.galaxyssi.chat

import org.json.JSONObject

/** Metadata only. The existing durable outbox continues to own Signal wire bytes. */
internal class MqttOutgoingChunks(private val database: AgentEncryptedDatabase, private val now: () -> Long = System::currentTimeMillis) {
    data class Batch(val query: MqttChunkReceipts.Query, val selected: List<Pair<Int, JSONObject>>, val paths: ByteArray) {
        fun attempted(index: Int) = MqttChunkReceipts.brokers.filterIndexed { bit, _ ->
            index >= 0 && paths[index].toInt() and (1 shl bit) != 0
        }.toSet()
    }
    private data class Row(val manifest: String, val count: Int, val request: String, val epoch: String,
                           val revision: Long, val bitmap: ByteArray, val paths: ByteArray)
    init {
        database.indexedTransaction { db ->
            db.execSQL("""CREATE TABLE IF NOT EXISTS mqtt_outgoing_chunks (
                scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, manifest_hash TEXT NOT NULL,
                chunk_count INTEGER NOT NULL, request_id TEXT NOT NULL, store_epoch TEXT NOT NULL,
                revision INTEGER NOT NULL, stored_bitmap BLOB NOT NULL, path_bits BLOB NOT NULL,
                expires_at INTEGER NOT NULL, PRIMARY KEY(scope_digest,transfer_id))""")
            db.execSQL("CREATE INDEX IF NOT EXISTS mqtt_outgoing_chunk_expiry ON mqtt_outgoing_chunks(expires_at)")
        }
    }

    fun prepare(scope: String, parts: List<JSONObject>): Batch {
        val chunk = MqttChunkManifest.parse(parts.first())
        require(parts.size == chunk.count) { "Incomplete outgoing chunk manifest" }
        val key = arrayOf(MqttDurableChunks.scopeKey(scope), chunk.transfer)
        val request = MqttChunkReceipts.newRequest()
        val (stored, paths) = database.indexedTransaction { db ->
            db.delete("mqtt_outgoing_chunks", "scope_digest=? AND transfer_id=? AND expires_at<=?", key + now().toString())
            db.execSQL("DELETE FROM mqtt_outgoing_chunks WHERE rowid IN (SELECT rowid FROM mqtt_outgoing_chunks WHERE expires_at<=? LIMIT 256)", arrayOf(now()))
            val row = read(db, key)
            if (row == null) {
                for ((where, args, limit) in listOf(Triple("", emptyArray<String>(), 65536), Triple(" WHERE scope_digest=?", arrayOf(key[0]), 4096))) {
                    db.rawQuery("SELECT COUNT(*) FROM mqtt_outgoing_chunks$where", args).use {
                        check(it.moveToFirst()); require(it.getInt(0) < limit) { "Outgoing chunk metadata capacity exceeded" }
                    }
                }
                val stored = ByteArray((chunk.count + 7) / 8)
                val paths = ByteArray(chunk.count)
                db.execSQL("INSERT INTO mqtt_outgoing_chunks VALUES(?,?,?,?,?,'',-1,?,?,?)",
                    arrayOf(key[0], key[1], chunk.manifestHash, chunk.count, request, stored, paths, now() + 7L * 86400 * 1000))
                stored to paths
            } else {
                require(row.manifest == chunk.manifestHash && row.count == chunk.count) { "Outgoing chunk manifest changed" }
                db.execSQL("UPDATE mqtt_outgoing_chunks SET request_id=?,store_epoch='',revision=-1 WHERE scope_digest=? AND transfer_id=?", arrayOf(request, key[0], key[1]))
                row.bitmap to row.paths
            }
        }
        val query = MqttChunkReceipts.Query(chunk.transfer, chunk.manifestHash, chunk.count, request)
        val selected = parts.mapIndexedNotNull { index, part ->
            if (stored[index / 8].toInt() and (1 shl (index % 8)) != 0) null
            else index to JSONObject(part.toString()).put(MqttChunkReceipts.FIELD, query.wire())
        }.ifEmpty { listOf(-1 to query.wire()) }
        return Batch(query, selected, paths)
    }

    fun accept(scope: String, raw: JSONObject): Boolean {
        val state = MqttChunkReceipts.parseState(raw)
        val query = state.query
        val key = arrayOf(MqttDurableChunks.scopeKey(scope), query.transfer)
        return database.indexedTransaction { db ->
            val row = read(db, key, fresh = true) ?: return@indexedTransaction false
            if (row.manifest != query.manifest || row.count != query.count || row.request != query.request) return@indexedTransaction false
            if (row.epoch.isNotEmpty() && (row.epoch != state.epoch || state.revision < row.revision)) return@indexedTransaction false
            if (row.epoch.isNotEmpty() && state.revision == row.revision) {
                require(row.bitmap.contentEquals(state.bitmap)) { "Conflicting chunk state revision" }
                return@indexedTransaction false
            }
            db.execSQL("UPDATE mqtt_outgoing_chunks SET store_epoch=?,revision=?,stored_bitmap=? WHERE scope_digest=? AND transfer_id=?",
                arrayOf(state.epoch, state.revision, state.bitmap, key[0], key[1]))
            true
        }
    }

    fun recordPath(scope: String, query: MqttChunkReceipts.Query, index: Int, broker: String) {
        if (index < 0) return
        require(index in 0 until query.count)
        val bit = MqttChunkReceipts.brokers.indexOf(broker).also { require(it >= 0) }
        val key = arrayOf(MqttDurableChunks.scopeKey(scope), query.transfer, query.request)
        database.indexedTransaction { db ->
            val paths = db.rawQuery("SELECT path_bits FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=? AND request_id=?", key)
                .use { if (it.moveToFirst()) it.getBlob(0) else null } ?: return@indexedTransaction
            paths[index] = (paths[index].toInt() or (1 shl bit)).toByte()
            db.execSQL("UPDATE mqtt_outgoing_chunks SET path_bits=? WHERE scope_digest=? AND transfer_id=? AND request_id=?",
                arrayOf(paths, key[0], key[1], key[2]))
        }
    }

    private fun read(db: android.database.sqlite.SQLiteDatabase, key: Array<String>, fresh: Boolean = false): Row? {
        val suffix = if (fresh) " AND expires_at>?" else ""
        return db.rawQuery("SELECT manifest_hash,chunk_count,request_id,store_epoch,revision,stored_bitmap,path_bits FROM mqtt_outgoing_chunks " +
            "WHERE scope_digest=? AND transfer_id=?$suffix", if (fresh) key + now().toString() else key).use {
            if (it.moveToFirst()) Row(it.getString(0), it.getInt(1), it.getString(2), it.getString(3), it.getLong(4), it.getBlob(5), it.getBlob(6)) else null
        }
    }
}
