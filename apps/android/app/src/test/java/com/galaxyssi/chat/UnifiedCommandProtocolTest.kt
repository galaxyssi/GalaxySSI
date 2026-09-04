package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UnifiedCommandProtocolTest {
    @Test
    fun requestPayloadUsesSharedDesktopMqttCommandContract() {
        val payload = UnifiedCommandProtocol.requestPayload(
            commandId = "commands.list",
            args = mapOf("dry_run" to true),
            messageId = "message-1"
        )

        assertEquals("unified_command", payload.getString("type"))
        assertEquals("message-1", payload.getString("message_id"))
        assertEquals("message-1", payload.getString("source_message_id"))
        assertEquals("commands.list", payload.getString("command_id"))
        assertTrue(payload.getJSONObject("args").getBoolean("dry_run"))
        assertEquals("paired_phone", payload.getString("requested_by"))
    }

    @Test
    fun slashPayloadCanOmitCommandId() {
        val payload = UnifiedCommandProtocol.requestPayload(
            commandId = "",
            slash = "/commands",
            messageId = "message-2"
        )

        assertEquals("", payload.getString("command_id"))
        assertEquals("/commands", payload.getString("slash"))
    }

    @Test
    fun decodeResultReturnsStructuredCommandResult() {
        val payload = JSONObject()
            .put("type", "unified_command_result")
            .put("command_id", "commands.list")
            .put("command_status", "completed")
            .put("source_message_id", "message-1")
            .put("result", JSONObject()
                .put("status", "completed")
                .put("command_id", "commands.list")
                .put("run_id", "run-1")
                .put("data", JSONObject().put("catalog_size", 753))
                .put("display", JSONObject().put("type", "command_list")))

        val result = UnifiedCommandProtocol.decodeResult(payload)!!

        assertEquals("commands.list", result.commandId)
        assertEquals("completed", result.status)
        assertEquals("run-1", result.runId)
        assertEquals("message-1", result.sourceMessageId)
        assertEquals(753, result.data.getInt("catalog_size"))
        assertEquals("command_list", result.display.getString("type"))
    }

    @Test
    fun decodeResultIgnoresOtherPayloadTypes() {
        assertNull(UnifiedCommandProtocol.decodeResult(JSONObject().put("type", "text")))
    }
}
