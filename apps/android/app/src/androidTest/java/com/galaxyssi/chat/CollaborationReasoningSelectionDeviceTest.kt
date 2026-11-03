package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local checkpoint fixture only: no provider, network, user conversation or physical operation. */
@RunWith(AndroidJUnit4::class)
class CollaborationReasoningSelectionDeviceTest {
    @Test fun pinnedModelAndEffortSurviveEncryptedStoreReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "reasoning-fixture-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, name)
        val request = AgentRunRequest("isolated-group", "turn", "task", runId = name, goal = "Synthetic checkpoint")
        val selection = mapOf("collaboration_group_id" to "isolated-group", "collaboration_model_id" to "gpt-6-astra",
            CollaborationReasoningSelection.KEY to "xhigh")
        try {
            val members = listOf("author", "reviewer").map { person -> AgentTeamMember("desktop:codex",
                AgentDeliveryMode.OBSERVE, instanceId = person, context = selection + (CollaborationResearchWorkflow.PERSON to person)) }
            EncryptedAgentTeamExecutionStore(database).create(
                AgentTeamDefinition(name, "desktop:codex", members, primaryInstanceId = "author"), request)
            database.close()
            val reopened = AgentEncryptedDatabase(context, name)
            try {
                val checkpoint = requireNotNull(EncryptedAgentTeamExecutionStore(reopened).deliveryCheckpoint(name))
                assertEquals(2, checkpoint.definition.members.size)
                checkpoint.definition.members.forEach {
                    assertEquals("gpt-6-astra", it.context["collaboration_model_id"])
                    assertEquals(it.memberId, it.context[CollaborationResearchWorkflow.PERSON])
                    assertEquals(mapOf("agent_reasoning_effort" to "xhigh"),
                        CollaborationReasoningSelection.parameters(it.context, "codex-app-server-or-cli"))
                }
            } finally { reopened.clear(); reopened.close() }
        } finally { database.close() }
    }
}
