package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Process-wide facade over the append-only Run Kernel ledger.
 *
 * Event payloads and root identities are encrypted independently so a long run
 * appends one bounded row instead of rewriting a growing plaintext array.
 */
class AgentRunEventStore(context: Context) : AgentRunControlStore {
    private val ledger = AgentRunEventLedger.shared(context.applicationContext)

    init {
        ledger.migrateLegacyIfNeeded(context.applicationContext)
    }

    fun append(event: AgentRunControlEvent): Boolean = ledger.appendExact(event)

    override fun appendNext(event: AgentRunControlEvent): AgentRunControlEvent? =
        ledger.appendNextAll(listOf(event)).singleOrNull()

    fun appendNextAll(events: List<AgentRunControlEvent>): List<AgentRunControlEvent> =
        ledger.appendNextAll(events)

    fun events(runId: String): List<AgentRunControlEvent> = ledger.events(runId)

    fun eventsPage(
        runId: String,
        afterSequence: Long = 0L,
        limit: Int = DEFAULT_EVENT_PAGE_SIZE
    ): List<AgentRunControlEvent> = ledger.eventsPage(runId, afterSequence, limit)

    fun latestEvent(runId: String): AgentRunControlEvent? = ledger.latestEvent(runId)

    fun snapshot(runId: String): AgentRunControlSnapshot? = ledger.snapshot(runId)

    override fun recoverableRuns(): List<AgentRunControlSnapshot> = ledger.recoverableRuns()

    fun storedRunIds(limit: Int = 500): List<String> = ledger.storedRunIds(limit)

    fun removeRuns(runIds: Set<String>) = ledger.removeRuns(runIds)

    fun clear() = ledger.clear()

    companion object {
        private const val DEFAULT_EVENT_PAGE_SIZE = 256
        private val TERMINAL_STATES = setOf(
            AgentRunControlState.COMPLETED,
            AgentRunControlState.FAILED,
            AgentRunControlState.CANCELLED
        )

        fun reduce(current: AgentRunControlState, event: AgentRunControlEventType): AgentRunControlState = when (event) {
            AgentRunControlEventType.RUN_CREATED -> AgentRunControlState.CREATED
            AgentRunControlEventType.RUN_QUEUED -> AgentRunControlState.QUEUED
            AgentRunControlEventType.CHECKPOINT_SAVED -> current
            AgentRunControlEventType.RUN_STARTED,
            AgentRunControlEventType.PLANNING,
            AgentRunControlEventType.THINKING,
            AgentRunControlEventType.AGENT_CONNECTED,
            AgentRunControlEventType.STEP_STARTED,
            AgentRunControlEventType.TOOL_STARTED,
            AgentRunControlEventType.TOOL_PROGRESS,
            AgentRunControlEventType.TOOL_COMPLETED,
            AgentRunControlEventType.RETRYING,
            AgentRunControlEventType.HANDOFF,
            AgentRunControlEventType.STEP_COMPLETED,
            AgentRunControlEventType.RUN_RECOVERED -> AgentRunControlState.RUNNING
            AgentRunControlEventType.TOOL_PERMISSION_REQUIRED,
            AgentRunControlEventType.WAITING_FOR_USER -> AgentRunControlState.WAITING_FOR_USER
            AgentRunControlEventType.PERMISSION_REVOKED,
            AgentRunControlEventType.PAUSED,
            AgentRunControlEventType.RUN_INTERRUPTED -> AgentRunControlState.PAUSED
            AgentRunControlEventType.WAITING_FOR_DEVICE -> AgentRunControlState.WAITING_FOR_DEVICE
            AgentRunControlEventType.RUN_COMPLETED -> AgentRunControlState.COMPLETED
            AgentRunControlEventType.RUN_FAILED -> AgentRunControlState.FAILED
            AgentRunControlEventType.RUN_CANCELLED -> AgentRunControlState.CANCELLED
        }.let { next ->
            if (current in TERMINAL_STATES && event != AgentRunControlEventType.RUN_RECOVERED) current else next
        }
    }
}

