package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CloudResearchCheckpointDeviceTest {
    @Test fun researchObservationsReopenEncryptedAndIsolated() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-research-${UUID.randomUUID()}"
        val database = "$name.db"
        val scope = AgentModelLoopScope(name, name, "turn", "task", name, "research", "action")
        val marker = "private-research-observation-marker"
        val first = AgentRunEventStore(context, database)
        try {
            EncryptedAgentModelLoopJournal(context, first).withLease(scope) { records ->
                CloudResearchCheckpoint(records, "same-input").record("web_search",
                    JSONObject().put("query", "public research probe"), marker + "x".repeat(30_000))
            }
        } finally { first.close() }
        val reopened = AgentRunEventStore(context, database)
        try {
            val journal = EncryptedAgentModelLoopJournal(context, reopened)
            journal.withLease(scope) { records ->
                val saved = CloudResearchCheckpoint(records, "same-input").restore().single()
                val cache = CloudWebToolLoopProgress()
                cache.record(saved.tool, saved.arguments, saved.output)
                assertEquals(saved.output, cache.cached(saved.tool, saved.arguments))
                assertTrue(saved.output.startsWith(marker))
            }
            journal.withLease(scope.copy(conversation = "other-conversation")) {
                assertTrue(CloudResearchCheckpoint(it, "same-input").restore().isEmpty())
            }
            context.openOrCreateDatabase(database, 0, null).use { raw ->
                raw.rawQuery("SELECT count(*) FROM run_events WHERE encrypted_event LIKE ?",
                    arrayOf("%$marker%")).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(0, cursor.getInt(0))
                }
            }
        } finally { reopened.close(); context.deleteDatabase(database) }
    }
}
