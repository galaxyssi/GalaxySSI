package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class MqttOutboxRetryWindowTest {
    @Test fun backlogCannotFloodOneRouteAndOtherRoutesRemainIndependent() {
        val gate = MqttOutboxRetryWindow({ 0L }, capacity = 2)
        assertEquals(0L, gate.acquire("a", "one"))
        assertEquals(0L, gate.acquire("a", "two"))
        repeat(4_000) { assertEquals(30_000L, gate.acquire("a", "old-$it")) }
        assertEquals(0L, gate.acquire("b", "other"))
        gate.release("one")
        assertEquals(0L, gate.acquire("a", "three"))
    }

    @Test fun missingReceiptEventuallyReleasesCreditWithoutMarkingDelivered() {
        var now = 0L
        val gate = MqttOutboxRetryWindow({ now }, capacity = 1)
        assertEquals(0L, gate.acquire("a", "one"))
        now = 29_000L
        assertEquals(1_000L, gate.acquire("a", "one"))
        assertEquals(1_000L, gate.acquire("a", "two"))
        now = 30_000L
        assertEquals(0L, gate.acquire("a", "two"))
    }

    @Test fun onlyRecomputableQueriesAreTransient() {
        assertTrue(MqttQueryDeliveryPolicy.hasRetryOwner("agent_task_result_received"))
        assertFalse(MqttQueryDeliveryPolicy.isTransient("agent_task_result_received"))
        listOf("connector_status_request", "agent_task_recovery_request", "agent_task_result_page_request")
            .forEach { assertTrue(MqttQueryDeliveryPolicy.isTransient(it)) }
        listOf("peer_message", "agent_task", "desktop_tool_call", "agent_task_cancel", "client_revoked",
            "artifact_receipt", "input_attachment_chunk", "evolution_task_create", "unknown")
            .forEach { assertFalse(MqttQueryDeliveryPolicy.isTransient(it)) }
    }
}
