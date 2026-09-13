package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale

class MqttTrafficPolicyTest {
    private fun payload(type: String) = JSONObject().put("type", type)

    @Test fun onlyTypedControlsUseCriticalTraffic() {
        for (type in listOf("agent_task_cancel", "desktop_tool_call_cancel", "client_revoked", "desktop_control_revoke", "pairing_revoked")) {
            assertEquals("control", MqttTrafficPolicy.classify(payload(type)))
        }
        assertEquals("message", MqttTrafficPolicy.classify(payload("text").put("content", "agent_task_cancel stop")))
    }

    @Test fun terminalEventsAndResultsRetainFinalPriority() {
        for (status in listOf("completed", "failed", "cancelled", "canceled")) {
            assertEquals("final", MqttTrafficPolicy.classify(payload("agent_task_event").put("task_status", status)))
            assertEquals("final", MqttTrafficPolicy.classify(payload("agent_task_event").put("status", status)))
        }
        for (type in listOf("text", "error", "rich_output")) {
            assertEquals("final", MqttTrafficPolicy.classify(payload(type).put("task_id", "run")))
            assertEquals("message", MqttTrafficPolicy.classify(payload(type)))
        }
        assertEquals("progress", MqttTrafficPolicy.classify(payload("agent_task_event").put("status", "running")))
    }

    @Test fun chunksAndReceiptsAreNotHedgedLikeUserText() {
        assertEquals("receipt", MqttTrafficPolicy.classify(payload("delivery_ack")))
        assertEquals("chunk", MqttTrafficPolicy.classify(payload("input_attachment_chunk")))
        assertEquals("chunk", MqttTrafficPolicy.classify(payload("artifact_chunk")))
        assertEquals("message", MqttTrafficPolicy.classify(payload("new_application_kind")))
    }

    @Test fun persistedTrafficParsesWithoutDependingOnDeviceLocale() {
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"))
            for (value in MqttMultipathPolicy.Traffic.entries) {
                assertEquals(value, MqttTrafficPolicy.parse(value.name.lowercase(Locale.ROOT)))
            }
            assertThrows(IllegalArgumentException::class.java) { MqttTrafficPolicy.parse("urgent") }
        } finally { Locale.setDefault(previous) }
    }
}
