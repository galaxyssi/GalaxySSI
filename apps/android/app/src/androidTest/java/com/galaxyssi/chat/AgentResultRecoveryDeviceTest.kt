package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentResultRecoveryDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun payload() = JSONObject().put("client_route_id", "isolated-route")
        .put("conversation_id", "isolated-conversation").put("task_id", "isolated-task").put("turn_id", "isolated-turn")
        .put("contact_id", "isolated-contact").put("source_message_id", "42").put("agent_id", "codex")
        .put("type", "text").put("task_status", "completed")
        .put("content", "\u8fd9\u662f\u91cd\u542f\u540e\u53d6\u56de\u7684\u5b8c\u6574\u56de\u590d\u3002".repeat(12000))

    @Test fun pagedResultPersistsAcrossInboxReopenAndDuplicateRedelivery(): Unit = runBlocking {
        val name = "result-recovery-test-${UUID.randomUUID()}.db"
        var inbox = AgentConnectorResponseInbox(context, name, "legacy-$name")
        try {
            val result = fetch(payload())!!
            val response = AgentConnectorResponse(42, "isolated-contact", result.getString("content"),
                "isolated-conversation", "isolated-turn", "isolated-task")
            assertTrue(inbox.append(response))
            assertTrue(inbox.wasRecorded(response))
            inbox.close()
            inbox = AgentConnectorResponseInbox(context, name, "legacy-$name")
            assertEquals(response.content, inbox.page().responses.single().content)
            assertFalse(inbox.append(response))
            assertEquals(1, inbox.page().responses.size)
            assertTrue(inbox.acknowledge(response))
            inbox.close()
            inbox = AgentConnectorResponseInbox(context, name, "legacy-$name")
            assertTrue(inbox.wasRecorded(response))
            assertFalse(inbox.append(response))
            assertTrue(inbox.page().responses.isEmpty())
        } finally { inbox.close(); context.deleteDatabase(name); context.deleteSharedPreferences("legacy-$name") }
    }

    @Test fun acknowledgementCannotBeInferredFromTransportReceipt() {
        val name = "result-recovery-test-${UUID.randomUUID()}.db"
        AgentConnectorResponseInbox(context, name, "legacy-$name").use { inbox ->
            val response = AgentConnectorResponse(42, "isolated-contact", "answer", "conversation", "turn", "task")
            assertFalse(inbox.wasRecorded(response))
            assertFalse(inbox.acknowledge(response))
            assertFalse(inbox.wasRecorded(response))
            assertTrue(inbox.append(response))
            assertTrue(inbox.wasRecorded(response))
            assertFalse(inbox.wasRecorded(response.copy(taskId = "another-task")))
        }
        context.deleteDatabase(name)
        context.deleteSharedPreferences("legacy-$name")
    }

    @Test fun corruptResultNeverEntersEncryptedInbox(): Unit = runBlocking {
        assertNull(fetch(payload(), corrupt = true))
    }

    private suspend fun fetch(body: JSONObject, corrupt: Boolean = false): JSONObject? {
        val bytes = body.toString().toByteArray(Charsets.UTF_8)
        val client = AgentResultRecoveryClient()
        val result = try {
            client.fetch("isolated-desktop", body) { request ->
                val index = request.getInt("page_index")
                val offset = index * AgentResultRecoveryClient.PAGE_BYTES
                val chunk = bytes.copyOfRange(offset, minOf(bytes.size, offset + AgentResultRecoveryClient.PAGE_BYTES))
                val page = JSONObject(request.toString()).put("type", "agent_task_result_page").put("status", "ready")
                    .put("sha256", AgentResultRecoveryClient.sha256(bytes)).put("total_bytes", bytes.size)
                    .put("page_count", (bytes.size + AgentResultRecoveryClient.PAGE_BYTES - 1) / AgentResultRecoveryClient.PAGE_BYTES)
                    .put("page_sha256", if (corrupt) "0".repeat(64) else AgentResultRecoveryClient.sha256(chunk))
                    .put("data_b64", Base64.getEncoder().encodeToString(chunk))
                chunk.fill(0)
                client.receive(page, "isolated-desktop")
            }
        } finally { bytes.fill(0) }
        assertEquals(0, client.pendingCount)
        return result
    }
}
