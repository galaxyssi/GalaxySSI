package com.signalasi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject
import java.security.MessageDigest

internal data class AgentTranscriptPage(
    val entries: List<AgentTranscriptEntry>,
    val nextBeforeSequence: Long?,
    val hasMore: Boolean,
    val newestSequence: Long?
)

internal data class AgentTranscriptDelta(
    val entries: List<AgentTranscriptEntry>,
    val newestSequence: Long?,
    val hasMore: Boolean
)

internal data class AgentTranscriptContentPage(
    val entryId: String,
    val field: String,
    val offset: Int,
    val nextOffset: Int,
    val totalChunks: Int,
    val totalLength: Int,
    val sha256: String,
    val chunks: List<String>,
    val done: Boolean
)

internal class AgentTranscriptWindow {
    var conversationId: String = ""
        private set
    var entries: List<AgentTranscriptEntry> = emptyList()
        private set
    var nextBeforeSequence: Long? = null
        private set
    var newestSequence: Long? = null
        private set
    var hasMore: Boolean = false
        private set

    fun reset(conversationId: String = "") {
        this.conversationId = conversationId
        entries = emptyList()
        nextBeforeSequence = null
        newestSequence = null
        hasMore = false
    }

    fun replace(conversationId: String, page: AgentTranscriptPage) {
        this.conversationId = conversationId
        entries = page.entries.distinctBy(AgentTranscriptEntry::id)
        nextBeforeSequence = page.nextBeforeSequence
        newestSequence = page.newestSequence
        hasMore = page.hasMore
    }

    fun appendNewer(conversationId: String, delta: AgentTranscriptDelta): Int {
        if (this.conversationId != conversationId) {
            reset(conversationId)
        }
        if (delta.entries.isEmpty()) {
            newestSequence = delta.newestSequence ?: newestSequence
            return 0
        }
        val incomingIds = delta.entries.mapTo(mutableSetOf(), AgentTranscriptEntry::id)
        val incomingDedupeKeys = delta.entries.asSequence()
            .map(AgentTranscriptEntry::dedupeKey)
            .filter(String::isNotBlank)
            .toSet()
        val retained = entries.filterNot { entry ->
            entry.id in incomingIds ||
                (entry.dedupeKey.isNotBlank() && entry.dedupeKey in incomingDedupeKeys)
        }
        entries = retained + delta.entries
        newestSequence = delta.newestSequence ?: newestSequence
        return delta.entries.size
    }

    fun prependOlder(conversationId: String, page: AgentTranscriptPage): Int {
        if (this.conversationId != conversationId || entries.isEmpty()) {
            replace(conversationId, page)
            return entries.size
        }
        val loadedIds = entries.mapTo(mutableSetOf(), AgentTranscriptEntry::id)
        val older = page.entries.filterNot { it.id in loadedIds }
        entries = older + entries
        nextBeforeSequence = page.nextBeforeSequence
        newestSequence = newestSequence ?: page.newestSequence
        hasMore = page.hasMore
        return older.size
    }

    fun remove(entryId: String): Boolean {
        val retained = entries.filterNot { it.id == entryId }
        if (retained.size == entries.size) return false
        entries = retained
        return true
    }
}

