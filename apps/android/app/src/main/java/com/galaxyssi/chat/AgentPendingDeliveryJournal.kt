package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.Closeable

internal data class AgentPendingDeliveryPage(
    val deliveries: List<AgentPendingDelivery>,
    val nextBeforeSource: Long?,
    val unreadableCount: Int = 0
)

/** Atomic pending bodies/turn heads. NULL bodies are durable anti-resurrection tombstones. */
internal class AgentPendingDeliveryJournal(
    private val context: Context,
    private val databaseName: String = DATABASE_NAME,
    private val legacyPreferences: String = LEGACY_PREFERENCES
) : Closeable {
    private val helper = Database(context, databaseName)
    @Volatile private var migrationChecked = false
    private val migrationLock = Any()

    @Synchronized fun put(delivery: AgentPendingDelivery) {
        if (delivery.sourceMessageId <= 0 || delivery.conversationId.isBlank() || delivery.turnId.isBlank()) return
        transaction { db ->
            writeBody(db, delivery)
            writeHead(db, delivery.conversationId, delivery.turnId, delivery.sourceMessageId)
        }
    }

    @Synchronized fun find(source: Long, contact: String = ""): AgentPendingDelivery? {
        if (source <= 0) return null
        return transaction { readSource(it, source) }?.takeIf {
            contact.isBlank() || it.contactId.isBlank() || it.contactId == contact
        }
    }

    @Synchronized fun markRecoveryPredecessor(source: Long, successor: Long): AgentPendingDelivery? {
        if (source <= 0 || successor <= 0 || source == successor) return null
        return transaction { db ->
            readSource(db, source)?.copy(recoverySuccessorSourceMessageId = successor)?.also { writeBody(db, it) }
        }
    }

    @Synchronized fun completeResponse(delivery: AgentPendingDelivery?) {
        if (delivery == null) return
        transaction { db ->
            val current = readHead(db, delivery.conversationId, delivery.turnId)
            setOf(delivery.sourceMessageId, delivery.recoverySuccessorSourceMessageId, current ?: 0L)
                .filter { it > 0 }.forEach { source ->
                    val candidate = readSource(db, source)
                    if (candidate != null && AgentPendingDeliveryCodec.sameTurn(candidate, delivery.conversationId, delivery.turnId)) {
                        retire(db, source)
                    }
                }
            writeHead(db, delivery.conversationId, delivery.turnId, null)
        }
    }

    @Synchronized fun remove(source: Long) {
        if (source <= 0) return
        transaction { db ->
            val delivery = readSource(db, source)
            retire(db, source)
            if (delivery != null && readHead(db, delivery.conversationId, delivery.turnId) == source) {
                writeHead(db, delivery.conversationId, delivery.turnId, null)
            }
        }
    }

    @Synchronized fun isSuperseded(source: Long, conversation: String, turn: String): Boolean {
        if (source <= 0 || conversation.isBlank() || turn.isBlank()) return false
        return transaction { db ->
            val current = readHead(db, conversation, turn) ?: return@transaction false
            if (current == source) return@transaction false
            val delivery = readSource(db, source) ?: return@transaction true
            !AgentPendingDeliveryCodec.sameTurn(delivery, conversation, turn) || delivery.recoverySuccessorSourceMessageId != current
        }
    }

    /** Called from IO. Only the one-time legacy ciphertext import needs a preferences snapshot. */
    fun page(beforeSource: Long? = null, limit: Int = PAGE_SIZE): AgentPendingDeliveryPage {
        migrateLegacy()
        return synchronized(this) {
            val bound = if (beforeSource == null) "" else " AND source_id<?"
            val args = if (beforeSource == null) arrayOf(limit.coerceIn(1, 64).toString())
                else arrayOf(beforeSource.toString(), limit.coerceIn(1, 64).toString())
            val rows = helper.readableDatabase.rawQuery(
                "SELECT source_id,encoding,encrypted_value FROM pending_deliveries WHERE encrypted_value IS NOT NULL" +
                    bound + " ORDER BY source_id DESC LIMIT ?", args
            ).use { cursor -> buildList {
                while (cursor.moveToNext()) add(Row(cursor.getLong(0), cursor.getInt(1), cursor.getString(2)))
            } }
            val values = rows.mapNotNull(::decode)
            AgentPendingDeliveryPage(values, rows.lastOrNull()?.source, rows.size - values.size)
        }
    }

    @Synchronized override fun close() = helper.close()

    private fun readSource(db: SQLiteDatabase, source: Long): AgentPendingDelivery? {
        if (!exists(db, "pending_deliveries", "source_id", source.toString()) && !migrated(db)) {
            val raw = context.getSharedPreferences(legacyPreferences, Context.MODE_PRIVATE).getString("source:$source", null)
            if (raw != null) insertLegacySource(db, source, raw)
        }
        return db.rawQuery("SELECT encoding,encrypted_value FROM pending_deliveries WHERE source_id=?",
            arrayOf(source.toString())).use { cursor ->
            if (!cursor.moveToFirst() || cursor.isNull(1)) null else decode(Row(source, cursor.getInt(0), cursor.getString(1)))
        }
    }

    private fun readHead(db: SQLiteDatabase, conversation: String, turn: String): Long? {
        val key = AgentPendingDeliveryCodec.turnKey(conversation, turn)
        if (!exists(db, "pending_turn_heads", "turn_key", key)) {
            val legacyKey = AgentPendingDeliveryCodec.legacyTurnKey(conversation, turn)
            val raw = db.rawQuery("SELECT encrypted_value FROM pending_legacy_turns WHERE lookup_key=?",
                arrayOf(AgentPendingDeliveryCodec.hash(legacyKey))).use { if (it.moveToFirst()) it.getString(0) else null }
                ?: if (!migrated(db)) context.getSharedPreferences(legacyPreferences, Context.MODE_PRIVATE).getString(legacyKey, null) else null
            val source = raw?.let { AgentStorageCipher.decrypt(it, legacyAad(legacyKey)) }?.toLongOrNull()
            val candidate = source?.let { readSource(db, it) }
            // Legacy delimiter collisions must never bind another conversation's source.
            val valid = source?.takeIf { candidate != null && AgentPendingDeliveryCodec.sameTurn(candidate, conversation, turn) }
            writeHead(db, conversation, turn, valid)
        }
        return db.rawQuery("SELECT encrypted_value FROM pending_turn_heads WHERE turn_key=?", arrayOf(key)).use {
            if (!it.moveToFirst() || it.isNull(0)) null else AgentStorageCipher.decrypt(it.getString(0), aad("head:$key"))?.toLongOrNull()
        }
    }

    private fun writeBody(db: SQLiteDatabase, delivery: AgentPendingDelivery) {
        db.insertWithOnConflict("pending_deliveries", null, ContentValues().apply {
            put("source_id", delivery.sourceMessageId); put("encoding", 2)
            put("encrypted_value", AgentStorageCipher.encrypt(AgentPendingDeliveryCodec.encode(delivery), aad("source:${delivery.sourceMessageId}")))
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) { "Pending delivery write failed" } }
    }

    private fun writeHead(db: SQLiteDatabase, conversation: String, turn: String, source: Long?) {
        val key = AgentPendingDeliveryCodec.turnKey(conversation, turn)
        db.insertWithOnConflict("pending_turn_heads", null, ContentValues().apply {
            put("turn_key", key)
            if (source == null) putNull("encrypted_value") else put("encrypted_value", AgentStorageCipher.encrypt(source.toString(), aad("head:$key")))
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) { "Pending turn head write failed" } }
    }

    private fun retire(db: SQLiteDatabase, source: Long) {
        db.insertWithOnConflict("pending_deliveries", null, ContentValues().apply {
            put("source_id", source); put("encoding", 2); putNull("encrypted_value")
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) { "Pending delivery retirement failed" } }
    }

    private fun decode(row: Row): AgentPendingDelivery? = runCatching {
        val associatedData = if (row.encoding == 1) legacyAad("source:${row.source}") else aad("source:${row.source}")
        val plaintext = checkNotNull(AgentStorageCipher.decrypt(row.body, associatedData)) { "Pending delivery authentication failed" }
        AgentPendingDeliveryCodec.decode(plaintext, row.source)
    }.getOrElse {
        Log.w("GalaxySSIRecovery", "Unreadable pending delivery retained: ${it.javaClass.simpleName}")
        null
    }

    private fun insertLegacySource(db: SQLiteDatabase, source: Long, raw: String) {
        db.execSQL("INSERT OR IGNORE INTO pending_deliveries(source_id,encoding,encrypted_value) VALUES (?,1,?)", arrayOf(source, raw))
    }

    private fun migrateLegacy() = synchronized(migrationLock) {
        if (migrationChecked) return@synchronized
        val preferences = context.getSharedPreferences(legacyPreferences, Context.MODE_PRIVATE)
        if (!synchronized(this) { migrated(helper.readableDatabase) }) {
            // Preserve ciphertext, including unreadable entries. No bulk plaintext cache or UI-thread scan.
            val snapshot = preferences.all
            snapshot.entries.asSequence().chunked(64).forEach { batch -> synchronized(this) {
                transaction { db -> batch.forEach { (key, value) ->
                    if (key.startsWith("source:") || key.startsWith("turn:")) {
                        require(value is String) { "Invalid legacy pending storage; migration not committed" }
                        val source = key.removePrefix("source:").toLongOrNull()
                        if (key.startsWith("source:") && source != null && source > 0) insertLegacySource(db, source, value)
                        else if (key.startsWith("turn:")) db.execSQL(
                            "INSERT OR IGNORE INTO pending_legacy_turns(lookup_key,encrypted_value) VALUES (?,?)",
                            arrayOf(AgentPendingDeliveryCodec.hash(key), value))
                    }
                } }
            } }
            synchronized(this) { transaction { it.execSQL("INSERT OR IGNORE INTO pending_metadata(name) VALUES ('legacy_migrated')") } }
        }
        // Database rows and tombstones are authoritative before old preferences are removed.
        if (preferences.edit().clear().commit()) {
            AgentEncryptedPreferenceCache.clearNamespace(legacyPreferences)
            migrationChecked = true
        }
    }

    private fun migrated(db: SQLiteDatabase): Boolean = db.rawQuery(
        "SELECT 1 FROM pending_metadata WHERE name='legacy_migrated'", null).use { it.moveToFirst() }
    private fun exists(db: SQLiteDatabase, table: String, column: String, value: String): Boolean =
        db.rawQuery("SELECT 1 FROM $table WHERE $column=?", arrayOf(value)).use { it.moveToFirst() }
    private fun <T> transaction(block: (SQLiteDatabase) -> T): T {
        val db = helper.writableDatabase
        db.beginTransaction()
        try { return block(db).also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
    }
    private fun aad(key: String) = "pending-journal:$databaseName:$key".toByteArray(Charsets.UTF_8)
    private fun legacyAad(key: String) = "$legacyPreferences:$key".toByteArray(Charsets.UTF_8)
    private data class Row(val source: Long, val encoding: Int, val body: String)

    private class Database(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        init { setWriteAheadLoggingEnabled(true) }
        override fun onConfigure(db: SQLiteDatabase) {
            db.rawQuery("PRAGMA synchronous=FULL", null).use { it.moveToFirst() }
        }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE pending_deliveries(source_id INTEGER PRIMARY KEY,encoding INTEGER NOT NULL,encrypted_value TEXT)")
            db.execSQL("CREATE INDEX pending_active ON pending_deliveries(source_id DESC) WHERE encrypted_value IS NOT NULL")
            db.execSQL("CREATE TABLE pending_turn_heads(turn_key TEXT PRIMARY KEY NOT NULL,encrypted_value TEXT)")
            db.execSQL("CREATE TABLE pending_legacy_turns(lookup_key TEXT PRIMARY KEY NOT NULL,encrypted_value TEXT NOT NULL)")
            db.execSQL("CREATE TABLE pending_metadata(name TEXT PRIMARY KEY NOT NULL)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = error("Unsupported pending journal migration")
    }
    companion object {
        const val DATABASE_NAME = "galaxyssi_pending_deliveries_v1.db"
        const val LEGACY_PREFERENCES = "galaxyssi_agent_pending_deliveries"
        const val PAGE_SIZE = 32
    }
}
