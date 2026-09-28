package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentManagedDeliveryDeviceTest {
    @Test fun onlyRegisteredManagedChildrenBypassTheParentTurnHead() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val owner = "managed-delivery-test-${UUID.randomUUID()}"
        val conversation = "$owner-conversation"
        val turn = "$owner-turn"
        val source = (UUID.randomUUID().mostSignificantBits ushr 2).coerceAtLeast(2)
        val child = source + 1
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val record = AgentManagedResponseRecord(owner, "$owner-supervisor", "codex", AgentDeliveryMode.RESPOND,
            child, "test-contact", conversation, turn, "$owner-task")
        try {
            AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, conversation, turn, "$owner-parent", "test-contact"))
            assertTrue(AgentPendingDeliveryStore.isSuperseded(context, child, conversation, turn))
            ledger.register(record)
            assertFalse(AgentPendingDeliveryStore.isSuperseded(context, child, conversation, turn))
            assertFalse(EncryptedAgentManagedResponseLedger(context).ownsRecordedSource(child, "wrong", turn))
            assertFalse(EncryptedAgentManagedResponseLedger(context).ownsRecordedSource(child, conversation, "wrong"))
            ledger.markApplied(owner)
            assertFalse(AgentPendingDeliveryStore.isSuperseded(context, child, conversation, turn))
            val response = AgentConnectorResponse(child, record.contactId, "Synthetic child result", conversation, turn, record.taskId)
            assertTrue(AgentConnectorResponseBus.publish(context, response))
            assertTrue(AgentConnectorResponseStore.wasRecorded(context, response))
            assertFalse(AgentConnectorResponseStore.contains(context, response))
            assertTrue(AgentConnectorResponseBus.publish(context, response))
            assertFalse(AgentConnectorResponseStore.contains(context, response))
            ledger.register(record)
            AgentPendingDeliveryStore.remove(context, child)
            assertTrue(AgentPendingDeliveryStore.isSuperseded(context, child, conversation, turn))
            assertNotNull(AgentPendingDeliveryStore.find(context, source))
        } finally {
            ledger.removeOwner(owner)
            AgentPendingDeliveryStore.remove(context, child)
            AgentPendingDeliveryStore.remove(context, source)
        }
    }
}