private class AgentRunEventLedger(context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_FILE,
    null,
    DATABASE_VERSION
) {
    private data class RootRow(
        val rootHash: String,
        val state: AgentRunControlState,
        val lastSequence: Long
    )

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
        db.rawQuery("PRAGMA busy_timeout=5000", null).use { it.moveToFirst() }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE run_roots (" +
                "run_key TEXT PRIMARY KEY NOT NULL," +
                "root_hash TEXT NOT NULL," +
                "encrypted_root TEXT NOT NULL," +
                "state TEXT NOT NULL," +
                "last_sequence INTEGER NOT NULL," +
                "updated_at_millis INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE run_events (" +
                "run_key TEXT NOT NULL," +
                "sequence INTEGER NOT NULL," +
                "event_id_hash TEXT NOT NULL," +
                "idempotency_hash TEXT NOT NULL," +
                "timestamp_millis INTEGER NOT NULL," +
                "event_type TEXT NOT NULL," +
                "encrypted_event TEXT NOT NULL," +
                "PRIMARY KEY(run_key, sequence)," +
                "UNIQUE(event_id_hash)," +
                "UNIQUE(run_key, idempotency_hash)," +
                "FOREIGN KEY(run_key) REFERENCES run_roots(run_key) ON DELETE CASCADE)"
        )
        db.execSQL(
            "CREATE TABLE ledger_metadata (" +
                "metadata_key TEXT PRIMARY KEY NOT NULL," +
                "metadata_value TEXT NOT NULL)"
        )
        db.execSQL(
            "CREATE INDEX run_roots_recovery_order " +
                "ON run_roots(state, updated_at_millis DESC)"
        )
        db.execSQL(
            "CREATE INDEX run_events_time_order " +
                "ON run_events(timestamp_millis, event_id_hash)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun appendExact(event: AgentRunControlEvent): Boolean = synchronized(this) {
        val canonical = AgentRunKernelContract.canonical(event)
        require(canonical.sequence > 0L) { "Run event sequence must be positive" }
        writableDatabase.inTransactionResult {
            val root = readRoot(canonical.runId)
            root?.let { require(it.rootHash == rootHash(canonical)) { "Run root identity changed" } }
            existingByIdempotency(canonical.runId, canonical.idempotencyKey)?.let { existing ->
                AgentRunKernelContract.requireIdempotentReplay(existing, canonical)
                return@inTransactionResult false
            }
            if (root != null) {
                check(!root.state.isTerminal() || canonical.type == AgentRunControlEventType.RUN_RECOVERED) {
                    "Cannot append ${canonical.type} after terminal Run state ${root.state}"
                }
                require(canonical.sequence > root.lastSequence) { "Run event sequence must increase" }
            }
            insert(canonical, root)
            true
        }
    }

    fun appendNextAll(events: List<AgentRunControlEvent>): List<AgentRunControlEvent> = synchronized(this) {
        if (events.isEmpty()) return@synchronized emptyList()
        val canonicalEvents = events.map(AgentRunKernelContract::canonical)
        val runId = canonicalEvents.first().runId
        require(canonicalEvents.all { it.runId == runId }) { "Batched Run events must belong to one Run" }
        writableDatabase.inTransactionResult {
            var root = readRoot(runId)
            val expectedRootHash = root?.rootHash ?: rootHash(canonicalEvents.first())
            canonicalEvents.forEach {
                require(rootHash(it) == expectedRootHash) { "Run root identity changed" }
            }
            var sequence = root?.lastSequence ?: 0L
            var state = root?.state ?: AgentRunControlState.CREATED
            val appended = mutableListOf<AgentRunControlEvent>()
            canonicalEvents.forEach { event ->
                existingByIdempotency(runId, event.idempotencyKey)?.let { existing ->
                    AgentRunKernelContract.requireIdempotentReplay(existing, event)
                    return@forEach
                }
                if (state.isTerminal() && event.type != AgentRunControlEventType.RUN_RECOVERED) {
                    return@forEach
                }
                sequence += 1L
                val sequenced = event.copy(sequence = sequence)
                insert(sequenced, root)
                appended += sequenced
                state = AgentRunEventStore.reduce(state, sequenced.type)
                root = RootRow(expectedRootHash, state, sequence)
            }
            appended
        }
    }

    fun events(runId: String): List<AgentRunControlEvent> = synchronized(this) {
        queryEvents(runId, afterSequence = 0L, limit = null)
    }

    fun eventsPage(runId: String, afterSequence: Long, limit: Int): List<AgentRunControlEvent> = synchronized(this) {
        queryEvents(runId, afterSequence.coerceAtLeast(0L), limit.coerceAtLeast(1))
    }

    fun latestEvent(runId: String): AgentRunControlEvent? = synchronized(this) {
        val runKey = digest(runId.trim())
        readableDatabase.query(
            TABLE_EVENTS,
            arrayOf(COLUMN_SEQUENCE, COLUMN_ENCRYPTED_EVENT),
            "$COLUMN_RUN_KEY = ?",
            arrayOf(runKey),
            null,
            null,
            "$COLUMN_SEQUENCE DESC",
            "1"
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else decodeEvent(cursor, runKey)
        }
    }

    fun snapshot(runId: String): AgentRunControlSnapshot? = synchronized(this) {
        val root = readRoot(runId) ?: return@synchronized null
        val last = latestEvent(runId) ?: return@synchronized null
        AgentRunControlSnapshot(
            runId = last.runId,
            taskId = last.taskId,
            state = root.state,
            agentId = last.agentId,
            deviceId = last.deviceId,
            lastSequence = root.lastSequence,
            lastEvent = last
        )
    }

    fun recoverableRuns(): List<AgentRunControlSnapshot> = synchronized(this) {
        readableDatabase.query(
            TABLE_ROOTS,
            arrayOf(COLUMN_RUN_KEY, COLUMN_ENCRYPTED_ROOT),
            "$COLUMN_STATE NOT IN (?,?,?)",
            TERMINAL_STATE_NAMES,
            null,
            null,
            "$COLUMN_UPDATED_AT_MILLIS ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    decodeRunId(cursor.getString(0), cursor.getString(1))
                        ?.let(::snapshot)
                        ?.let(::add)
                }
            }
        }
    }

    fun storedRunIds(limit: Int): List<String> = synchronized(this) {
        readableDatabase.query(
            TABLE_ROOTS,
            arrayOf(COLUMN_RUN_KEY, COLUMN_ENCRYPTED_ROOT),
            null,
            null,
            null,
            null,
            "$COLUMN_UPDATED_AT_MILLIS DESC",
            limit.coerceAtLeast(1).toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    decodeRunId(cursor.getString(0), cursor.getString(1))?.let(::add)
                }
            }.asReversed()
        }
    }

    fun removeRuns(runIds: Set<String>) = synchronized(this) {
        if (runIds.isEmpty()) return@synchronized
        writableDatabase.inTransaction {
            runIds.map(String::trim).filter(String::isNotEmpty).forEach { runId ->
                delete(TABLE_ROOTS, "$COLUMN_RUN_KEY = ?", arrayOf(digest(runId)))
            }
        }
    }

    fun clear() = synchronized(this) {
        writableDatabase.inTransaction {
            delete(TABLE_ROOTS, null, null)
        }
    }

    fun migrateLegacyIfNeeded(context: Context) = synchronized(this) {
        if (metadata(LEGACY_MIGRATION_KEY) == "done") return@synchronized
        val legacy = AgentEncryptedDatabase(context, LEGACY_DATABASE)
        val entries = legacy.entries("run:")
        entries.forEach { (_, raw) ->
            val array = runCatching { JSONArray(raw) }.getOrNull() ?: return@forEach
            val events = buildList {
                for (index in 0 until array.length()) {
                    array.optJSONObject(index)?.toRunEvent()?.let(::add)
                }
            }.sortedBy { it.sequence }
            events.forEach { event ->
                runCatching { appendExact(event) }.getOrThrow()
            }
        }
        putMetadata(LEGACY_MIGRATION_KEY, "done")
    }

    private fun insert(event: AgentRunControlEvent, existingRoot: RootRow?) {
        val database = writableDatabase
        val runKey = digest(event.runId)
        val nextState = AgentRunEventStore.reduce(
            existingRoot?.state ?: AgentRunControlState.CREATED,
            event.type
        )
        if (existingRoot == null) {
            val rootValues = ContentValues().apply {
                put(COLUMN_RUN_KEY, runKey)
                put(COLUMN_ROOT_HASH, rootHash(event))
                put(COLUMN_ENCRYPTED_ROOT, encryptRoot(event, runKey))
                put(COLUMN_STATE, nextState.name)
                put(COLUMN_LAST_SEQUENCE, event.sequence)
                put(COLUMN_UPDATED_AT_MILLIS, System.currentTimeMillis())
            }
            check(database.insertOrThrow(TABLE_ROOTS, null, rootValues) != -1L)
        }
        val eventValues = ContentValues().apply {
            put(COLUMN_RUN_KEY, runKey)
            put(COLUMN_SEQUENCE, event.sequence)
            put(COLUMN_EVENT_ID_HASH, digest(event.eventId))
            put(COLUMN_IDEMPOTENCY_HASH, digest(event.idempotencyKey))
            put(COLUMN_TIMESTAMP_MILLIS, event.timestampMillis)
            put(COLUMN_EVENT_TYPE, event.type.name)
            put(COLUMN_ENCRYPTED_EVENT, encryptEvent(event, runKey))
        }
        check(database.insertOrThrow(TABLE_EVENTS, null, eventValues) != -1L)
        val rootUpdate = ContentValues().apply {
            put(COLUMN_STATE, nextState.name)
            put(COLUMN_LAST_SEQUENCE, event.sequence)
            put(COLUMN_UPDATED_AT_MILLIS, System.currentTimeMillis())
        }
        check(database.update(TABLE_ROOTS, rootUpdate, "$COLUMN_RUN_KEY = ?", arrayOf(runKey)) == 1)
    }

    private fun readRoot(runId: String): RootRow? {
        val runKey = digest(runId.trim())
        return readableDatabase.query(
            TABLE_ROOTS,
            arrayOf(COLUMN_ROOT_HASH, COLUMN_STATE, COLUMN_LAST_SEQUENCE),
            "$COLUMN_RUN_KEY = ?",
            arrayOf(runKey),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else RootRow(
                rootHash = cursor.getString(0),
                state = enumValueOf(cursor.getString(1)),
                lastSequence = cursor.getLong(2)
            )
        }
    }

    private fun existingByIdempotency(runId: String, idempotencyKey: String): AgentRunControlEvent? {
        val runKey = digest(runId.trim())
        return readableDatabase.query(
            TABLE_EVENTS,
            arrayOf(COLUMN_SEQUENCE, COLUMN_ENCRYPTED_EVENT),
            "$COLUMN_RUN_KEY = ? AND $COLUMN_IDEMPOTENCY_HASH = ?",
            arrayOf(runKey, digest(idempotencyKey)),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (!cursor.moveToFirst()) null else decodeEvent(cursor, runKey)
        }
    }

    private fun queryEvents(runId: String, afterSequence: Long, limit: Int?): List<AgentRunControlEvent> {
        val runKey = digest(runId.trim())
        return readableDatabase.query(
            TABLE_EVENTS,
            arrayOf(COLUMN_SEQUENCE, COLUMN_ENCRYPTED_EVENT),
            "$COLUMN_RUN_KEY = ? AND $COLUMN_SEQUENCE > ?",
            arrayOf(runKey, afterSequence.toString()),
            null,
            null,
            "$COLUMN_SEQUENCE ASC",
            limit?.toString()
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) decodeEvent(cursor, runKey)?.let(::add)
            }
        }
    }

    private fun decodeEvent(cursor: Cursor, runKey: String): AgentRunControlEvent? {
        val sequence = cursor.getLong(0)
        val encrypted = cursor.getString(1)
        val plaintext = AgentStorageCipher.decrypt(encrypted, eventAssociatedData(runKey, sequence)) ?: return null
        return runCatching { JSONObject(plaintext).toRunEvent() }.getOrNull()
    }

    private fun encryptEvent(event: AgentRunControlEvent, runKey: String): String =
        AgentStorageCipher.encrypt(event.toJson().toString(), eventAssociatedData(runKey, event.sequence))

    private fun encryptRoot(event: AgentRunControlEvent, runKey: String): String {
        val root = AgentRunKernelContract.rootIdentity(event)
        val payload = JSONObject()
            .put("client_route_id", root.clientRouteId)
            .put("conversation_id", root.conversationId)
            .put("goal_id", root.goalId)
            .put("task_id", root.taskId)
            .put("run_id", root.runId)
        return AgentStorageCipher.encrypt(payload.toString(), rootAssociatedData(runKey))
    }

    private fun decodeRunId(runKey: String, encryptedRoot: String): String? = runCatching {
        val plaintext = AgentStorageCipher.decrypt(encryptedRoot, rootAssociatedData(runKey))
            ?: return@runCatching null
        JSONObject(plaintext).optString("run_id").takeIf(String::isNotBlank)
    }.getOrNull()

    private fun rootHash(event: AgentRunControlEvent): String {
        val root = AgentRunKernelContract.rootIdentity(event)
        return digest(listOf(
            root.clientRouteId,
            root.conversationId,
            root.goalId,
            root.taskId,
            root.runId
        ).joinToString("\u0000"))
    }

    private fun eventAssociatedData(runKey: String, sequence: Long): ByteArray =
        "run-event:$runKey:$sequence".toByteArray(Charsets.UTF_8)

    private fun rootAssociatedData(runKey: String): ByteArray =
        "run-root:$runKey".toByteArray(Charsets.UTF_8)

    private fun metadata(key: String): String? = readableDatabase.query(
        TABLE_METADATA,
        arrayOf(COLUMN_METADATA_VALUE),
        "$COLUMN_METADATA_KEY = ?",
        arrayOf(key),
        null,
        null,
        null,
        "1"
    ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private fun putMetadata(key: String, value: String) {
        val values = ContentValues().apply {
            put(COLUMN_METADATA_KEY, key)
            put(COLUMN_METADATA_VALUE, value)
        }
        writableDatabase.insertWithOnConflict(
            TABLE_METADATA,
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') }

    private fun AgentRunControlState.isTerminal(): Boolean = this in setOf(
        AgentRunControlState.COMPLETED,
        AgentRunControlState.FAILED,
        AgentRunControlState.CANCELLED
    )

    private inline fun <T> SQLiteDatabase.inTransactionResult(block: SQLiteDatabase.() -> T): T {
        beginTransaction()
        return try {
            block().also { setTransactionSuccessful() }
        } finally {
            endTransaction()
        }
    }

    private inline fun SQLiteDatabase.inTransaction(block: SQLiteDatabase.() -> Unit) {
        beginTransaction()
        try {
            block()
            setTransactionSuccessful()
        } finally {
            endTransaction()
        }
    }

    companion object {
        private const val DATABASE_FILE = "galaxyssi_run_kernel_v1.db"
        private const val DATABASE_VERSION = 1
        private const val LEGACY_DATABASE = "galaxyssi_run_control_v1"
        private const val LEGACY_MIGRATION_KEY = "legacy_encrypted_array_v1"
        private const val TABLE_ROOTS = "run_roots"
        private const val TABLE_EVENTS = "run_events"
        private const val TABLE_METADATA = "ledger_metadata"
        private const val COLUMN_RUN_KEY = "run_key"
        private const val COLUMN_ROOT_HASH = "root_hash"
        private const val COLUMN_ENCRYPTED_ROOT = "encrypted_root"
        private const val COLUMN_STATE = "state"
        private const val COLUMN_LAST_SEQUENCE = "last_sequence"
        private const val COLUMN_UPDATED_AT_MILLIS = "updated_at_millis"
        private const val COLUMN_SEQUENCE = "sequence"
        private const val COLUMN_EVENT_ID_HASH = "event_id_hash"
        private const val COLUMN_IDEMPOTENCY_HASH = "idempotency_hash"
        private const val COLUMN_TIMESTAMP_MILLIS = "timestamp_millis"
        private const val COLUMN_EVENT_TYPE = "event_type"
        private const val COLUMN_ENCRYPTED_EVENT = "encrypted_event"
        private const val COLUMN_METADATA_KEY = "metadata_key"
        private const val COLUMN_METADATA_VALUE = "metadata_value"
        private val TERMINAL_STATE_NAMES = arrayOf(
            AgentRunControlState.COMPLETED.name,
            AgentRunControlState.FAILED.name,
            AgentRunControlState.CANCELLED.name
        )
        private val INSTANCES = ConcurrentHashMap<String, AgentRunEventLedger>()

        fun shared(context: Context): AgentRunEventLedger = INSTANCES.computeIfAbsent(DATABASE_FILE) {
            AgentRunEventLedger(context.applicationContext)
        }
    }
}
