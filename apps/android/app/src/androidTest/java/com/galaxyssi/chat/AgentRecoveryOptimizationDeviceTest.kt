package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Uses private test databases, never the user's tasks, transcripts or pairing records. */
@RunWith(AndroidJUnit4::class)
class AgentRecoveryOptimizationDeviceTest {
    private fun record(owner: String = "owner", source: Long = 12) = AgentManagedResponseRecord(
        owner, "run", "codex", AgentDeliveryMode.RESPOND, source, "peer", "conversation", "turn", "task")

    @Test fun migratesLegacyArrayAtomicallyAndCanFindOneRecordAmongMany() = isolated { context ->
        val legacy = AgentEncryptedDatabase(context, AgentManagedResponseRows.DATABASE)
        val records = (1..1000).map { record("owner-$it", it.toLong()) }
        legacy.writeString(AgentManagedResponseRows.LEGACY_RECORDS, AgentManagedResponseCodec.encode(records).toString())
        val ledger = EncryptedAgentManagedResponseLedger(context)
        assertFalse(legacy.contains(AgentManagedResponseRows.LEGACY_RECORDS))
        assertEquals(records[499], ledger.findOwner("owner-500"))
        assertEquals(1000, ledger.pendingForSupervisor("run").size)
        assertEquals(1000, legacy.countKeys("record:"))
        assertEquals(1, legacy.countKeys("source:500:"))
        assertEquals(records[499], EncryptedAgentManagedResponseLedger(context).findOwner("owner-500"))
        assertTrue(legacy.readableCiphertextsAreEncrypted(context))
    }

    @Test fun malformedLegacyDataIsKeptIntactForRepair() = isolated { context ->
        val legacy = AgentEncryptedDatabase(context, AgentManagedResponseRows.DATABASE)
        val raw = AgentManagedResponseCodec.encode(listOf(record())).put(JSONObject().put("invalid", true)).toString()
        legacy.writeString(AgentManagedResponseRows.LEGACY_RECORDS, raw)
        assertThrows(IllegalStateException::class.java) { EncryptedAgentManagedResponseLedger(context) }
        assertEquals(raw, legacy.readString(AgentManagedResponseRows.LEGACY_RECORDS, ""))
        assertEquals(0, legacy.countKeys("record:"))
    }

    @Test fun duplicateAndWrongSessionResponsesKeepExactOwnershipAndIndexes() = isolated { context ->
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val record = record()
        ledger.register(record)
        val response = AgentConnectorResponse(12, "peer", "Answer", "conversation", "turn", "task")
        assertNull(ledger.acknowledge(response.copy(conversationId = "other")))
        assertNull(ledger.acknowledge(response.copy(contactId = "other")))
        assertEquals(AgentManagedResponseState.COMPLETED, ledger.acknowledge(response)?.state)
        assertEquals("Answer", ledger.acknowledge(response.copy(content = "Duplicate"))?.response?.content)
        assertTrue(ledger.pendingForSupervisor("run").isEmpty())
        assertEquals(1, ledger.completedUnapplied().size)
        ledger.markApplied(record.ownerRunId)
        val recreated = EncryptedAgentManagedResponseLedger(context)
        assertTrue(recreated.completedUnapplied().isEmpty())
        assertEquals(AgentManagedResponseState.APPLIED, recreated.findOwner(record.ownerRunId)?.state)
        assertNull(recreated.findOwner(record.ownerRunId)?.response)
        assertTrue(recreated.ownsRecordedSource(12, "conversation", "turn"))
        recreated.removeOwner(record.ownerRunId)
        assertNull(recreated.findOwner(record.ownerRunId))
        assertFalse(recreated.ownsRecordedSource(12, "conversation", "turn"))
        val database = AgentEncryptedDatabase(context, AgentManagedResponseRows.DATABASE)
        assertEquals(0, database.countKeys("source:"))
        assertEquals(0, database.countKeys("state:"))
        assertEquals(0, database.countKeys("supervisor:"))
    }

