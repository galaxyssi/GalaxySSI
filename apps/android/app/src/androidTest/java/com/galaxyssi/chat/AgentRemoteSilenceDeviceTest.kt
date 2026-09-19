package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRemoteSilenceDeviceTest {
    @Test fun probesAreCoalescedAndAuthenticatedResponseRenewsLease() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val source = Long.MAX_VALUE - 70
        val metadata = mapOf("resource_started_at" to "1000")
        try {
            AndroidAgentRemoteSilence.retire(context, source)
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 1000))
            repeat(100) { assertFalse(AndroidAgentRemoteSilence.shouldProbe(context, source, 1001)) }
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 31000))
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 61000))
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 151000))
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 241000))
            assertTrue(AndroidAgentRemoteSilence.expired(context, source, metadata, 301000))
            AndroidAgentRemoteSilence.observed(context, source, 301000)
            assertFalse(AndroidAgentRemoteSilence.expired(context, source, metadata, 302000))
            assertFalse(AndroidAgentRemoteSilence.expired(context, source, metadata, 94 * 3600000L))
            assertTrue(AndroidAgentRemoteSilence.shouldProbe(context, source, 94 * 3600000L))
            assertFalse(AndroidAgentRemoteSilence.expired(context, source, metadata, 94 * 3600000L))
        } finally { AndroidAgentRemoteSilence.retire(context, source) }
    }

    @Test fun exhaustedNoModelTaskStopsAndPersistsInsteadOfWaitingForever() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val source = Long.MAX_VALUE - 71
        val sessions = InMemoryAgentSessionStore()
        val action = AgentAction("silence-test", AgentActionKind.CALL_CONNECTOR, "Test Desktop", AgentRisk.HIGH,
            AgentActionStatus.WAITING_RESPONSE, "Modify remote files")
        val runtime = MobileNativeAgent(context, sessionStore = sessions,
            memoryStore = InMemoryAgentMemoryStore(),
            taskStore = object : AgentTaskStore {
                override fun upsert(record: AgentTaskRecord) = Unit
                override fun recent(limit: Int) = emptyList<AgentTaskRecord>()
                override fun forSession(sessionId: String, limit: Int) = emptyList<AgentTaskRecord>()
                override fun find(taskId: String): AgentTaskRecord? = null
                override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
                override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
                override fun delete(taskIds: Set<String>) = Unit
                override fun clear() = Unit
            },
            connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
            actionEffectReplayStore = InMemoryAgentNativeToolReplayStore(), screenObservationOverride = false)
        runtime.currentGoal = "Modify remote files"
        runtime.currentPlan = AgentPlan(runtime.currentGoal, ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Test"), emptyList(), listOf(action))
        runtime.phase = AgentPhase.WAITING_RESPONSE
        runtime.lastActionResult = AgentActionResult(action.id, true, "Waiting", mapOf(
            "source_message_id" to source.toString(), "resource_location" to "desktop",
            "resource_started_at" to "1000", "resource_id" to "silence-test-desktop", "awaiting_response" to "true"))
        assertNull(runtime.handleConnectorTimeout(source - 1, AgentConnectorTimeoutStage.NOT_ACCEPTED, true))
        val result = requireNotNull(runtime.handleConnectorTimeout(source, AgentConnectorTimeoutStage.NOT_ACCEPTED, true))
        assertEquals(AgentPhase.FAILED, result.phase)
        assertEquals(AgentPhase.FAILED, sessions.load()?.phase)
        assertEquals("false", result.lastActionResult?.metadata?.get("awaiting_response"))
        assertEquals("true", result.lastActionResult?.metadata?.get("delivery_confirmation_unknown"))
        assertNull(runtime.handleConnectorTimeout(source, AgentConnectorTimeoutStage.NOT_ACCEPTED, true))
    }
}
