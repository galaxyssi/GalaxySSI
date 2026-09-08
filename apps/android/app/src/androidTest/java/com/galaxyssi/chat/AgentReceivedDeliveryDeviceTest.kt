package com.galaxyssi.chat

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentReceivedDeliveryDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun lateFailureCannotInvalidateReceivedAnswerBeforeOrAfterConsumption() {
        val id = UUID.randomUUID().toString()
        val source = System.currentTimeMillis()
        val store = AgentTranscriptStore(context, "received-test-$id")
        val conversation = store.createConversation("Received delivery regression", privateMode = true)
        val turn = "turn-$id"
        val contact = "test-contact-$id"
        val delivery = AgentPendingDelivery(source, conversation.id, turn, "task-$id", contact)
        val response = AgentConnectorResponse(source, contact, "verified-$id", conversation.id, turn, "remote-$id")
        store.append(AgentTranscriptRole.USER, "Regression request", conversationId = conversation.id, turnId = turn)
        AgentPendingDeliveryStore.put(context, delivery)
        try {
            assertTrue(AgentConnectorResponseStore.append(context, response))
            assertNull(AgentDeliveryFailureRecorder.record(context, source, contact, "unexpected failure"))
            assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
            assertEquals(response, AgentConnectorResponseStore.find(context, response))
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.onDeliveryFailed(source, contact, "delivery_retry_exhausted")
                    assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
                }
            }
            assertFalse(store.list(conversation.id).any { it.dedupeKey == AgentDeliveryFailureRecorder.dedupeKey(source) })
            AgentConnectorResponseStore.remove(context, response)
            assertTrue(AgentConnectorResponseStore.hasReceivedDelivery(context, source, contact))
            assertNull(AgentDeliveryFailureRecorder.record(context, source, contact, "unexpected late failure"))
            assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
        } finally {
            AgentConnectorResponseStore.remove(context, response)
            AgentPendingDeliveryStore.remove(context, source)
            store.deleteConversation(conversation.id)
        }
    }

    @Test fun realFailureWithoutReplyStillMarksOnlyItsOwnRequest() {
        val id = UUID.randomUUID().toString()
        val source = System.currentTimeMillis() + 1
        val store = AgentTranscriptStore(context, "unreceived-test-$id")
        val conversation = store.createConversation("Unreceived regression", privateMode = true)
        val delivery = AgentPendingDelivery(source, conversation.id, "turn-$id", "task-$id", "peer-$id")
        AgentPendingDeliveryStore.put(context, delivery)
        try {
            assertEquals(delivery, AgentDeliveryFailureRecorder.record(context, source, delivery.contactId, "expected failure"))
            assertTrue(AgentTerminalDeliveryStore.isTerminal(context, source))
            assertTrue(store.list(conversation.id).any { it.text == "expected failure" })
        } finally {
            AgentPendingDeliveryStore.remove(context, source)
            store.deleteConversation(conversation.id)
            AgentEncryptedPreferences(context, "galaxyssi_agent_terminal_deliveries").remove("source:$source")
        }
    }
}