    @Test fun corruptIndexesAreReportedInsteadOfDroppingRecoveryRecords() = isolated { context ->
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val database = AgentEncryptedDatabase(context, AgentManagedResponseRows.DATABASE)
        val record = record()
        ledger.register(record)
        database.remove(database.keys("record:").single())
        assertThrows(IllegalStateException::class.java) { ledger.pendingForSupervisor("run") }
        ledger.clear()
        ledger.register(record)
        val oldIndex = database.keys("state:").single()
        database.writeString(oldIndex.replace("PENDING", "COMPLETED"), database.readString(oldIndex, ""))
        assertThrows(IllegalStateException::class.java) { ledger.completedUnapplied() }
    }

    @Test fun snapshotsReuseOnlyUnchangedCiphertextAndObserveExternalWritesAndRemoval() = isolated { context ->
        val database = AgentEncryptedDatabase(context, "team-decode-fixture")
        val store = EncryptedAgentTeamExecutionStore(database)
        val request = AgentRunRequest(conversationId = "conversation", messageId = "turn", taskId = "task",
            runId = "run", goal = "Snapshot fixture", idempotencyKey = "fixture")
        val definition = AgentTeamDefinition("team", "lead", listOf(AgentTeamMember("lead", AgentDeliveryMode.RESPOND)))
        store.create(definition, request)
        val first = requireNotNull(store.snapshot("run"))
        repeat(1000) { assertSame(first, store.snapshot("run")) }
        val oldCiphertext = database.readDecodedRows(listOf("run:run")) { _, ciphertext, _ -> ciphertext }.values.single()
        runBlocking { store.append(AgentSubagentEvent(1, "run", "", AgentSubagentEventKinds.SUPERVISOR_STARTED)) }
        assertEquals(AgentTeamExecutionState.RUNNING, store.snapshot("run")?.state)
        assertNotSame(first, store.snapshot("run"))
        // Simulate a different writer replacing the same row without consulting the snapshot cache.
        val path = context.getDatabasePath("team-decode-fixture.db")
        SQLiteDatabase.openDatabase(path.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("UPDATE encrypted_values SET encrypted_value = ? WHERE storage_key = ?",
                arrayOf(oldCiphertext, "run:run"))
        }
        assertEquals(AgentTeamExecutionState.QUEUED, store.snapshots().single().state)
        database.remove("run:run")
        assertNull(store.snapshot("run"))
        assertTrue(store.snapshots().isEmpty())
        database.clear()
    }

    @Test fun productionTranscriptFactoryReusesOnePoolAndKeepsPathsIsolated() {
        val first = IsolatedContext(ApplicationProvider.getApplicationContext())
        val other = IsolatedContext(ApplicationProvider.getApplicationContext())
        val shared = AgentTranscriptEntryDatabase.shared(first)
        try {
            val database = shared.readableDatabase
            repeat(1000) {
                assertSame(shared, AgentTranscriptEntryDatabase.shared(first))
                assertSame(database, AgentTranscriptEntryDatabase.shared(first).readableDatabase)
            }
            assertNotSame(shared, AgentTranscriptEntryDatabase.shared(other))
        } finally {
            shared.close()
            AgentTranscriptEntryDatabase.shared(other).close()
            first.cleanup(); other.cleanup()
        }
    }

    private fun AgentEncryptedDatabase.readableCiphertextsAreEncrypted(context: Context): Boolean {
        val file = context.getDatabasePath(AgentManagedResponseRows.DATABASE + ".db")
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("SELECT encrypted_value FROM encrypted_values", null).use { cursor ->
                var valid = true
                while (cursor.moveToNext()) valid = valid && AgentStorageCipher.isEncrypted(cursor.getString(0))
                valid
            }
        }
    }

    private fun isolated(block: (IsolatedContext) -> Unit) {
        val context = IsolatedContext(ApplicationProvider.getApplicationContext())
        try { block(context) } finally {
            AgentEncryptedDatabase(context, AgentManagedResponseRows.DATABASE).clear()
            context.cleanup()
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "recovery-optimization-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name)
            baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
            errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
        fun cleanup() { names.forEach(baseContext::deleteDatabase) }
    }
}
