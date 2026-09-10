package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.AgentTransportTiming
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryTransportTraceTest {
    private fun item(task: String = "task") = JSONObject().put("client_route_id", "route")
        .put("conversation_id", "conversation").put("task_id", task).put("turn_id", "turn")
        .put("contact_id", "contact").put("source_message_id", "42").put("agent_id", "codex")
    private fun batch(type: String = "agent_task_recovery_request") = JSONObject().put("type", type)
        .put("request_id", "nonce").put("client_route_id", "route").put("items", JSONArray(listOf(item(), item("second"))))

    @Test fun requestAndResponseUseOneTraceWithoutChangingProtocolFields() {
        for (type in listOf("agent_task_recovery_request", "agent_task_recovery_result")) {
            val payload = batch(type)
            val before = payload.toString()
            assertEquals("task", AgentTransportTiming.taskId(payload))
            assertEquals(before, payload.toString())
            payload.put("task_id", "unrelated-top-level")
            assertEquals("task", AgentTransportTiming.taskId(payload))
        }
        assertEquals("normal", AgentTransportTiming.taskId(JSONObject().put("type", "text").put("task_id", "normal")))
        assertEquals("", AgentTransportTiming.taskId(batch().put("peer_chat", true)))
    }

    @Test fun incompleteMixedRouteAndOversizedBatchesDoNotCreateMisleadingSamples() {
        for (field in item().keys()) {
            for (value in listOf<Any>("", " ", "x".repeat(201), 42, JSONObject.NULL)) {
                val invalid = batch()
                invalid.getJSONArray("items").getJSONObject(1).put(field, value)
                assertEquals(field, "", AgentTransportTiming.taskId(invalid))
            }
        }
        for (size in listOf(0, 33)) {
            assertEquals("", AgentTransportTiming.taskId(batch().put("items", JSONArray(List(size) { item("task-$it") }))))
        }
        assertEquals("", AgentTransportTiming.taskId(batch().put("request_id", "x".repeat(129))))
        assertEquals("", AgentTransportTiming.taskId(batch().put("client_route_id", "wrong")))
        assertEquals("", AgentTransportTiming.taskId(batch().put("items", JSONArray(listOf("not-an-identity")))))
    }

    @Test fun diagnosticsDistinguishLateResponsesWithoutExposingIdentityOrContent(): Unit = runBlocking {
        val notices = mutableListOf<Pair<String, String>>()
        val client = AgentRemoteRecoveryClient { hash, outcome -> notices.add(hash to outcome) }
        lateinit var sent: JSONObject
        assertTrue(client.query("desktop", "route", listOf(item()), timeoutMillis = 5) { sent = it; true }.isEmpty())
        val response = JSONObject(sent.toString()).put("content", "private content")
        assertFalse(client.receive(response, "desktop"))
        assertEquals(listOf("started", "transport_accepted", "response_timeout", "late_or_unknown"), notices.map { it.second })
        assertEquals(1, notices.map { it.first }.distinct().size)
        assertTrue(notices.all { it.first.matches(Regex("[a-f0-9]{64}")) })
        assertFalse(notices.toString().contains(sent.getString("request_id")))
        assertFalse(notices.toString().contains("private content"))
    }

    @Test fun diagnosticFailuresCannotAlterRecoveryOrCleanup(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient { _, _ -> error("diagnostic sink failed") }
        lateinit var sent: JSONObject
        val query = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", "route", listOf(item())) { sent = it; true }
        }
        assertFalse(client.receive(sent, "wrong"))
        assertTrue(client.receive(sent, "desktop"))
        assertEquals("task", query.await().single().getString("task_id"))
        assertEquals(0, client.pendingCount)
    }

    @Test fun diagnosticReasonsMatchRejectedAndAcceptedBoundaries(): Unit = runBlocking {
        val notices = mutableListOf<String>()
        val client = AgentRemoteRecoveryClient { _, outcome -> notices.add(outcome) }
        lateinit var sent: JSONObject
        val query = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", "route", listOf(item())) { sent = it; true }
        }
        assertFalse(client.receive(sent, "wrong"))
        assertFalse(client.receive(JSONObject(sent.toString()).put("client_route_id", "wrong"), "desktop"))
        assertFalse(client.receive(JSONObject(sent.toString()).put("items", JSONArray()), "desktop"))
        val mismatched = JSONObject(sent.toString())
        mismatched.getJSONArray("items").getJSONObject(0).put("task_id", "other")
        assertFalse(client.receive(mismatched, "desktop"))
        assertTrue(client.receive(sent, "desktop"))
        query.await()
        assertTrue(notices.containsAll(listOf("wrong_desktop", "wrong_route", "invalid_batch", "identity_mismatch",
            "accepted", "authenticated_response")))
    }
}
