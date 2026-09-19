package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentResearchDeliveryDeviceTest {
    @Test fun backgroundAndManagedDeliveryPersistWithoutActivity() = fixture { context, payload ->
        val trace = receipt()
        payload.put("progress_event", JSONObject().put("metadata", JSONObject().put("research_trace", trace)))
        repeat(2) { AgentResearchTraceStore.receiveAuthenticated(context, payload) }
        assertEquals(1, AgentResearchTraceStore.read(context, "conversation", "turn").queries.size)
        assertEquals("Source", AgentResearchTraceStore.read(context, "conversation", "turn").sources.single().title)
        assertFalse(AgentResearchTraceStore.read(context, "conversation", "other-turn").visible)
    }

    @Test fun recoveredFinalRestoresMissingProgressBeforePublishingResponse() = fixture { context, payload ->
        payload.put("type", "text").put("task_status", "completed").put("content", "Answer")
            .put("research_trace", receipt())
        AndroidAgentResultRecovery.publishResult(context, payload, requireNotNull(AgentRemoteOutcomeCodec.decode(payload, "Answer")))
        assertEquals("https://example.org/source", AgentResearchTraceStore.read(context, "conversation", "turn").sources.single().url)
    }

    @Test fun replayIsIdempotentAndDeletedConversationStaysDeleted() = fixture { context, payload ->
        payload.put("events", JSONArray().put(JSONObject().put("metadata", JSONObject().put("research_trace", receipt()))))
        repeat(3) { AgentResearchTraceStore.receiveAuthenticated(context, payload) }
        assertEquals(1, AgentResearchTraceStore.read(context, "conversation", "turn").sources.size)
        AgentResearchTraceStore.delete(context, "conversation")
        AgentResearchTraceStore.receiveAuthenticated(context, payload)
        assertFalse(AgentResearchTraceStore.read(context, "conversation", "turn").visible)
    }

    @Test fun rejectsOtherTurnsPeersAndOldExecutions() = fixture { context, payload ->
        payload.put("research_trace", receipt())
        AgentResearchTraceStore.receiveAuthenticated(context, JSONObject(payload.toString()).put("turn_id", "wrong"))
        AgentResearchTraceStore.receiveAuthenticated(context, JSONObject(payload.toString()).put("peer_chat", true))
        assertFalse(AgentResearchTraceStore.read(context, "conversation", "turn").visible)
        AgentConnectorResponseStore.observeExecution(context,
            requireNotNull(AgentRemoteOutcomeCodec.observation(payload)).copy(executionGeneration = 2))
        AgentResearchTraceStore.receiveAuthenticated(context, payload)
        assertFalse(AgentResearchTraceStore.read(context, "conversation", "turn").visible)
    }

    private fun receipt() = AgentResearchTrace(listOf("news"),
        listOf(AgentResearchTrace.Source("https://example.org/source", "Source")), remote = true).toJson()

    private fun fixture(block: (Context, JSONObject) -> Unit) {
        val context = IsolatedContext(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            AgentTaskIdentityStore.register(context, "contact", 42,
                AgentTaskIdentity("route", "conversation", "task", "turn"))
            block(context, JSONObject().put("type", "agent_task_event").put("contact_id", "contact")
                .put("source_message_id", "42").put("client_route_id", "route")
                .put("conversation_id", "conversation").put("task_id", "task").put("turn_id", "turn")
                .put("execution_generation", 1).put("status_seq", 1).put("task_status", "running"))
        } finally { context.close() }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "research-delivery-${UUID.randomUUID()}-"
        private val preferences = mutableSetOf<String>()
        private val databases = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name)
            else baseContext.getDatabasePath(prefix + name).also { databases.add(it.name) }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
            errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            preferences.add(prefix + name)
            return baseContext.getSharedPreferences(prefix + name, mode)
        }
        fun close() {
            AgentConnectorResponseStore.clear(this)
            AgentPendingDeliveryStore.close(this)
            databases.forEach(baseContext::deleteDatabase)
            preferences.forEach(baseContext::deleteSharedPreferences)
        }
    }
}
