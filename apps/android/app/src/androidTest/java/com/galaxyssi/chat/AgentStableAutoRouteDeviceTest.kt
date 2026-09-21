package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentStableAutoRouteDeviceTest {
    @Test fun tenConversationsKeepIndependentStickyTargetsAndRejectStaleTurns() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scopes = (1..10).map { "stable-auto-test-${UUID.randomUUID()}" }
        val codex = AgentCallableTarget("test:codex", "Codex", AgentConnectorKind.AGENT,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT))
        val cloud = codex.copy(id = "test:deepseek", title = "DeepSeek", kind = AgentConnectorKind.MODEL)
        val targets = listOf(cloud, codex)
        try {
            scopes.forEachIndexed { index, scope ->
                assertEquals(codex.id, AgentStableAutoRouteStore.target(context, scope, targets)?.id)
                AgentStableAutoRouteStore.beginTurn(context, scope, "turn-$index")
                if (index % 2 == 0) AgentStableAutoRouteStore.recordDispatch(context, scope, "turn-$index", cloud.id)
            }
            scopes.forEachIndexed { index, scope ->
                val expected = if (index % 2 == 0) cloud.id else codex.id
                AgentStableAutoRouteStore.recordDispatch(context, scope, "stale-turn", "wrong-target")
                assertEquals(expected, AgentStableAutoRouteStore.target(context, scope, targets)?.id)
            }
        } finally {
            AgentModelSelectionSettings.clearConversations(context, scopes)
        }
    }
}
