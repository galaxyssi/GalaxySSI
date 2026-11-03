package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationExchangeReplayTest {
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "author")
    private fun request(id: String = "request") = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
        put("execution_generation", 1).put("request_id", id).put("expires_at", 20_000)
        put("type", CollaborationRemoteRecallProtocol.REQUEST).put("contract", CollaborationRemoteRecallProtocol.CONTRACT)
        put("phase", "read").put("arguments", JSONObject().put("mode", "evidence").put("evidence_id", "a".repeat(64)))
    }
    private fun result() = JSONObject().put("success", true).put("content", "original")
        .put("delivery", JSONObject().put("receipt_id", "original-challenge").put("content_sha256", "b".repeat(64)))
    private fun begin(store: CollaborationExchangeReplay, request: JSONObject = request()) =
        requireNotNull(store.acquire("desktop", request, 0).lease)

    @Test fun lostReplyReplaysTheSameOriginalChallengeWithoutRepeatingRead() {
        val store = CollaborationExchangeReplay(clock = { 0 })
        val lease = begin(store)
        val original = result()
        assertTrue(store.remember(lease, access, original))
        // Publishing was rejected or the response was lost. It is not a delivery acknowledgement.
        original.getJSONObject("delivery").put("receipt_id", "mutated-by-publisher")
        store.release(lease)
        val admission = store.acquire("desktop", request(), 0)
        assertEquals(CollaborationExchangeReplay.Outcome.REPLAY, admission.outcome)
        val replay = requireNotNull(store.read(admission.lease!!, access))
        assertEquals("original-challenge", replay.getJSONObject("delivery").getString("receipt_id"))
        assertFalse(replay.has(CollaborationEvidenceReadCoverage.FIELD))
        replay.put("content", "caller mutation")
        assertEquals("original", store.read(admission.lease, access)!!.getString("content"))
        assertTrue(store.remember(admission.lease, access, result()))
        assertThrows(IllegalStateException::class.java) { store.remember(admission.lease, access, result().put("content", "new")) }
        store.release(admission.lease)
    }

    @Test fun selectorsIdentityExpiryAndPhaseCannotChangeUnderOneNonce() {
        val store = CollaborationExchangeReplay(clock = { 0 })
        val lease = begin(store)
        val changes = AgentResultRecoveryClient.FIELDS.map { request().put(it, "other") } + listOf(
            request().put("execution_generation", 2), request().put("expires_at", 30_000),
            request().put("type", "other"), request().put("contract", "other"), request().put("phase", "confirm"),
            request().put("delivery", JSONObject().put("receipt_id", "other")),
            request().put("arguments", JSONObject().put("mode", "workspace")))
        changes.forEach { assertEquals(CollaborationExchangeReplay.Outcome.CONFLICT, store.acquire("desktop", it, 0).outcome) }
        store.remember(lease, access, result()); store.release(lease)
        changes.forEach { assertEquals(CollaborationExchangeReplay.Outcome.CONFLICT, store.acquire("desktop", it, 0).outcome) }
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, store.acquire("another-desktop", request(), 0).outcome)
    }

    @Test fun transportMetadataAndJsonKeyOrderDoNotTurnRetriesIntoNewWork() {
        val store = CollaborationExchangeReplay(clock = { 0 })
        val lease = begin(store)
        val wire = request().put("trace_id", "new-trace").put(MqttImmutableContent.RECORD_KEY, "new-inbox-key")
        val reordered = JSONObject().also { value -> wire.keys().asSequence().toList().reversed().forEach { value.put(it, wire.get(it)) } }
        assertEquals(CollaborationExchangeReplay.Outcome.IN_FLIGHT, store.acquire("desktop", reordered, 0).outcome)
        store.remember(lease, access, result()); store.release(lease)
        assertEquals(CollaborationExchangeReplay.Outcome.REPLAY, store.acquire("desktop", reordered, 0).outcome)
    }

    @Test fun replayStillRequiresExactFreshMemberBinding() {
        val store = CollaborationExchangeReplay(clock = { 0 })
        val lease = begin(store); store.remember(lease, access, result()); store.release(lease)
        val replay = begin(store)
        for (other in listOf(access.copy(groupId = "other"), access.copy(runId = "other"), access.copy(turnId = "other"),
                access.copy(nodeId = "other"), access.copy(personId = "other"), access.copy(round = 2),
                access.copy(dependencyNodes = setOf("extra")), access.copy(pinnedReads = setOf("extra"))))
            assertNull(store.read(replay, other))
        assertNotNull(store.read(replay, access))
        store.release(replay)
        assertThrows(IllegalStateException::class.java) { store.read(replay, access) }
    }

    @Test fun unfinishedResponsesAreNotCachedAndBusySlotsAreReleased() {
        val store = CollaborationExchangeReplay(clock = { 0 }, concurrency = 1)
        val lease = begin(store)
        assertEquals(CollaborationExchangeReplay.Outcome.IN_FLIGHT, store.acquire("desktop", request(), 0).outcome)
        assertEquals(CollaborationExchangeReplay.Outcome.BUSY, store.acquire("desktop", request("second"), 0).outcome)
        assertFalse(store.remember(lease, access, CollaborationRemoteRecallProtocol.unavailable()))
        store.release(lease); store.release(lease)
        val retried = store.acquire("desktop", request(), 0)
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, retried.outcome)
        store.release(retried.lease!!)
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, store.acquire("desktop", request("second"), 0).outcome)
    }

    @Test fun expirationDoesNotAcknowledgeLateWorkOrFreeAnExecutingSlot() {
        var elapsed = 0L
        val store = CollaborationExchangeReplay(clock = { elapsed }, concurrency = 1)
        val lease = begin(store)
        elapsed = 20_001
        assertFalse(store.remember(lease, access, result()))
        assertEquals(CollaborationExchangeReplay.Outcome.EXPIRED, store.acquire("desktop", request(), 20_000).outcome)
        assertEquals(CollaborationExchangeReplay.Outcome.BUSY, store.acquire("desktop", request("second").put("expires_at", 40_000), 20_001).outcome)
        store.release(lease)
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, store.acquire("desktop", request("second").put("expires_at", 40_000), 20_001).outcome)
    }

    @Test fun replayDeadlineDoesNotExtendWithRepeatedAdmission() {
        var elapsed = 0L
        val store = CollaborationExchangeReplay(clock = { elapsed })
        val lease = begin(store); store.remember(lease, access, result()); store.release(lease)
        elapsed = 19_999
        val replay = store.acquire("desktop", request(), 19_999).lease!!
        assertNotNull(store.read(replay, access))
        elapsed = 20_000
        assertNull(store.read(replay, access))
        assertFalse(store.remember(replay, access, result()))
        store.release(replay)
        assertEquals(CollaborationExchangeReplay.Outcome.EXPIRED, store.acquire("desktop", request(), 20_000).outcome)
        assertEquals(CollaborationExchangeReplay.Outcome.EXPIRED, store.acquire("desktop", request().put("expires_at", 80_001), 20_000).outcome)
    }

    @Test fun cacheCountAndUtf8BytesAreBoundedWithoutDroppingActiveWork() {
        val store = CollaborationExchangeReplay(clock = { 0 }, capacity = 1, maxBytes = 256)
        fun save(id: String, content: String): Boolean {
            val lease = begin(store, request(id))
            return try { store.remember(lease, access, JSONObject().put("success", true).put("content", content)) }
                finally { store.release(lease) }
        }
        assertTrue(save("one", "first"))
        assertFalse(save("too-big", "\u4e2d".repeat(100)))
        val one = store.acquire("desktop", request("one"), 0)
        assertEquals(CollaborationExchangeReplay.Outcome.REPLAY, one.outcome)
        store.release(one.lease!!)
        assertTrue(save("two", "second"))
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, store.acquire("desktop", request("one"), 0).outcome)
        assertEquals(CollaborationExchangeReplay.Outcome.REPLAY, store.acquire("desktop", request("two"), 0).outcome)
    }

    @Test fun processLossNeedsFreshReadAndCannotRecoverAClaimOfReceipt() {
        val old = CollaborationExchangeReplay(clock = { 0 })
        val lease = begin(old); old.remember(lease, access, result()); old.release(lease)
        val fresh = CollaborationExchangeReplay(clock = { 0 })
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, fresh.acquire("desktop", request(), 0).outcome)
    }

    @Test fun malformedOrExcessivelyNestedSelectorsDoNotCrashOrReserveCapacity() {
        val store = CollaborationExchangeReplay(clock = { 0 }, concurrency = 1)
        var nested = JSONObject().put("value", "x")
        repeat(65) { nested = JSONObject().put("nested", nested) }
        for (bad in listOf(request().put("arguments", nested), request().apply { remove("execution_generation") },
                request().put("expires_at", "not an integer")))
            assertEquals(CollaborationExchangeReplay.Outcome.INVALID, store.acquire("desktop", bad, 0).outcome)
        assertEquals(CollaborationExchangeReplay.Outcome.STARTED, store.acquire("desktop", request(), 0).outcome)
    }

    @Test fun concurrentDuplicatesAdmitOneWorkerAndBoundReplaysToo() {
        val store = CollaborationExchangeReplay(clock = { 0 }, concurrency = 1)
        val start = CountDownLatch(1)
        val threads = Executors.newFixedThreadPool(12)
        try {
            val work = (1..12).map { threads.submit<CollaborationExchangeReplay.Admission> {
                assertTrue(start.await(5, TimeUnit.SECONDS)); store.acquire("desktop", request(), 0)
            } }
            start.countDown()
            val admissions = work.map { it.get(5, TimeUnit.SECONDS) }
            assertEquals(1, admissions.count { it.outcome == CollaborationExchangeReplay.Outcome.STARTED })
            assertEquals(11, admissions.count { it.outcome == CollaborationExchangeReplay.Outcome.IN_FLIGHT })
            val lease = admissions.single { it.lease != null }.lease!!
            store.remember(lease, access, result()); store.release(lease)
            val replay = store.acquire("desktop", request(), 0)
            assertEquals(CollaborationExchangeReplay.Outcome.REPLAY, replay.outcome)
            assertEquals(CollaborationExchangeReplay.Outcome.BUSY, store.acquire("desktop", request("new"), 0).outcome)
            store.release(replay.lease!!)
        } finally { threads.shutdownNow() }
    }

    @Test fun diagnosticsAreCorrelatedWithoutResearchContentOrRawIdentity() {
        val input = request().put("private", "secret-result").put("phase", "malicious\nphase")
            .put("arguments", JSONObject().put("mode", "private-mode").put("content", "secret-result"))
        val first = CollaborationExchangeTrace.line("private-desktop", input, CollaborationExchangeTrace.Stage.ADMISSION,
            admission = CollaborationExchangeReplay.Outcome.STARTED)
        val second = CollaborationExchangeTrace.line("private-desktop", input, CollaborationExchangeTrace.Stage.PUBLISH_REJECTED, 30)
        assertEquals(first.substringBefore(" phase="), second.substringBefore(" phase="))
        listOf("private-desktop", "private-mode", "secret-result", "malicious", "contact_id").forEach { assertFalse(first.contains(it)) }
        assertTrue(first.contains("phase=unknown mode=unknown"))
        assertTrue(second.contains("stage=publish_rejected elapsed_ms=30"))
        assertFalse(second.contains("delivered"))
    }
}