internal class AgentTranscriptEntryDatabase(
    context: Context,
    databaseName: String = DATABASE_NAME
) : SQLiteOpenHelper(context.applicationContext, databaseName, null, DATABASE_VERSION) {
    private val decodeCache = AgentTranscriptDecodeCache()

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE transcript_entries (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_id TEXT UNIQUE NOT NULL,
                conversation_id TEXT NOT NULL,
                turn_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                dedupe_hash TEXT NOT NULL,
                timestamp_millis INTEGER NOT NULL,
                encrypted_payload TEXT NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX transcript_entries_conversation_order
            ON transcript_entries(conversation_id, timestamp_millis, sequence)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX transcript_entries_turn
            ON transcript_entries(turn_id, sequence)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX transcript_entries_task
            ON transcript_entries(task_id, sequence)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX transcript_entries_dedupe
            ON transcript_entries(conversation_id, dedupe_hash)
            """.trimIndent()
        )
        createChunkStorage(db)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createChunkStorage(db)
    }

    @Synchronized
    fun insert(entry: AgentTranscriptEntry): Boolean {
        val db = writableDatabase
        db.beginTransaction()
        return try {
            val inserted = insertEntry(db, entry) != -1L
            if (inserted) db.setTransactionSuccessful()
            inserted
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun replace(previousEntryId: String, entry: AgentTranscriptEntry): Boolean {
        val db = writableDatabase
        db.beginTransaction()
        return try {
            db.delete(TABLE_ENTRIES, "entry_id = ?", arrayOf(previousEntryId))
            val inserted = insertEntry(db, entry) != -1L
            if (inserted) {
                db.setTransactionSuccessful()
                decodeCache.remove(previousEntryId)
            }
            inserted
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun replaceAll(entries: List<AgentTranscriptEntry>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(TABLE_ENTRIES, null, null)
            entries.forEach { entry ->
                check(insertEntry(db, entry) != -1L) { "Agent transcript entry write failed" }
            }
            db.setTransactionSuccessful()
            decodeCache.clear()
        } finally {
            db.endTransaction()
        }
    }

    fun listAll(): List<AgentTranscriptEntry> =
        readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            null,
            null,
            null,
            null,
            "timestamp_millis ASC, sequence ASC"
        ).use(::decodeEntries).map(::hydrateEntry)

    fun listConversation(conversationId: String): List<AgentTranscriptEntry> =
        readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            "conversation_id = ?",
            arrayOf(conversationId),
            null,
            null,
            "timestamp_millis ASC, sequence ASC"
        ).use(::decodeEntries).map(::hydrateEntry)

    fun listConversationAfterEntry(
        conversationId: String,
        entryId: String
    ): List<AgentTranscriptEntry>? {
        val cleanConversationId = conversationId.trim()
        val cleanEntryId = entryId.trim()
        if (cleanConversationId.isBlank()) return emptyList()
        if (cleanEntryId.isBlank()) return null
        val cursorSequence = readableDatabase.query(
            TABLE_ENTRIES,
            arrayOf("sequence"),
            "conversation_id = ? AND entry_id = ?",
            arrayOf(cleanConversationId, cleanEntryId),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getLong(0) else null
        } ?: return null
        return readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            "conversation_id = ? AND sequence > ?",
            arrayOf(cleanConversationId, cursorSequence.toString()),
            null,
            null,
            "sequence ASC"
        ).use(::decodeEntries).map(::hydrateEntry)
    }

    fun listConversationPage(
        conversationId: String,
        beforeSequenceExclusive: Long? = null,
        pageSize: Int = DEFAULT_PAGE_SIZE
    ): AgentTranscriptPage {
        val safePageSize = pageSize.coerceIn(1, MAX_PAGE_SIZE)
        val selection = buildString {
            append("conversation_id = ?")
            if (beforeSequenceExclusive != null) append(" AND sequence < ?")
        }
        val arguments = buildList {
            add(conversationId)
            beforeSequenceExclusive?.let { add(it.toString()) }
        }.toTypedArray()
        val rows = readableDatabase.query(
            TABLE_ENTRIES,
            PAGE_COLUMNS,
            selection,
            arguments,
            null,
            null,
            "sequence DESC",
            (safePageSize + 1).toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.getLong(cursor.getColumnIndexOrThrow("sequence")) to decodeEntry(cursor))
                }
            }
        }
        val hasMore = rows.size > safePageSize
        val retained = rows.take(safePageSize)
        return AgentTranscriptPage(
            entries = retained.asReversed().map { it.second },
            nextBeforeSequence = retained.lastOrNull()?.first?.takeIf { hasMore },
            hasMore = hasMore,
            newestSequence = retained.firstOrNull()?.first
        )
    }

    fun listConversationAfter(
        conversationId: String,
        afterSequenceExclusive: Long,
        pageSize: Int = DEFAULT_PAGE_SIZE
    ): AgentTranscriptDelta {
        val safePageSize = pageSize.coerceIn(1, MAX_PAGE_SIZE)
        val rows = readableDatabase.query(
            TABLE_ENTRIES,
            PAGE_COLUMNS,
            "conversation_id = ? AND sequence > ?",
            arrayOf(conversationId, afterSequenceExclusive.toString()),
            null,
            null,
            "sequence ASC",
            (safePageSize + 1).toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(cursor.getLong(cursor.getColumnIndexOrThrow("sequence")) to decodeEntry(cursor))
                }
            }
        }
        val hasMore = rows.size > safePageSize
        val retained = rows.take(safePageSize)
        return AgentTranscriptDelta(
            entries = retained.map { it.second },
            newestSequence = retained.lastOrNull()?.first ?: afterSequenceExclusive,
            hasMore = hasMore
        )
    }

    fun listTurn(turnId: String): List<AgentTranscriptEntry> =
        readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            "turn_id = ?",
            arrayOf(turnId),
            null,
            null,
            "sequence ASC"
        ).use(::decodeEntries).map(::hydrateEntry)

    fun listTask(taskId: String): List<AgentTranscriptEntry> =
        readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            "task_id = ?",
            arrayOf(taskId),
            null,
            null,
            "sequence ASC"
        ).use(::decodeEntries).map(::hydrateEntry)

    fun findById(entryId: String): AgentTranscriptEntry? =
        querySingle("entry_id = ?", arrayOf(entryId))

    fun findByDedupeKey(conversationId: String, dedupeKey: String): AgentTranscriptEntry? {
        if (dedupeKey.isBlank()) return null
        return querySingle(
            "conversation_id = ? AND dedupe_hash = ?",
            arrayOf(conversationId, digest(dedupeKey))
        )
    }

    fun textChunkPage(
        entryId: String,
        offset: Int = 0,
        pageSize: Int = 2
    ): AgentTranscriptContentPage? {
        val cleanEntryId = entryId.trim()
        if (cleanEntryId.isBlank()) return null
        val entry = queryStored("entry_id = ?", arrayOf(cleanEntryId)) ?: return null
        val safeOffset = offset.coerceAtLeast(0)
        val safePageSize = pageSize.coerceIn(1, MAX_CONTENT_PAGE_CHUNKS)
        if (entry.textChunkCount <= 0) {
            val chunks = if (safeOffset == 0 && entry.text.isNotEmpty()) {
                listOf(entry.text)
            } else {
                emptyList()
            }
            return AgentTranscriptContentPage(
                entryId = cleanEntryId,
                field = FIELD_TEXT,
                offset = safeOffset,
                nextOffset = safeOffset + chunks.size,
                totalChunks = if (entry.text.isEmpty()) 0 else 1,
                totalLength = entry.text.length,
                sha256 = AgentLargeOutputPolicy.digest(entry.text),
                chunks = chunks,
                done = true
            )
        }
        val chunks = readableDatabase.query(
            TABLE_CHUNKS,
            arrayOf("chunk_index", "encrypted_chunk", "char_count", "chunk_sha256"),
            "entry_id = ? AND field_name = ? AND chunk_index >= ?",
            arrayOf(cleanEntryId, FIELD_TEXT, safeOffset.toString()),
            null,
            null,
            "chunk_index ASC",
            safePageSize.toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val index = cursor.getInt(0)
                    check(index == safeOffset + size) {
                        "Agent transcript chunk order mismatch"
                    }
                    val value = AgentStorageCipher.decrypt(
                        cursor.getString(1),
                        chunkAssociatedData(cleanEntryId, FIELD_TEXT, index)
                    ) ?: error("Agent transcript chunk could not be decrypted")
                    check(value.length == cursor.getInt(2)) {
                        "Agent transcript chunk length mismatch"
                    }
                    check(AgentLargeOutputPolicy.digest(value) == cursor.getString(3)) {
                        "Agent transcript chunk digest mismatch"
                    }
                    add(value)
                }
            }
        }
        val nextOffset = safeOffset + chunks.size
        return AgentTranscriptContentPage(
            entryId = cleanEntryId,
            field = FIELD_TEXT,
            offset = safeOffset,
            nextOffset = nextOffset,
            totalChunks = entry.textChunkCount,
            totalLength = entry.textLength,
            sha256 = entry.textSha256,
            chunks = chunks,
            done = nextOffset >= entry.textChunkCount
        )
    }

    fun conversationIdForTurn(turnId: String): String? =
        scalarId("turn_id = ?", arrayOf(turnId), "conversation_id")

    fun conversationIdForTask(taskId: String): String? =
        scalarId("task_id = ?", arrayOf(taskId), "conversation_id")

    fun turnIdForTask(taskId: String): String? =
        scalarId("task_id = ? AND turn_id != ''", arrayOf(taskId), "turn_id")

    fun conversationIdsWithEntries(): Set<String> =
        readableDatabase.query(
            true,
            TABLE_ENTRIES,
            arrayOf("conversation_id"),
            null,
            null,
            null,
            null,
            null,
            null
        ).use { cursor ->
            buildSet {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }

    @Synchronized
    fun deleteById(entryId: String): Boolean {
        val deleted = writableDatabase.delete(TABLE_ENTRIES, "entry_id = ?", arrayOf(entryId)) > 0
        if (deleted) decodeCache.remove(entryId)
        return deleted
    }

    @Synchronized
    fun deleteEntries(entryIds: Collection<String>): Int {
        if (entryIds.isEmpty()) return 0
        val db = writableDatabase
        db.beginTransaction()
        return try {
            var removed = 0
            entryIds.forEach { entryId ->
                removed += db.delete(TABLE_ENTRIES, "entry_id = ?", arrayOf(entryId))
            }
            db.setTransactionSuccessful()
            entryIds.forEach(decodeCache::remove)
            removed
        } finally {
            db.endTransaction()
        }
    }

    @Synchronized
    fun deleteConversation(conversationId: String): Int {
        val deleted = writableDatabase.delete(TABLE_ENTRIES, "conversation_id = ?", arrayOf(conversationId))
        if (deleted > 0) decodeCache.clear()
        return deleted
    }

    @Synchronized
    fun clear() {
        writableDatabase.delete(TABLE_ENTRIES, null, null)
        decodeCache.clear()
    }

    @Synchronized
    fun clearRuntimeDecodeCache() {
        decodeCache.clear()
    }

    private fun querySingle(selection: String, arguments: Array<String>): AgentTranscriptEntry? =
        queryStored(selection, arguments)?.let(::hydrateEntry)

    private fun queryStored(
        selection: String,
        arguments: Array<String>
    ): AgentTranscriptEntry? =
        readableDatabase.query(
            TABLE_ENTRIES,
            PAYLOAD_COLUMNS,
            selection,
            arguments,
            null,
            null,
            "sequence DESC",
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) decodeEntry(cursor) else null
        }

    private fun scalarId(selection: String, arguments: Array<String>, column: String): String? =
        readableDatabase.query(
            TABLE_ENTRIES,
            arrayOf(column),
            selection,
            arguments,
            null,
            null,
            "sequence DESC",
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0).takeIf(String::isNotBlank) else null
        }

    private fun insertEntry(db: SQLiteDatabase, entry: AgentTranscriptEntry): Long {
        val text = AgentLargeOutputPolicy.prepare(entry.text, includePreview = true)
        val richOutput = AgentLargeOutputPolicy.prepare(
            entry.richOutputJson,
            includePreview = false
        )
        val storedEntry = entry.copy(
            text = text.storedValue,
            richOutputJson = richOutput.storedValue,
            textChunkCount = text.chunkCount,
            textLength = text.totalLength,
            textSha256 = text.sha256,
            richOutputChunkCount = richOutput.chunkCount,
            richOutputLength = richOutput.totalLength,
            richOutputSha256 = richOutput.sha256
        )
        val values = ContentValues().apply {
            put("entry_id", entry.id)
            put("conversation_id", entry.conversationId)
            put("turn_id", entry.turnId)
            put("task_id", entry.taskId)
            put("dedupe_hash", entry.dedupeKey.takeIf(String::isNotBlank)?.let(::digest).orEmpty())
            put("timestamp_millis", entry.timestampMillis)
            put("encrypted_payload", encode(storedEntry))
        }
        val rowId = db.insertWithOnConflict(
            TABLE_ENTRIES,
            null,
            values,
            SQLiteDatabase.CONFLICT_ABORT
        )
        if (rowId == -1L) return rowId
        writeChunks(db, entry.id, FIELD_TEXT, text.chunks)
        writeChunks(db, entry.id, FIELD_RICH_OUTPUT, richOutput.chunks)
        return rowId
    }

    private fun decodeEntries(cursor: Cursor): List<AgentTranscriptEntry> = buildList {
        while (cursor.moveToNext()) add(decodeEntry(cursor))
    }

    private fun decodeEntry(cursor: Cursor): AgentTranscriptEntry {
        val entryId = cursor.getString(cursor.getColumnIndexOrThrow("entry_id"))
        val encrypted = cursor.getString(cursor.getColumnIndexOrThrow("encrypted_payload"))
        decodeCache.get(entryId, encrypted)?.let { return it }
        val raw = AgentStorageCipher.decrypt(encrypted, associatedData(entryId))
            ?: error("Agent transcript entry could not be decrypted")
        val item = JSONObject(raw)
        return AgentTranscriptEntry(
            id = item.optString("id", entryId),
            role = runCatching { AgentTranscriptRole.valueOf(item.optString("role")) }
                .getOrDefault(AgentTranscriptRole.ASSISTANT),
            text = item.optString("text"),
            timestampMillis = item.optLong("timestamp_millis"),
            dedupeKey = item.optString("dedupe_key"),
            conversationId = item.optString("conversation_id"),
            turnId = item.optString("turn_id"),
            taskId = item.optString("task_id"),
            richOutputJson = AgentRichContentCodec.normalize(item.optString("rich_output")),
            sourceConversationId = item.optString("source_conversation_id"),
            sourceConversationTitle = item.optString("source_conversation_title"),
            sourceEntryId = item.optString("source_entry_id"),
            textChunkCount = item.optInt("text_chunk_count"),
            textLength = item.optInt("text_length"),
            textSha256 = item.optString("text_sha256"),
            richOutputChunkCount = item.optInt("rich_output_chunk_count"),
            richOutputLength = item.optInt("rich_output_length"),
            richOutputSha256 = item.optString("rich_output_sha256")
        ).also { entry -> decodeCache.put(entryId, encrypted, entry) }
    }

    private fun hydrateEntry(entry: AgentTranscriptEntry): AgentTranscriptEntry {
        if (!AgentLargeOutputPolicy.hasDeferredContent(entry)) return entry
        val text = if (entry.textChunkCount > 0) {
            readChunks(
                entryId = entry.id,
                field = FIELD_TEXT,
                expectedCount = entry.textChunkCount,
                expectedLength = entry.textLength,
                expectedSha256 = entry.textSha256
            )
        } else {
            entry.text
        }
        val richOutput = if (entry.richOutputChunkCount > 0) {
            readChunks(
                entryId = entry.id,
                field = FIELD_RICH_OUTPUT,
                expectedCount = entry.richOutputChunkCount,
                expectedLength = entry.richOutputLength,
                expectedSha256 = entry.richOutputSha256
            )
        } else {
            entry.richOutputJson
        }
        return entry.copy(
            text = text,
            richOutputJson = AgentRichContentCodec.normalize(richOutput)
        )
    }

    private fun encode(entry: AgentTranscriptEntry): String {
        val raw = JSONObject()
            .put("id", entry.id)
            .put("role", entry.role.name)
            .put("text", entry.text)
            .put("timestamp_millis", entry.timestampMillis)
            .put("dedupe_key", entry.dedupeKey)
            .put("conversation_id", entry.conversationId)
            .put("turn_id", entry.turnId)
            .put("task_id", entry.taskId)
            .put("rich_output", entry.richOutputJson)
            .put("source_conversation_id", entry.sourceConversationId)
            .put("source_conversation_title", entry.sourceConversationTitle)
            .put("source_entry_id", entry.sourceEntryId)
            .put("text_chunk_count", entry.textChunkCount)
            .put("text_length", entry.textLength)
            .put("text_sha256", entry.textSha256)
            .put("rich_output_chunk_count", entry.richOutputChunkCount)
            .put("rich_output_length", entry.richOutputLength)
            .put("rich_output_sha256", entry.richOutputSha256)
            .toString()
        return AgentStorageCipher.encrypt(raw, associatedData(entry.id))
    }

    private fun writeChunks(
        db: SQLiteDatabase,
        entryId: String,
        field: String,
        chunks: List<String>
    ) {
        chunks.forEachIndexed { index, chunk ->
            val values = ContentValues().apply {
                put("entry_id", entryId)
                put("field_name", field)
                put("chunk_index", index)
                put(
                    "encrypted_chunk",
                    AgentStorageCipher.encrypt(
                        chunk,
                        chunkAssociatedData(entryId, field, index)
                    )
                )
                put("char_count", chunk.length)
                put("chunk_sha256", AgentLargeOutputPolicy.digest(chunk))
            }
            db.insertOrThrow(TABLE_CHUNKS, null, values)
        }
    }

    private fun readChunks(
        entryId: String,
        field: String,
        expectedCount: Int,
        expectedLength: Int,
        expectedSha256: String
    ): String {
        val chunks = readableDatabase.query(
            TABLE_CHUNKS,
            arrayOf("chunk_index", "encrypted_chunk", "char_count", "chunk_sha256"),
            "entry_id = ? AND field_name = ?",
            arrayOf(entryId, field),
            null,
            null,
            "chunk_index ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val index = cursor.getInt(0)
                    check(index == size) { "Agent transcript chunk order mismatch" }
                    val value = AgentStorageCipher.decrypt(
                        cursor.getString(1),
                        chunkAssociatedData(entryId, field, index)
                    ) ?: error("Agent transcript chunk could not be decrypted")
                    check(value.length == cursor.getInt(2)) {
                        "Agent transcript chunk length mismatch"
                    }
                    check(AgentLargeOutputPolicy.digest(value) == cursor.getString(3)) {
                        "Agent transcript chunk digest mismatch"
                    }
                    add(value)
                }
            }
        }
        check(chunks.size == expectedCount) { "Agent transcript chunk count mismatch" }
        val value = chunks.joinToString("")
        check(value.length == expectedLength) { "Agent transcript output length mismatch" }
        check(AgentLargeOutputPolicy.digest(value) == expectedSha256) {
            "Agent transcript output digest mismatch"
        }
        return value
    }

    private fun associatedData(entryId: String): ByteArray =
        "agent-transcript-entry:$entryId".toByteArray(Charsets.UTF_8)

    private fun chunkAssociatedData(entryId: String, field: String, index: Int): ByteArray =
        "agent-transcript-chunk:$entryId:$field:$index".toByteArray(Charsets.UTF_8)

    private fun digest(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun createChunkStorage(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transcript_entry_chunks (
                entry_id TEXT NOT NULL,
                field_name TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                encrypted_chunk TEXT NOT NULL,
                char_count INTEGER NOT NULL,
                chunk_sha256 TEXT NOT NULL,
                PRIMARY KEY(entry_id, field_name, chunk_index),
                FOREIGN KEY(entry_id) REFERENCES transcript_entries(entry_id)
                    ON DELETE CASCADE
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS transcript_entry_chunks_order
            ON transcript_entry_chunks(entry_id, field_name, chunk_index)
            """.trimIndent()
        )
    }

    companion object {
        private const val DATABASE_NAME = "signalasi_agent_transcript_entries.db"
        private const val DATABASE_VERSION = 2
        private const val TABLE_ENTRIES = "transcript_entries"
        private const val TABLE_CHUNKS = "transcript_entry_chunks"
        private const val FIELD_TEXT = "text"
        private const val FIELD_RICH_OUTPUT = "rich_output"
        private const val DEFAULT_PAGE_SIZE = 100
        private const val MAX_PAGE_SIZE = 500
        private const val MAX_CONTENT_PAGE_CHUNKS = 8
        private val PAYLOAD_COLUMNS = arrayOf("entry_id", "encrypted_payload")
        private val PAGE_COLUMNS = arrayOf("sequence", "entry_id", "encrypted_payload")
    }
}
