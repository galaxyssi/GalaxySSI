package com.galaxyssi.chat

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationLateEvidenceTest {
    private fun fields() = JSONObject().apply { AgentResultRecoveryClient.FIELDS.forEach { put(it, it) } }
        .put("agent_id", "codex").put("execution_generation", 2)
    private fun index(after: Long = 0) = JSONObject().put("mode", "index").put("after_sequence", after).put("inline_page_bytes", 16384)
    private fun page() = JSONObject().put("mode", "page").put("evidence_id", "a".repeat(64))
        .put("sha256", "b".repeat(64)).put("page_index", 1)
    private fun response(request: JSONObject) = JSONObject(request.toString()).put("type", "agent_task_evidence")
        .put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT).put("status", "ready")

    @Test fun lateReplyIsReusedWithoutPublishingAnotherQuery(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        assertNull(client.query("desktop", fields(), index(), 5) { sent = it; true })
        assertEquals(0, client.pendingCount); assertEquals(1, client.lateCount)
        val reasons = mutableListOf<String>()
        val reply = response(sent).put("archive_final", false)
        assertTrue(client.receive(reply, "desktop", reasons::add))
        reply.put("archive_final", true)
        assertFalse(client.receive(response(sent), "desktop", reasons::add))
        val result = client.query("desktop", fields(), index()) { error("No duplicate transport needed") }!!
        assertEquals(sent.getString("request_id"), result.getString("request_id"))
        assertFalse(result.getBoolean("archive_final"))
        assertEquals(listOf("accepted_late", "already_completed"), reasons)
        assertEquals(0, client.lateCount); assertEquals(0, client.pendingCount)
    }

    @Test fun retryReusesNonceAndCanReceiveOriginalReplyDuringWait(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var first: JSONObject
        client.query("desktop", fields(), page(), 5) { first = it; true }
        lateinit var retried: JSONObject
        val job = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", fields(), page()) { retried = it; true }
        }
        assertEquals(first.getString("request_id"), retried.getString("request_id"))
        assertEquals(1, client.pendingCount); assertEquals(0, client.lateCount)
        assertTrue(client.receive(response(first), "desktop"))
        assertNotNull(job.await()); assertEquals(0, client.pendingCount)
    }

    @Test fun lateReplyStillRequiresAllScopeAndPageBindings(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        client.query("desktop", fields(), page(), 5) { sent = it; true }
        for (key in AgentResultRecoveryClient.FIELDS + listOf("execution_generation", "request_id", "type", "contract", "mode", "status", "evidence_id", "sha256", "page_index")) {
            assertFalse(key, client.receive(response(sent).put(key, if (key in listOf("page_index", "execution_generation")) 9 else "wrong"), "desktop"))
        }
        assertFalse(client.receive(response(sent), "other-desktop"))
        assertTrue(client.receive(response(sent), "desktop"))
        assertNotNull(client.query("desktop", fields(), page()) { error("Already received") })
    }

    @Test fun changedScopeDesktopOrSelectionNeverConsumesRetainedReply(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var old: JSONObject
        client.query("desktop", fields(), index(), 5) { old = it; true }
        client.receive(response(old), "desktop")
        val changes = AgentResultRecoveryClient.FIELDS.filter { it != "agent_id" }.map { key ->
            Triple("desktop", fields().put(key, "other"), index())
        } + listOf(Triple("other-desktop", fields(), index()),
            Triple("desktop", fields().put("execution_generation", 3), index()),
            Triple("desktop", fields(), index(1)), Triple("desktop", fields(), page()),
            Triple("desktop", fields(), index().put("inline_page_bytes", 0)))
        changes.forEach { (desktop, scope, selection) ->
            val result = client.query(desktop, scope, selection) {
                assertNotEquals(old.getString("request_id"), it.getString("request_id"))
                client.receive(response(it), desktop)
            }
            assertNotNull(result)
        }
        assertNotNull(client.query("desktop", fields(), index()) { error("Original still retained") })
    }

    @Test fun activeSameSelectionQueriesHaveIndependentOwnership(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var first: JSONObject
        lateinit var second: JSONObject
        val a = async(start = CoroutineStart.UNDISPATCHED) { client.query("desktop", fields(), index()) { first = it; true } }
        val b = async(start = CoroutineStart.UNDISPATCHED) { client.query("desktop", fields(), index()) { second = it; true } }
        assertNotEquals(first.getString("request_id"), second.getString("request_id"))
        a.cancel(); a.join()
        assertFalse(client.receive(response(first), "desktop"))
        assertTrue(client.receive(response(second), "desktop")); assertNotNull(b.await())
        assertEquals(0, client.lateCount)
    }

    @Test fun immediateConsumptionStillAcknowledgesTheLiveReply(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        val job = async(Dispatchers.Unconfined) { client.query("desktop", fields(), index()) { sent = it; true } }
        val reasons = mutableListOf<String>()
        assertTrue(client.receive(response(sent), "desktop", reasons::add))
        assertTrue(job.isCompleted)
        assertNotNull(job.await())
        assertEquals(listOf("accepted"), reasons)
        assertEquals(0, client.pendingCount)
    }

    @Test fun cancelOrRejectedRetryRevokesRetainedOwnership(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        client.query("desktop", fields(), index(), 5) { sent = it; true }
        val job = async(start = CoroutineStart.UNDISPATCHED) { client.query("desktop", fields(), index()) { true } }
        job.cancel(); job.join()
        assertFalse(client.receive(response(sent), "desktop")); assertEquals(0, client.lateCount)
        client.query("desktop", fields(), index(), 5) { sent = it; true }
        assertNull(client.query("desktop", fields(), index()) { false })
        assertFalse(client.receive(response(sent), "desktop")); assertEquals(0, client.lateCount)
    }

    @Test fun expiredReplyCannotBeReusedAndActiveWaitIsNotEvicted(): Unit = runBlocking {
        var now = 0L
        val client = CollaborationRemoteEvidenceClient(nowMillis = { now }, lateRetentionMillis = 1000, maxLateRequests = 1)
        lateinit var expired: JSONObject
        client.query("desktop", fields(), index(), 5) { expired = it; true }
        now = 1001
        assertFalse(client.receive(response(expired), "desktop"))
        lateinit var active: JSONObject
        val job = async(start = CoroutineStart.UNDISPATCHED) { client.query("desktop", fields(), index()) { active = it; true } }
        assertNotEquals(expired.getString("request_id"), active.getString("request_id"))
        repeat(3) { client.query("desktop", fields(), index(it + 1L), 5) { true } }
        assertEquals(1, client.lateCount); assertEquals(1, client.pendingCount)
        assertTrue(client.receive(response(active), "desktop")); assertNotNull(job.await())
    }

    @Test fun retainedBytesAreBoundedAndOversizedLateResponseCanBeQueriedAgain(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient(maxLateBytes = 3000)
        val sent = mutableListOf<JSONObject>()
        repeat(4) { i ->
            client.query("desktop", fields(), index(i.toLong()), 5) { sent.add(it); true }
            client.receive(response(sent.last()).put("body", "x".repeat(1000)), "desktop")
        }
        assertTrue(client.lateBytes <= 3000); assertTrue(client.lateCount < 4)
        assertFalse(client.receive(response(sent.first()), "desktop"))
        lateinit var large: JSONObject
        client.query("desktop", fields(), index(9), 5) { large = it; true }
        assertFalse(client.receive(response(large).put("body", "x".repeat(4000)), "desktop"))
        assertNotNull(client.query("desktop", fields(), index(9)) {
            assertNotEquals(large.getString("request_id"), it.getString("request_id"))
            client.receive(response(it), "desktop")
        })
    }
}
