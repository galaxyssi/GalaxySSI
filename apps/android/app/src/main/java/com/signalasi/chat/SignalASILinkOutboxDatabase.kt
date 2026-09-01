package com.signalasi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

internal class SignalASILinkOutboxDatabase(
    context: Context,
    private val databaseName: String = DATABASE_NAME
) : SQLiteOpenHelper(context.applicationContext, databaseName, null, DATABASE_VERSION) {
    private val rowCipher = AgentRowStorageCipher(context.applicationContext, databaseName)
    @Volatile private var legacyRowsMigrated = false

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE outbox_messages (
                message_id TEXT PRIMARY KEY NOT NULL,
                status TEXT NOT NULL,
                attempts INTEGER NOT NULL,
                next_attempt_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                requires_validated_network INTEGER NOT NULL,
                blocked_dependency_count INTEGER NOT NULL,
                client_source_message_id INTEGER NOT NULL,
                attachment_transfer_id TEXT NOT NULL,
                encrypted_item TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX outbox_retry_schedule
            ON outbox_messages(blocked_dependency_count, requires_validated_network, next_attempt_at)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX outbox_client_source
            ON outbox_messages(client_source_message_id)
            """.trimIndent()
        )
        createMigrationMetadata(db, complete = true)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        createMigrationMetadata(db, complete = false)
    }

    @Synchronized
    fun insert(item: JSONObject): Boolean {
        val messageId = item.optString(KEY_MESSAGE_ID)
        if (messageId.isBlank()) return false
        return writableDatabase.insertWithOnConflict(
            TABLE_OUTBOX,
            null,
            values(item),
            SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    @Synchronized
    fun update(messageId: String, mutate: (JSONObject) -> Unit): Boolean {
        val item = read(messageId) ?: return false
        mutate(item)
        return writableDatabase.update(
            TABLE_OUTBOX,
            values(item),
            "message_id = ?",
            arrayOf(messageId)
        ) == 1
    }

    @Synchronized
    fun delete(messageId: String): JSONObject? {
        val item = read(messageId) ?: return null
        writableDatabase.delete(TABLE_OUTBOX, "message_id = ?", arrayOf(messageId))
        return item
    }

    @Synchronized
    fun deleteByClientSourceMessageIds(
        sourceMessageIds: Collection<Long>,
        beforeDelete: (JSONObject) -> Unit = {}
    ): Int {
        ensureLegacyRowsMigrated()
        val validIds = sourceMessageIds.asSequence()
            .filter { it > 0L }
            .distinct()
            .toList()
        if (validIds.isEmpty()) return 0
        val db = writableDatabase
        var removed = 0
        db.beginTransaction()
        try {
            validIds.chunked(SQL_BIND_BATCH_SIZE).forEach { batch ->
                val placeholders = List(batch.size) { "?" }.joinToString(",")
                val arguments = batch.map(Long::toString).toTypedArray()
                db.query(
                    TABLE_OUTBOX,
                    arrayOf("message_id", "encrypted_item"),
                    "client_source_message_id IN ($placeholders)",
                    arguments,
                    null,
                    null,
                    null
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        decode(cursor.getString(0), cursor.getString(1))?.let(beforeDelete)
                    }
                }
                removed += db.delete(
                    TABLE_OUTBOX,
                    "client_source_message_id IN ($placeholders)",
                    arguments
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        if (validIds.size >= BULK_DELETE_CHECKPOINT_THRESHOLD) {
            db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use(Cursor::moveToFirst)
        }
        return removed
    }

    @Synchronized
    fun contains(messageId: String): Boolean = readableDatabase.query(
        TABLE_OUTBOX,
        arrayOf("message_id"),
        "message_id = ?",
        arrayOf(messageId),
        null,
        null,
        null,
        "1"
    ).use(Cursor::moveToFirst)

    @Synchronized
    fun hasClientSourceMessageId(sourceMessageId: Long): Boolean {
        if (sourceMessageId <= 0L) return false
        return readableDatabase.query(
            TABLE_OUTBOX,
            arrayOf("message_id"),
            "client_source_message_id = ?",
            arrayOf(sourceMessageId.toString()),
            null,
            null,
            null,
            "1"
        ).use(Cursor::moveToFirst)
    }

    @Synchronized
    fun readAll(): JSONArray {
        ensureLegacyRowsMigrated()
        return queryItems(null, null, "created_at ASC, rowid ASC")
    }

    @Synchronized
    fun retryCandidates(
        nowMillis: Long,
        allowValidatedNetworkMessages: Boolean,
        maxAttempts: Int,
        attachmentMaxAttempts: Int,
        limit: Int
    ): JSONArray {
        ensureLegacyRowsMigrated()
        val selection = buildString {
            append("blocked_dependency_count = 0 AND next_attempt_at <= ?")
            if (!allowValidatedNetworkMessages) append(" AND requires_validated_network = 0")
            if (maxAttempts < Int.MAX_VALUE) {
                append(
                    " AND ((attachment_transfer_id = '' AND attempts < ?)" +
                        " OR (attachment_transfer_id <> '' AND attempts < ?))"
                )
            }
        }
        val arguments = buildList {
            add(nowMillis.toString())
            if (maxAttempts < Int.MAX_VALUE) {
                add(maxAttempts.toString())
                add(attachmentMaxAttempts.toString())
            }
        }.toTypedArray()
        val candidateLimit = if (limit == Int.MAX_VALUE) null else (limit * ROUTE_FAIRNESS_LOOKAHEAD)
            .coerceAtLeast(limit)
            .toString()
        return queryItems(selection, arguments, "created_at ASC, rowid ASC", candidateLimit)
    }

    @Synchronized
    fun exhausted(
        maxAttempts: Int,
        attachmentMaxAttempts: Int,
        nowMillis: Long
    ): JSONArray {
        ensureLegacyRowsMigrated()
        return queryItems(
            selection =
                "next_attempt_at <= ? AND ((attachment_transfer_id = '' AND attempts >= ?)" +
                    " OR (attachment_transfer_id <> '' AND attempts >= ?))",
            selectionArgs = arrayOf(
                nowMillis.toString(),
                maxAttempts.toString(),
                attachmentMaxAttempts.toString()
            ),
            orderBy = "created_at ASC, rowid ASC"
        )
    }

    @Synchronized
    fun nextRetryAt(allowValidatedNetworkMessages: Boolean): Long? {
        val selection = buildString {
            append("blocked_dependency_count = 0")
            if (!allowValidatedNetworkMessages) append(" AND requires_validated_network = 0")
        }
        return readableDatabase.rawQuery(
            "SELECT MIN(next_attempt_at) FROM $TABLE_OUTBOX WHERE $selection",
            null
        ).use { cursor ->
            cursor.takeIf { it.moveToFirst() && !it.isNull(0) }?.getLong(0)
        }
    }

    @Synchronized
    fun makePendingImmediatelyRetryable(nowMillis: Long) {
        val values = ContentValues().apply {
            put("status", "queued")
            put("next_attempt_at", nowMillis)
        }
        writableDatabase.update(
            TABLE_OUTBOX,
            values,
            "next_attempt_at > ?",
            arrayOf(nowMillis.toString())
        )
    }

    @Synchronized
    fun replaceAll(items: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE_OUTBOX, null, null)
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                if (item.optString(KEY_MESSAGE_ID).isBlank()) continue
                db.insertWithOnConflict(TABLE_OUTBOX, null, values(item), SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun clear() {
        writableDatabase.delete(TABLE_OUTBOX, null, null)
    }

    @Synchronized
    fun count(): Int = readableDatabase.rawQuery(
        "SELECT COUNT(*) FROM $TABLE_OUTBOX",
        null
    ).use { cursor -> if (cursor.moveToFirst()) cursor.getInt(0) else 0 }

    private fun read(messageId: String): JSONObject? {
        ensureLegacyRowsMigrated()
        return readableDatabase.query(
            TABLE_OUTBOX,
            arrayOf("encrypted_item"),
            "message_id = ?",
            arrayOf(messageId),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else decode(messageId, cursor.getString(0))
        }
    }

    private fun queryItems(
        selection: String?,
        selectionArgs: Array<String>?,
        orderBy: String,
        limit: String? = null
    ): JSONArray {
        val items = JSONArray()
        readableDatabase.query(
            TABLE_OUTBOX,
            arrayOf("message_id", "encrypted_item"),
            selection,
            selectionArgs,
            null,
            null,
            orderBy,
            limit
        ).use { cursor ->
            while (cursor.moveToNext()) {
                decode(cursor.getString(0), cursor.getString(1))?.let(items::put)
            }
        }
        return items
    }

    private fun values(item: JSONObject): ContentValues {
        val messageId = item.getString(KEY_MESSAGE_ID)
        val dependencies = item.optJSONArray(KEY_BLOCKED_DEPENDENCIES)?.length() ?: 0
        return ContentValues().apply {
            put("message_id", messageId)
            put("status", item.optString("status", "queued"))
            put("attempts", item.optInt("attempts", 0))
            put("next_attempt_at", item.optLong("next_attempt_at", System.currentTimeMillis()))
            put("created_at", item.optLong("created_at", System.currentTimeMillis()))
            put("requires_validated_network", if (item.optBoolean("requires_validated_network")) 1 else 0)
            put("blocked_dependency_count", dependencies)
            put("client_source_message_id", item.optLong("client_source_message_id", 0L))
            put("attachment_transfer_id", item.optString(KEY_ATTACHMENT_TRANSFER_ID))
            put("encrypted_item", rowCipher.encrypt(item.toString(), associatedData(messageId)))
        }
    }

    private fun decode(messageId: String, encrypted: String): JSONObject? =
        rowCipher.decrypt(encrypted, associatedData(messageId))
            ?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun associatedData(messageId: String): ByteArray =
        "$databaseName:$messageId".toByteArray(Charsets.UTF_8)

    @Synchronized
    private fun ensureLegacyRowsMigrated() {
        if (legacyRowsMigrated) return
        val db = writableDatabase
        if (migrationMetadataComplete(db)) {
            legacyRowsMigrated = true
            return
        }
        val updates = db.query(
            TABLE_OUTBOX,
            arrayOf("message_id", "encrypted_item"),
            "encrypted_item LIKE ?",
            arrayOf("enc:v1:%"),
            null,
            null,
            null
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    rowCipher.reencryptLegacy(cursor.getString(1), associatedData(id))
                        ?.let { encrypted -> add(id to encrypted) }
                }
            }
        }
        if (updates.isNotEmpty()) {
            db.beginTransaction()
            try {
                updates.forEach { (id, encrypted) ->
                    val values = ContentValues().apply { put("encrypted_item", encrypted) }
                    check(db.update(TABLE_OUTBOX, values, "message_id = ?", arrayOf(id)) == 1)
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }
        markMigrationMetadataComplete(db)
        legacyRowsMigrated = true
    }

    private fun createMigrationMetadata(db: SQLiteDatabase, complete: Boolean) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS row_storage_metadata (
                metadata_key TEXT PRIMARY KEY NOT NULL,
                metadata_value INTEGER NOT NULL
            )
            """.trimIndent()
        )
        val values = ContentValues().apply {
            put("metadata_key", KEY_LEGACY_ROWS_MIGRATED)
            put("metadata_value", if (complete) 1 else 0)
        }
        db.insertWithOnConflict(
            TABLE_ROW_STORAGE_METADATA,
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        )
    }

    private fun migrationMetadataComplete(db: SQLiteDatabase): Boolean = db.query(
        TABLE_ROW_STORAGE_METADATA,
        arrayOf("metadata_value"),
        "metadata_key = ?",
        arrayOf(KEY_LEGACY_ROWS_MIGRATED),
        null,
        null,
        null,
        "1"
    ).use { cursor -> cursor.moveToFirst() && cursor.getInt(0) == 1 }

    private fun markMigrationMetadataComplete(db: SQLiteDatabase) {
        val values = ContentValues().apply {
            put("metadata_key", KEY_LEGACY_ROWS_MIGRATED)
            put("metadata_value", 1)
        }
        check(
            db.insertWithOnConflict(
                TABLE_ROW_STORAGE_METADATA,
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE
            ) != -1L
        ) { "Link outbox migration metadata write failed" }
    }

    private companion object {
        const val DATABASE_NAME = "opaque_link_outbox_v3.db"
        const val DATABASE_VERSION = 2
        const val SQL_BIND_BATCH_SIZE = 500
        const val BULK_DELETE_CHECKPOINT_THRESHOLD = 500
        const val TABLE_OUTBOX = "outbox_messages"
        const val TABLE_ROW_STORAGE_METADATA = "row_storage_metadata"
        const val KEY_LEGACY_ROWS_MIGRATED = "legacy_rows_migrated"
        const val KEY_MESSAGE_ID = "message_id"
        const val KEY_BLOCKED_DEPENDENCIES = "blocked_by_attachment_transfers"
        const val KEY_ATTACHMENT_TRANSFER_ID = "attachment_transfer_id"
        const val ROUTE_FAIRNESS_LOOKAHEAD = 8
    }
}
