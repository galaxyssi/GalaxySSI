package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareDiscussionRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun legacyResponseStopsWaitingWithoutRemovingTheQuestionOrReceipt() {
        withHealthTurn { store, conversation, turn ->
            val source = Long.MAX_VALUE - SystemClock.elapsedRealtime()
            val response = AgentConnectorResponse(source, "synthetic-desktop",
                """{"execution_location":"phone","actions":[]}""", conversation, turn, turn)
            AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, conversation, turn, turn, response.contactId))
            try {
                assertTrue(AgentConnectorResponseStore.append(context, response))
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { it.deferSupervisedProjectControlResponse(response) }
                    val key = "health-legacy-interrupted:$turn"
                    await { store.entriesForTurn(turn).any { it.dedupeKey == key } }
                    scenario.onActivity { it.deferSupervisedProjectControlResponse(response) }
                    assertTrue(AgentConnectorResponseStore.contains(context, response))
                    val entries = store.entriesForTurn(turn)
                    assertEquals(1, entries.count { it.dedupeKey == key })
                    assertTrue(entries.any { it.role == AgentTranscriptRole.USER && it.text == QUESTION })
                    assertFalse(entries.any { it.text.contains("execution_location") })
                }
            } finally {
                AgentConnectorResponseStore.remove(context, response)
                AgentPendingDeliveryStore.remove(context, source)
            }
        }
    }

    @Test fun scopedForegroundTurnWithoutAValidGrantStillCreatesAStoppedClock() {
        withHealthTurn { store, conversation, turn ->
            val workspaces = EncryptedAgentWorkspaceStore(context)
            val goal = HealthCareDiscussionPolicy.prompt(QUESTION, "{}")
            val action = AgentAction("fixture-health", AgentActionKind.CALL_CONNECTOR, "Synthetic model",
                AgentRisk.LOW, AgentActionStatus.PENDING_CONFIRMATION, "Review health discussion",
                parameters = mapOf("connector_id" to "synthetic-model", "prompt" to goal,
                    "manual_target_locked" to "true", "routing_fallback_ids" to "",
                    "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE),
                requiresConfirmation = false)
            try {
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { activity ->
                        activity.executeConcurrentAgentGoal(goal,
                            AgentConversationContext(conversation, "", emptyList(), true, trackingPaused = true),
                            conversation, turn, action, AgentTaskExecutionMode.AUTO_COMPLETE,
                            approvedHealthDiscussion = true)
                    }
                    await { workspaces.find(turn)?.status?.isTerminal == true }
                    val workspace = requireNotNull(workspaces.find(turn))
                    assertEquals(conversation, workspace.conversationId)
                    assertTrue(AgentTranscriptPresentationPolicy.processClockStopsFor(workspace.status))
                    assertTrue(store.entriesForTurn(turn).any {
                        it.role == AgentTranscriptRole.PROCESS && it.dedupeKey == "agent-loop-context:$turn"
                    })
                }
            } finally {
                SharedPreferencesAgentSessionStore(context, "task:$turn").clear()
                workspaces.delete(turn)
            }
        }
    }

    private fun withHealthTurn(block: (AgentTranscriptStore, String, String) -> Unit) {
        val store = AgentTranscriptStore(context)
        val conversation = store.createAgentConversation("Synthetic health test",
            globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + UUID.randomUUID(),
            privateMode = true, trackingPaused = true).id
        val turn = UUID.randomUUID().toString()
        try {
            store.append(AgentTranscriptRole.USER, QUESTION, conversationId = conversation, turnId = turn, taskId = turn)
            block(store, conversation, turn)
        } finally { store.deleteConversation(conversation) }
    }

    private fun await(matches: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            if (matches()) return
            SystemClock.sleep(100)
        }
        assertTrue("Expected health task state was not observed", matches())
    }

    private companion object { const val QUESTION = "Explain the synthetic fixture." }
}
