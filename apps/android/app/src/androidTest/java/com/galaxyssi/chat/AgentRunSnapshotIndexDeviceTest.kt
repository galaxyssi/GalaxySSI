package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.agent.AgentRunEventVoiceAgentRunRepository
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRequest
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentRunSnapshotIndexDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val databaseName = "run-index-test-${UUID.randomUUID()}.db"
    private var store = AgentRunEventStore(context, databaseName)
    private val kind = AgentRunSnapshotContract.VOICE

    @After fun cleanUp() {
        store.close()
        check(databaseName.startsWith("run-index-test-"))
        context.deleteDatabase(databaseName)
    }

    @Test fun oldestRunBeyond256IsFoundAndAllPagesAndClearingAreComplete() {
        (1..300).forEach { store.appendNext(event(it)) }
        store.appendNext(event(1000, voice = false))
        assertEquals("run-1", store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "task-1")?.runId)
        assertEquals("run-1", store.findSnapshot(kind, AgentRunSnapshotLookup.MESSAGE, "1")?.runId)
        assertEquals("run-1", store.findSnapshot(kind, AgentRunSnapshotLookup.REQUEST, "request-1")?.runId)
        val legacyStart = SystemClock.elapsedRealtimeNanos()
        val legacyEvents = store.storedRunIds(256).flatMap(store::events)
        assertTrue(legacyEvents.any { it.runId == "run-300" })
        val legacyMillis = (SystemClock.elapsedRealtimeNanos() - legacyStart) / 1_000_000.0
        val hits = (1..30).map {
            val start = SystemClock.elapsedRealtimeNanos()
            assertEquals("run-300", store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "task-300")?.runId)
            (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
        }.sorted()
        val missStart = SystemClock.elapsedRealtimeNanos()
        assertNull(store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "missing"))
        Log.i("RunSnapshotIndexTest", "runs=301 legacy_scan_ms=$legacyMillis " +
            "hit_samples=30 hit_p50_ms=${hits[14]} hit_p95_ms=${hits[28]} " +
            "miss_ms=${(SystemClock.elapsedRealtimeNanos() - missStart) / 1_000_000.0}")
        val ids = mutableListOf<String>()
        var before: Long? = null
        do {
            val page = store.snapshotEventsPage(kind, before, 37)
            assertTrue(page.events.size <= 37)
            ids += page.events.map { it.runId }
            before = page.nextBeforeOrdinal
        } while (before != null)
        assertEquals((300 downTo 1).map { "run-$it" }, ids)
        assertEquals(300, ids.toSet().size)
        store.removeSnapshotRuns(kind)
        assertTrue(store.snapshotEventsPage(kind).events.isEmpty())
        assertEquals(listOf("run-1000"), store.storedRunIds(500))
    }

    @Test fun latestPointerSurvivesColdReopenAndIgnoresNonSnapshotEvents() {
        store.appendNext(event(1))
        val completed = store.appendNext(event(1, type = AgentRunControlEventType.RUN_COMPLETED))!!
        assertNull(store.appendNext(event(1)))
        store.appendNext(event(2))
        store.appendNext(event(2, voice = false))
        reopen()
        assertEquals(completed.eventId, store.snapshotEvent(kind, "run-1")?.eventId)
        assertEquals(1L, store.snapshotEvent(kind, "run-2")?.sequence)
    }

    @Test fun missAndTargetLookupDoNotDecryptUnrelatedCorruptHistory() {
        store.appendNext(event(1))
        store.appendNext(event(2))
        assertNotNull(store.snapshotEvent(kind, "run-1"))
        database { db ->
            db.execSQL("UPDATE run_events SET encrypted_event='invalid-ciphertext' WHERE run_key=?",
                arrayOf(AgentRunSnapshotContract.digest("run-2")))
        }
        assertNull(store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "missing"))
        assertEquals("run-1", store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "task-1")?.runId)
        assertTrue(runCatching { store.snapshotEvent(kind, "run-2") }.isFailure)
    }

    @Test fun indexFailureRollsBackNewRootEventAndPointer() {
        store.appendNext(event(1))
        database { db -> db.execSQL("CREATE TRIGGER fail_snapshot BEFORE INSERT ON run_snapshot_index " +
            "BEGIN SELECT RAISE(ABORT,'injected index failure'); END") }
        assertTrue(runCatching { store.appendNext(event(2)) }.isFailure)
        assertTrue(runCatching { store.appendNext(event(1)) }.isFailure)
        assertNull(store.latestEvent("run-2"))
        assertFalse("run-2" in store.storedRunIds(10))
        assertEquals(1L, store.latestEvent("run-1")?.sequence)
        assertEquals(1L, store.snapshotEvent(kind, "run-1")?.sequence)
        database { it.execSQL("DROP TRIGGER fail_snapshot") }
        assertEquals(2L, store.appendNext(event(1))?.sequence)
    }

    @Test fun duplicateReplayAndInvalidSnapshotDoNotChangeIndex() {
        val original = store.appendNext(event(1))!!
        assertFalse(store.append(original))
        val wrong = event(1).let { it.copy(payload = mapOf(AgentRunSnapshotContract.VOICE_PAYLOAD to
            JSONObject(it.payload[AgentRunSnapshotContract.VOICE_PAYLOAD] as String)
                .put("conversation_id", "other-conversation").toString())) }
        assertTrue(runCatching { store.appendNext(wrong) }.isFailure)
        assertEquals(original.eventId, store.snapshotEvent(kind, "run-1")?.eventId)
        assertEquals(1, store.events("run-1").size)
    }

    @Test fun lookupUsesSqlIndexAndStoresOnlyHashesAndEncryptedBodies() {
        store.appendNext(event(1))
        database { db ->
            db.rawQuery("EXPLAIN QUERY PLAN SELECT run_key,sequence FROM run_snapshot_index " +
                "WHERE kind=? AND task_hash=? ORDER BY event_ordinal DESC LIMIT 1",
                arrayOf(kind, AgentRunSnapshotContract.lookupHash(kind, AgentRunSnapshotLookup.TASK, "task-1"))).use {
                assertTrue(it.moveToFirst())
                assertTrue(it.getString(3), it.getString(3).contains("snapshot_task_hash"))
            }
            db.rawQuery("SELECT run_key,task_hash,message_hash,request_hash FROM run_snapshot_index", null).use {
                assertTrue(it.moveToFirst())
                (0..3).forEach { column -> assertTrue(it.getString(column).matches(Regex("[0-9a-f]{64}"))) }
            }
            db.rawQuery("SELECT encrypted_event FROM run_events", null).use {
                assertTrue(it.moveToFirst())
                assertFalse(it.getString(0).contains("task-1"))
                assertFalse(it.getString(0).contains("request-1"))
            }
        }
    }

    @Test fun migrationCheckpointsResumeAndConcurrentAppendDoesNotRegress() {
        (1..97).forEach { store.appendNext(event(it)) }
        makeLegacyDatabase()
        assertTrue(store.backfillSnapshotIndexPage())
        val checkpoint = metadata()
        assertEquals(32L, JSONObject(checkpoint).getLong("after"))
        assertEquals(97L, JSONObject(checkpoint).getLong("through"))
        // This event is newer than the captured migration high-water mark.
        val newer = store.appendNext(event(90))!!
        reopen()
        assertEquals(checkpoint, metadata())
        assertEquals(newer.eventId, store.findSnapshot(kind, AgentRunSnapshotLookup.TASK, "task-90")?.eventId)
        assertEquals("run-1", store.snapshotEvent(kind, "run-1")?.runId)
        assertEquals("done", metadata())
        assertEquals(97, store.snapshotEventsPage(kind, limit = 256).events.size)
    }

    @Test fun migrationDecodeFailureKeepsCheckpointAndCanResumeAfterRepair() {
        (1..65).forEach { store.appendNext(event(it)) }
        makeLegacyDatabase()
        assertTrue(store.backfillSnapshotIndexPage())
        val checkpoint = metadata()
        val encrypted = database { db ->
            db.rawQuery("SELECT encrypted_event FROM run_events WHERE rowid=40", null).use {
                assertTrue(it.moveToFirst()); it.getString(0)
            }.also { db.execSQL("UPDATE run_events SET encrypted_event='broken' WHERE rowid=40") }
        }
        assertTrue(runCatching { store.backfillSnapshotIndexPage() }.isFailure)
        assertEquals(checkpoint, metadata())
        database { it.execSQL("UPDATE run_events SET encrypted_event=? WHERE rowid=40", arrayOf(encrypted)) }
        reopen()
        assertEquals("run-65", store.snapshotEvent(kind, "run-65")?.runId)
        assertEquals("done", metadata())
        assertEquals(65, store.snapshotEventsPage(kind).events.size)
    }

    @Test fun failedCheckpointRollsBackBatchAndDoesNotMarkMigrationReady() {
        (1..33).forEach { store.appendNext(event(it)) }
        makeLegacyDatabase()
        // Open schema v2 before installing the failure on its migration metadata.
        assertNotNull(store.latestEvent("run-1"))
        database { it.execSQL("CREATE TRIGGER fail_checkpoint BEFORE INSERT ON ledger_metadata " +
            "BEGIN SELECT RAISE(ABORT,'injected checkpoint failure'); END") }
        assertTrue(runCatching { store.backfillSnapshotIndexPage() }.isFailure)
        database { db ->
            db.rawQuery("SELECT COUNT(*) FROM run_snapshot_index", null).use {
                assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
            }
            db.execSQL("DROP TRIGGER fail_checkpoint")
        }
        assertTrue(store.backfillSnapshotIndexPage())
        assertEquals(32L, JSONObject(metadata()).getLong("after"))
        assertEquals("run-33", store.snapshotEvent(kind, "run-33")?.runId)
        assertEquals("done", metadata())
    }

    @Test fun voiceRepositoryUsesBoundedRecentRestoreAndExactIdentities() {
        val repository = AgentRunEventVoiceAgentRunRepository(store)
        val bridge = VoiceAgentRunBridge(repository)
        val snapshots = (1..5).map { number -> bridge.createRun(VoiceAgentRunRequest(
            conversationId = "conversation-$number", turnId = "turn-$number", taskId = "task-$number",
            sourceMessageId = number.toLong(), contactId = "contact", agentId = "codex", agentName = "Codex",
            deviceId = "phone", goal = "test", idempotencyKey = "request-$number")).snapshot }
        assertEquals(snapshots.first(), repository.findByTaskId("task-1"))
        assertEquals(snapshots.first(), repository.findBySourceMessageId(1))
        assertEquals(snapshots.first(), repository.findByIdempotencyKey("request-1"))
        assertNull(repository.findByTaskId("missing"))
        assertNull(repository.findBySourceMessageId(0))
        assertEquals(snapshots.takeLast(2), bridge.recentSnapshots(2))
        assertTrue(bridge.recentSnapshots(0).isEmpty())
        assertEquals(snapshots, repository.list())
        repository.clear()
        assertTrue(repository.list().isEmpty())
    }

    @Test fun preRoutingEvaluationInterruptionIsDurableWithoutInventingAModel() {
        val run = AgentRecordedRun("evaluation-run", "evaluation-conversation", "evaluation-task", "test")
        val failed = store.appendNext(AgentEvalRunEvents.create(run, null,
            AgentRunControlEventType.RUN_FAILED, mapOf("condition" to "process_death")))!!
        assertEquals(AgentEvalRunEvents.OBSERVER, failed.agentId)
        assertEquals(AgentRunControlState.FAILED, store.snapshot(run.runId)?.state)
        reopen()
        val recovered = store.appendNext(AgentEvalRunEvents.create(run, store.latestEvent(run.runId),
            AgentRunControlEventType.RUN_RECOVERED, emptyMap()))!!
        assertEquals(2L, recovered.sequence)
        assertEquals(AgentRunControlState.RUNNING, store.snapshot(run.runId)?.state)
        assertTrue(store.snapshotEventsPage(kind).events.isEmpty())
    }

    private fun event(number: Int, voice: Boolean = true,
        type: AgentRunControlEventType = AgentRunControlEventType.TOOL_PROGRESS): AgentRunControlEvent {
        val body = JSONObject().put("run_id", "run-$number").put("task_id", "task-$number")
            .put("conversation_id", "conversation-$number").put("source_message_id", number.toLong())
            .put("turn_id", "turn-$number").put("idempotency_key", "request-$number")
        return AgentRunControlEvent(conversationId = "conversation-$number", messageId = number.toString(),
            taskId = "task-$number", runId = "run-$number", agentId = "codex", deviceId = "phone",
            type = type, sequence = 0L,
            payload = if (voice) mapOf(AgentRunSnapshotContract.VOICE_PAYLOAD to body.toString()) else emptyMap())
    }

    private fun reopen() {
        store.close()
        store = AgentRunEventStore(context, databaseName)
    }

    private fun makeLegacyDatabase() {
        store.close()
        database { db ->
            db.execSQL("DROP TABLE run_snapshot_index")
            db.delete("ledger_metadata", "metadata_key=?", arrayOf(AgentRunSnapshotIndex.MIGRATION_KEY))
            db.version = 1
        }
        store = AgentRunEventStore(context, databaseName)
    }

    private fun metadata(): String = database { db ->
        db.rawQuery("SELECT metadata_value FROM ledger_metadata WHERE metadata_key=?",
            arrayOf(AgentRunSnapshotIndex.MIGRATION_KEY)).use { assertTrue(it.moveToFirst()); it.getString(0) }
    }

    private fun <T> database(block: (SQLiteDatabase) -> T): T = SQLiteDatabase.openDatabase(
        context.getDatabasePath(databaseName).absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use(block)
}
