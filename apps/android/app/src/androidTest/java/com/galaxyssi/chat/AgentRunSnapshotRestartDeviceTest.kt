package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Two opt-in phases, separated by an external am force-stop of the target App. */
@RunWith(AndroidJUnit4::class)
class AgentRunSnapshotRestartDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun persistMigrationCheckpointBeforeProcessDeath() {
        val name = databaseName()
        var store = AgentRunEventStore(context, name)
        (1..65).forEach { store.appendNext(event(it)) }
        store.close()
        database(name) { db ->
            db.execSQL("DROP TABLE run_snapshot_index")
            db.delete("ledger_metadata", "metadata_key=?", arrayOf(AgentRunSnapshotIndex.MIGRATION_KEY))
            db.version = 1
        }
        store = AgentRunEventStore(context, name)
        try {
            assertTrue(store.backfillSnapshotIndexPage())
            assertEquals(32L, JSONObject(checkpoint(name)).getLong("after"))
        } finally {
            store.close()
        }
        // Keep only this uniquely named test database for the recovery phase.
    }

    @Test fun recoverMigrationAfterProcessDeath() {
        val name = databaseName()
        assertTrue(context.getDatabasePath(name).isFile)
        assertEquals(32L, JSONObject(checkpoint(name)).getLong("after"))
        val store = AgentRunEventStore(context, name)
        try {
            assertEquals("run-65", store.snapshotEvent(AgentRunSnapshotContract.VOICE, "run-65")?.runId)
            assertEquals("done", checkpoint(name))
            assertEquals(65, store.snapshotEventsPage(AgentRunSnapshotContract.VOICE).events.size)
            assertEquals(2L, store.appendNext(event(65))?.sequence)
            assertEquals(2L, store.snapshotEvent(AgentRunSnapshotContract.VOICE, "run-65")?.sequence)
        } finally {
            store.close()
            context.deleteDatabase(name)
        }
    }

    private fun databaseName(): String {
        val id = InstrumentationRegistry.getArguments().getString("snapshotRecoveryId").orEmpty()
        assumeTrue(id.matches(Regex("run-index-process-[0-9a-f-]{36}")))
        return "$id.db"
    }

    private fun checkpoint(name: String): String = database(name) { db ->
        db.rawQuery("SELECT metadata_value FROM ledger_metadata WHERE metadata_key=?",
            arrayOf(AgentRunSnapshotIndex.MIGRATION_KEY)).use { assertTrue(it.moveToFirst()); it.getString(0) }
    }

    private fun <T> database(name: String, block: (SQLiteDatabase) -> T): T = SQLiteDatabase.openDatabase(
        context.getDatabasePath(name).absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use(block)

    private fun event(number: Int): AgentRunControlEvent {
        val snapshot = JSONObject().put("run_id", "run-$number").put("task_id", "task-$number")
            .put("conversation_id", "conversation-$number").put("source_message_id", number.toLong())
            .put("turn_id", "turn-$number").put("idempotency_key", "request-$number")
        return AgentRunControlEvent(conversationId = "conversation-$number", messageId = number.toString(),
            taskId = "task-$number", runId = "run-$number", agentId = "codex", deviceId = "phone",
            type = AgentRunControlEventType.TOOL_PROGRESS, sequence = 0L,
            payload = mapOf(AgentRunSnapshotContract.VOICE_PAYLOAD to snapshot.toString()))
    }
}
