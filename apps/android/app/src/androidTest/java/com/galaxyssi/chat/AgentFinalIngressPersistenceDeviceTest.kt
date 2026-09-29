package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated control-plane fixtures, not real-model success evidence. Never clears user stores. */
@RunWith(AndroidJUnit4::class)
class AgentFinalIngressPersistenceDeviceTest {
    @Test fun artifactOnlyFinalIsDurableBeforeAnyActivityConsumerRuns() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = "ingress-test-${UUID.randomUUID()}"
        val source = System.currentTimeMillis()
        val identity = AgentTaskIdentity(id, id, id, id)
        val rich = AgentRichContentCodec.encode(listOf(AgentRichBlock(
            id = id, type = AgentRichBlockType.IMAGE, title = "Synthetic fixture",
            uri = "https://example.invalid/fixture.png", mimeType = "image/png")))
        val payload = JSONObject().put("type", "text").put("task_status", "completed")
            .put("source_message_id", source.toString()).put("contact_id", id)
            .put("client_route_id", id).put("conversation_id", id).put("task_id", id).put("turn_id", id)
            .put("rich_output", JSONObject(rich)).put("content", "")
        var consumed: AgentConnectorResponse? = null
        AgentTaskIdentityStore.register(context, id, source, identity)
        AgentManagedConnectorResponseRegistry.register(source, id, id, id, id, id) {
            consumed = it
            true
        }
        try {
            AndroidAgentResultRecovery.persistAuthenticatedFinal(context, payload)
            val response = requireNotNull(consumed)
            assertTrue(AgentConnectorResponseStore.wasRecorded(context, response))
            assertEquals(AgentRichBlockType.IMAGE, AgentRichContentCodec.decode(response.richOutputJson).single().type)
            assertTrue(AgentConnectorResponseStore.pending(context).none { it.sourceMessageId == source })
            AndroidAgentResultRecovery.persistAuthenticatedFinal(context, payload)
            assertThrows(IllegalArgumentException::class.java) {
                AndroidAgentResultRecovery.persistAuthenticatedFinal(context,
                    JSONObject(payload.toString()).put("turn_id", "wrong-turn"))
            }
        } finally {
            AgentManagedConnectorResponseRegistry.unregisterOwner(id)
            context.getSharedPreferences("galaxyssi_agent_task_identities", 0).edit()
                .remove("$id\u001f$source").commit()
        }
    }
}
