package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

internal data class AgentConversationPageCursor(
    val pinned: Boolean,
    val updatedAt: Long,
    val id: String
)

internal data class AgentConversationPage(
    val items: List<AgentConversation>,
    val nextCursor: AgentConversationPageCursor?,
    val hasMore: Boolean
)

internal class AgentConversationDatabase(
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
            CREATE TABLE agent_conversations (
                conversation_id TEXT PRIMARY KEY NOT NULL,
                status TEXT NOT NULL,
                pinned INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                latest_message_indexed INTEGER NOT NULL,
                encrypted_payload TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX agent_conversations_order
            ON agent_conversations(status, pinned DESC, updated_at DESC, conversation_id DESC)
            """.trimIndent()
        )
        createLatestMessageIndex(db)
        createMigrationMetadata(db, complete = true)
        createConversationState(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL(
                "ALTER TABLE $TABLE_CONVERSATIONS " +
                    "ADD COLUMN latest_message_indexed INTEGER NOT NULL DEFAULT 0"
            )
            val indexedStates = db.query(
                TABLE_CONVERSATIONS,
                COLUMNS,
                null,
                null,
                null,
                null,
                null
            ).use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        val conversation = decode(cursor) ?: continue
                        add(conversation.id to conversation.latestMessageIndexed)
                    }
                }
            }
            indexedStates.forEach { (conversationId, indexed) ->
                val values = ContentValues().apply {
                    put("latest_message_indexed", if (indexed) 1 else 0)
                }
                db.update(
                    TABLE_CONVERSATIONS,
                    values,
                    "conversation_id = ?",
                    arrayOf(conversationId)
                )
            }
            createLatestMessageIndex(db)
        }
        createMigrationMetadata(db, complete = false)
        if (oldVersion < 4) createConversationState(db)
    }

    @Synchronized
    fun activeConversationId(): String = readableDatabase.query(
        TABLE_CONVERSATION_STATE,
        arrayOf("state_value"),
        "state_key = ?",
        arrayOf(KEY_ACTIVE_CONVERSATION),
        null,
        null,
        null,
        "1"
    ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else "" }

    @Synchronized
    fun setActiveConversationId(conversationId: String) {
        val cleanId = conversationId.trim()
        if (cleanId.isBlank()) {
            clearActiveConversationId()
            return
        }
        val values = ContentValues().apply {
            put("state_key", KEY_ACTIVE_CONVERSATION)
            put("state_value", cleanId)
        }
        check(
            writableDatabase.insertWithOnConflict(
                TABLE_CONVERSATION_STATE,
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE
            ) != -1L
        ) { "Agent conversation selection write failed" }
    }

    @Synchronized
    fun clearActiveConversationId() {
        writableDatabase.delete(
            TABLE_CONVERSATION_STATE,
            "state_key = ?",
            arrayOf(KEY_ACTIVE_CONVERSATION)
        )
    }

    @Synchronized
    fun upsert(conversation: AgentConversation): Boolean = writableDatabase.insertWithOnConflict(
        TABLE_CONVERSATIONS,
        null,
        values(conversation),
        SQLiteDatabase.CONFLICT_REPLACE
    ) != -1L

    @Synchronized
    fun insertIfAbsent(conversation: AgentConversation): Boolean = writableDatabase.insertWithOnConflict(
        TABLE_CONVERSATIONS,
        null,
        values(conversation),
        SQLiteDatabase.CONFLICT_IGNORE
    ) != -1L

    @Synchronized
    fun upsertAll(conversations: Collection<AgentConversation>): Boolean {
        if (conversations.isEmpty()) return true
        val db = writableDatabase
        db.beginTransaction()
        return try {
            val inserted = conversations.all { conversation ->
                db.insertWithOnConflict(
                    TABLE_CONVERSATIONS,
                    null,
                    values(conversation),
                    SQLiteDatabase.CONFLICT_REPLACE
                ) != -1L
            }
            if (inserted) db.setTransactionSuccessful()
            inserted
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun read(conversationId: String): AgentConversation? {
        ensureLegacyRowsMigrated()
        return readableDatabase.query(
            TABLE_CONVERSATIONS,
            COLUMNS,
            "conversation_id = ?",
            arrayOf(conversationId),
            null,
            null,
            null,
            "1"
        ).use { cursor -> if (cursor.moveToFirst()) decode(cursor) else null }
    }

    @Synchronized
    fun firstActive(): AgentConversation? {
        ensureLegacyRowsMigrated()
        return readableDatabase.query(
            TABLE_CONVERSATIONS,
            COLUMNS,
            "status = ?",
            arrayOf(AgentConversationStatus.ACTIVE.name),
            null,
            null,
            ORDER_BY,
            "1"
        ).use { cursor -> if (cursor.moveToFirst()) decode(cursor) else null }
    }

    @Synchronized
    fun readAll(): List<AgentConversation> {
        ensureLegacyRowsMigrated()
        return query(selection = null, selectionArgs = null, limit = null)
    }

    @Synchronized
    fun page(
        status: AgentConversationStatus?,
        cursor: AgentConversationPageCursor?,
        pageSize: Int
    ): AgentConversationPage {
        ensureLegacyRowsMigrated()
        val safePageSize = pageSize.coerceIn(1, MAX_PAGE_SIZE)
        val clauses = mutableListOf<String>()
        val arguments = mutableListOf<String>()
        if (status != null) {
            clauses += "status = ?"
            arguments += status.name
        }
        cursor?.let { value ->
            clauses += """
                (pinned < ? OR
                 (pinned = ? AND updated_at < ?) OR
                 (pinned = ? AND updated_at = ? AND conversation_id < ?))
            """.trimIndent()
            val pinned = if (value.pinned) "1" else "0"
            arguments += listOf(
                pinned,
                pinned,
                value.updatedAt.toString(),
                pinned,
                value.updatedAt.toString(),
                value.id
            )
        }
        val rows = query(
            selection = clauses.takeIf(List<String>::isNotEmpty)?.joinToString(" AND "),
            selectionArgs = arguments.takeIf(List<String>::isNotEmpty)?.toTypedArray(),
            limit = (safePageSize + 1).toString()
        )
        val hasMore = rows.size > safePageSize
        val retained = rows.take(safePageSize)
        val last = retained.lastOrNull()
        return AgentConversationPage(
            items = retained,
            nextCursor = last?.takeIf { hasMore }?.let {
                AgentConversationPageCursor(it.pinned, it.updatedAt, it.id)
            },
            hasMore = hasMore
        )
    }

    @Synchronized
    fun prepareForPaging() {
        rowCipher.preload()
        ensureLegacyRowsMigrated()
    }

    @Synchronized
    fun delete(conversationId: String): AgentConversation? {
        val current = read(conversationId) ?: return null
        writableDatabase.delete(
            TABLE_CONVERSATIONS,
            "conversation_id = ?",
            arrayOf(conversationId)
        )
        return current
    }

    @Synchronized
    fun deleteConversations(conversationIds: Collection<String>): Int {
        val ids = conversationIds.map(String::trim).filter(String::isNotBlank).distinct()
        if (ids.isEmpty()) return 0
        val db = writableDatabase
        db.beginTransaction()
        return try {
            var deleted = 0
            ids.chunked(SQL_DELETE_BATCH_SIZE).forEach { chunk ->
                val placeholders = List(chunk.size) { "?" }.joinToString(",")
                deleted += db.delete(
                    TABLE_CONVERSATIONS,
                    "conversation_id IN ($placeholders)",
                    chunk.toTypedArray()
                )
            }
            db.setTransactionSuccessful()
            deleted
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun replaceAll(conversations: Collection<AgentConversation>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE_CONVERSATIONS, null, null)
            conversations.forEach { conversation ->
                db.insertWithOnConflict(
                    TABLE_CONVERSATIONS,
                    null,
                    values(conversation),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun clear() {
        writableDatabase.delete(TABLE_CONVERSATIONS, null, null)
    }

    @Synchronized
    fun count(status: AgentConversationStatus? = null): Int {
        val selection = status?.let { " WHERE status = ?" }.orEmpty()
        val arguments = status?.let { arrayOf(it.name) }
        return readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM $TABLE_CONVERSATIONS$selection",
            arguments
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getInt(0) else 0 }
    }

    @Synchronized
    fun missingLatestMessageIndex(): List<AgentConversation> {
        ensureLegacyRowsMigrated()
        return query("latest_message_indexed = 0", null, null)
    }

    private fun query(
        selection: String?,
        selectionArgs: Array<String>?,
        limit: String?
    ): List<AgentConversation> = readableDatabase.query(
        TABLE_CONVERSATIONS,
        COLUMNS,
        selection,
        selectionArgs,
        null,
        null,
        ORDER_BY,
        limit
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) decode(cursor)?.let(::add)
        }
    }

    private fun values(conversation: AgentConversation): ContentValues = ContentValues().apply {
        put("conversation_id", conversation.id)
        put("status", conversation.status.name)
        put("pinned", if (conversation.pinned) 1 else 0)
        put("created_at", conversation.createdAt)
        put("updated_at", conversation.updatedAt)
        put("latest_message_indexed", if (conversation.latestMessageIndexed) 1 else 0)
        put(
            "encrypted_payload",
            rowCipher.encrypt(toJson(conversation).toString(), associatedData(conversation.id))
        )
    }

    private fun decode(cursor: Cursor): AgentConversation? {
        val id = cursor.getString(cursor.getColumnIndexOrThrow("conversation_id"))
        val encrypted = cursor.getString(cursor.getColumnIndexOrThrow("encrypted_payload"))
        val raw = rowCipher.decrypt(encrypted, associatedData(id)) ?: return null
        val item = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        return AgentConversation(
            id = id,
            title = item.optString("title", "New session").take(MAX_TITLE_CHARACTERS),
            createdAt = item.optLong("created_at", System.currentTimeMillis()),
            updatedAt = item.optLong("updated_at", System.currentTimeMillis()),
            selectedModelOrAgent = item.optString("selected_model_or_agent", "Automatic"),
            contextPolicy = item.optString("context_policy", "balanced"),
            summary = item.optString("summary"),
            status = runCatching {
                AgentConversationStatus.valueOf(item.optString("status"))
            }.getOrDefault(AgentConversationStatus.ACTIVE),
            pinned = item.optBoolean("pinned"),
            privateMode = item.optBoolean("private_mode"),
            inputTokens = item.optLong("input_tokens"),
            outputTokens = item.optLong("output_tokens"),
            costMicros = item.optLong("cost_micros"),
            createdByAgent = item.optBoolean("created_by_agent"),
            parentConversationId = item.optString("parent_conversation_id"),
            trackingPaused = item.optBoolean("tracking_paused"),
            globalTopicKey = item.optString("global_topic_key").take(MAX_GLOBAL_TOPIC_KEY_CHARACTERS),
            mergedIntoConversationId = item.optString("merged_into_conversation_id"),
            mergedAtMillis = item.optLong("merged_at_millis"),
            contextCompactedThroughMillis = item.optLong("context_compacted_through_millis"),
            contextCompactedThroughEntryId = item.optString("context_compacted_through_entry_id"),
            latestMessageIndexed = item.optBoolean("latest_message_indexed"),
            latestMessageEntryId = item.optString("latest_message_entry_id"),
            latestMessagePreview = item.optString("latest_message_preview").take(MAX_MESSAGE_PREVIEW_CHARACTERS),
            latestMessageTimestampMillis = item.optLong("latest_message_timestamp_millis")
        )
    }

    private fun toJson(conversation: AgentConversation): JSONObject = JSONObject()
        .put("id", conversation.id)
        .put("title", conversation.title)
        .put("created_at", conversation.createdAt)
        .put("updated_at", conversation.updatedAt)
        .put("selected_model_or_agent", conversation.selectedModelOrAgent)
        .put("context_policy", conversation.contextPolicy)
        .put("summary", conversation.summary)
        .put("status", conversation.status.name)
        .put("pinned", conversation.pinned)
        .put("private_mode", conversation.privateMode)
        .put("input_tokens", conversation.inputTokens)
        .put("output_tokens", conversation.outputTokens)
        .put("cost_micros", conversation.costMicros)
        .put("created_by_agent", conversation.createdByAgent)
        .put("parent_conversation_id", conversation.parentConversationId)
        .put("tracking_paused", conversation.trackingPaused)
        .put("global_topic_key", conversation.globalTopicKey)
        .put("merged_into_conversation_id", conversation.mergedIntoConversationId)
        .put("merged_at_millis", conversation.mergedAtMillis)
        .put("context_compacted_through_millis", conversation.contextCompactedThroughMillis)
        .put("context_compacted_through_entry_id", conversation.contextCompactedThroughEntryId)
        .put("latest_message_indexed", conversation.latestMessageIndexed)
        .put("latest_message_entry_id", conversation.latestMessageEntryId)
        .put("latest_message_preview", conversation.latestMessagePreview)
        .put("latest_message_timestamp_millis", conversation.latestMessageTimestampMillis)

    private fun associatedData(conversationId: String): ByteArray =
        "$databaseName:$conversationId".toByteArray(Charsets.UTF_8)

    @Synchronized
    private fun ensureLegacyRowsMigrated() {
        if (legacyRowsMigrated) return
        val db = writableDatabase
        if (migrationMetadataComplete(db)) {
            legacyRowsMigrated = true
            return
        }
        val updates = db.query(
            TABLE_CONVERSATIONS,
            arrayOf("conversation_id", "encrypted_payload"),
            "encrypted_payload LIKE ?",
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
                    val values = ContentValues().apply { put("encrypted_payload", encrypted) }
                    check(db.update(TABLE_CONVERSATIONS, values, "conversation_id = ?", arrayOf(id)) == 1)
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
        ) { "Agent conversation migration metadata write failed" }
    }

    private fun createLatestMessageIndex(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS agent_conversations_latest_message
            ON agent_conversations(latest_message_indexed)
            """.trimIndent()
        )
    }

    private fun createConversationState(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_CONVERSATION_STATE (
                state_key TEXT PRIMARY KEY NOT NULL,
                state_value TEXT NOT NULL
            )
            """.trimIndent()
        )
    }

    internal companion object {
        const val DATABASE_NAME = "galaxyssi_agent_conversations_v2.db"
        const val STORAGE_CIPHER_NAMESPACE = DATABASE_NAME
        const val DATABASE_VERSION = 4
        const val TABLE_CONVERSATIONS = "agent_conversations"
        const val TABLE_CONVERSATION_STATE = "agent_conversation_state"
        const val TABLE_ROW_STORAGE_METADATA = "row_storage_metadata"
        const val KEY_LEGACY_ROWS_MIGRATED = "legacy_rows_migrated"
        const val KEY_ACTIVE_CONVERSATION = "active_conversation"
        const val ORDER_BY = "pinned DESC, updated_at DESC, conversation_id DESC"
        const val MAX_PAGE_SIZE = 500
        const val MAX_TITLE_CHARACTERS = 72
        const val MAX_GLOBAL_TOPIC_KEY_CHARACTERS = 80
        const val MAX_MESSAGE_PREVIEW_CHARACTERS = 500
        const val SQL_DELETE_BATCH_SIZE = 400
        val COLUMNS = arrayOf("conversation_id", "encrypted_payload")
    }
}
