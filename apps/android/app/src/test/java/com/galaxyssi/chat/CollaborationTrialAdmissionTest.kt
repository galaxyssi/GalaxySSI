package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class CollaborationTrialAdmissionTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = linkedMapOf<String, String>()
        val commits = mutableListOf<Map<String, String>>()
        var failCommit = false
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) {
            check(!failCommit) { "storage unavailable" }
            commits += values.toMap()
            this.values.putAll(values)
        }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter {
            it.startsWith(prefix) && it > after
        }.sorted().take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "person")
    private val policy = CollaborationTrialPolicy("a".repeat(64), "cloud-target", "model", 3, 10_000)
    private fun configured(rows: Rows = Rows(), clock: () -> Long = { 1_000L }) =
        CollaborationModelCallLedger(rows, clock).also { it.configureTrial("group", "run", policy) }
    private fun request() = ModelStreamRequest("same-logical-round", ModelStreamProvider.OPENAI_COMPATIBLE,
        "https://example.invalid", emptyMap(), """{"model":"model"}""")
    private fun admit(ledger: CollaborationModelCallLedger, target: CollaborationWorkspaceAccess = access,
                      request: ModelStreamRequest = request(), strict: Boolean = true): ModelCallAccounting =
        ModelCallAccounting(request, ledger.sink(target), singleHttpRequest = strict).also { it.begin() }
    private fun count(ledger: CollaborationModelCallLedger) = ledger.trialSnapshot("group", "run")!!.getLong("admitted")
    private fun denied(reason: String, block: () -> Unit) {
        assertEquals(reason, assertThrows(ModelCallAdmissionDenied::class.java, block).reason)
    }

    @Test fun allMembersNodesAndRetriesShareDurableAdmissions() {
        val rows = Rows()
        val ledger = configured(rows)
        repeat(3) { admit(ledger, access.copy(personId = "member-$it", nodeId = "node-$it", round = it.toLong())) }
        val reopened = CollaborationModelCallLedger(rows, { 2_000L })
        denied("request_admissions_exhausted") { admit(reopened) }
        assertEquals(3L, count(reopened))
        assertEquals(3, reopened.page("group", "run").first.size)
        assertEquals(3, reopened.page("group", "run").first.map { it.getString("call_id") }.distinct().size)
        assertTrue(reopened.page("group", "run").first.all { it.getString("status") == "started" })
    }

    @Test fun concurrentWorkersCannotOverdrawAndDebitSharesReceiptTransaction() {
        val rows = Rows()
        val ledger = configured(rows)
        val pool = Executors.newFixedThreadPool(4)
        try {
            val results = (0 until 20).map { index -> pool.submit<Boolean> {
                try { admit(ledger, access.copy(personId = "member-$index")); true }
                catch (_: ModelCallAdmissionDenied) { false }
            } }.map { it.get(10, TimeUnit.SECONDS) }
            assertEquals(3, results.count { it })
            assertEquals(3L, count(ledger))
            assertEquals(3, rows.commits.drop(1).size)
            assertTrue(rows.commits.drop(1).all { transaction ->
                transaction.size == 3 && transaction.keys.count { it.endsWith(":admission") } == 1 &&
                    transaction.keys.count { it.contains(":trial:") } == 1
            })
        } finally { pool.shutdownNow() }
    }

    @Test fun failedCommitDoesNotPartiallyConsumeOrAdmit() {
        val rows = Rows()
        val ledger = configured(rows)
        rows.failCommit = true
        assertThrows(IllegalStateException::class.java) { admit(ledger) }
        assertEquals(0L, count(ledger))
        assertTrue(ledger.page("group", "run").first.isEmpty())
        rows.failCommit = false
        admit(ledger)
        assertEquals(1L, count(ledger))
    }

    @Test fun cancellationAndHttpFailureNeverRefundAnAdmission() {
        val ledger = configured()
        admit(ledger).apply { cancelled(); finish() }
        admit(ledger).apply {
            event(ModelStreamEvent.Failed("same-logical-round", ModelStreamError("HTTP_503", "unavailable")))
            finish()
        }
        admit(ledger)
        denied("request_admissions_exhausted") { admit(ledger) }
        assertEquals(setOf("cancelled", "failed", "started"), ledger.page("group", "run").first.map { it.getString("status") }.toSet())
    }

    @Test fun policyCannotBeResetChangedOrAttachedAfterDispatch() {
        val rows = Rows()
        val ledger = configured(rows)
        admit(ledger)
        ledger.configureTrial("group", "run", policy)
        assertEquals(1L, count(ledger))
        assertThrows(IllegalStateException::class.java) { ledger.configureTrial("group", "run", policy.copy(maxRequestAdmissions = 100)) }
        ledger.closeTrial("group", "run")
        CollaborationModelCallLedger(rows, { 2_000L }).configureTrial("group", "run", policy)
        denied("trial_closed") { admit(ledger) }
        val ordinary = CollaborationModelCallLedger(Rows())
        admit(ordinary, strict = false)
        assertThrows(IllegalStateException::class.java) { ordinary.configureTrial("group", "run", policy) }
    }

    @Test fun closureExpiryAndClockRollbackRejectNewWorkButPermitFinalReceipts() {
        var clock = 1_000L
        val ledger = configured(clock = { clock })
        val pending = admit(ledger)
        clock = 999
        denied("clock_moved_before_admission_window") { admit(ledger) }
        clock = 10_000
        denied("admission_window_expired") { admit(ledger) }
        ledger.closeTrial("group", "run")
        pending.cancelled()
        pending.finish()
        assertEquals(1L, count(ledger))
        assertEquals("cancelled", ledger.page("group", "run").first.single().getString("status"))
    }

    @Test fun executionTargetProviderModelAndTransportCannotChange() {
        val ledger = configured()
        assertTrue(ledger.requireTrialTarget(access, "cloud-target", "cloud-model-api"))
        denied("unmetered_or_changed_execution_target") { ledger.requireTrialTarget(access, "cloud-target", "codex") }
        denied("unmetered_or_changed_execution_target") { ledger.requireTrialTarget(access, "another", "cloud-model-api") }
        denied("unmetered_or_changed_model") { admit(ledger, request = request().copy(provider = ModelStreamProvider.GEMINI)) }
        denied("unmetered_or_changed_model") { admit(ledger, request = request().copy(transport = ModelStreamTransport.JSON_LINES)) }
        denied("unmetered_or_changed_model") { admit(ledger, request = request().copy(bodyJson = """{"model":"another"}""")) }
        denied("single_http_request_not_enforced") { admit(ledger, strict = false) }
        assertEquals(0L, count(ledger))
        admit(ledger, request = request().copy(transport = ModelStreamTransport.COMPLETE_JSON))
        assertEquals(1L, count(ledger))
    }

    @Test fun corruptCounterOrClosureFailsClosedWithoutAllocating() {
        listOf("admitted" to "0", "admitted" to -1, "admitted" to 0.5, "closed" to "false").forEach { (key, value) ->
            val rows = Rows()
            val ledger = configured(rows)
            val saved = rows.values.keys.single()
            rows.values[saved] = JSONObject(rows.values.getValue(saved)).put(key, value).toString()
            assertThrows(RuntimeException::class.java) { admit(ledger) }
            assertTrue(ledger.page("group", "run").first.isEmpty())
        }
    }

    @Test fun distinctRunsRemainIsolatedAndOrdinaryGroupsStayUnrestricted() {
        val ledger = configured()
        val other = access.copy(runId = "other")
        assertFalse(ledger.sink(other).singleHttpRequest())
        assertFalse(ledger.requireTrialTarget(other, "remote-codex", "codex"))
        repeat(6) { admit(ledger, other, strict = false) }
        assertEquals(0L, count(ledger))
        assertEquals(6, ledger.page("group", "other").first.size)
        assertTrue(ledger.sink(access).singleHttpRequest())
    }

    @Test fun revokedBindingAndReplayedAdmissionCannotSendAgain() {
        val rows = Rows()
        var authorized = true
        val ledger = CollaborationModelCallLedger(rows, { 1_000L }) { authorized }
        ledger.configureTrial("group", "run", policy)
        val call = admit(ledger)
        denied("admission_replay") { call.begin() }
        authorized = false
        assertThrows(IllegalStateException::class.java) { ledger.sink(access).singleHttpRequest() }
        assertThrows(IllegalStateException::class.java) { admit(ledger) }
        assertEquals(1L, count(ledger))
    }

    @Test fun settlementCannotRewriteAdmissionMode() {
        val ledger = configured()
        admit(ledger)
        val started = ledger.page("group", "run").first.single()
        assertThrows(IllegalStateException::class.java) {
            ledger.sink(access).write(JSONObject(started.toString()).put("status", "failed").put("single_http_request", false))
        }
        assertEquals("started", ledger.page("group", "run").first.single().getString("status"))
        assertEquals(1L, count(ledger))
    }

    @Test fun settlementCannotRewriteCapturedRequestControls() {
        val ledger = configured()
        admit(ledger)
        val started = ledger.page("group", "run").first.single()
        started.getJSONObject("request_controls").put("temperature", 0.5)
        assertThrows(IllegalStateException::class.java) { ledger.sink(access).write(started.put("status", "failed")) }
        assertEquals("started", ledger.page("group", "run").first.single().getString("status"))
    }

    @Test fun policyDecodingRejectsCoercedCountsAndInvalidBounds() {
        assertEquals(policy, CollaborationTrialPolicy.from(JSONObject(policy.json().toString())))
        listOf<Any>("3", 3.5, -1, 0, Long.MAX_VALUE, JSONObject.NULL).forEach { value ->
            assertThrows(RuntimeException::class.java) {
                CollaborationTrialPolicy.from(policy.json().put("max_request_admissions", value))
            }
        }
        assertThrows(IllegalArgumentException::class.java) { policy.copy(protocolSha256 = "not-a-digest") }
        assertThrows(IllegalArgumentException::class.java) { policy.copy(targetId = "") }
    }

    @Test fun actualTransportStopsBeforeFourthRequestAndPreservesAllAdmissions() = runBlocking {
        val ledger = configured()
        MockWebServer().use { server ->
            server.start()
            repeat(3) { server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream")
                .setBody("data: {\"model\":\"model\",\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1}}\n\ndata: [DONE]\n\n")) }
            val request = request().copy(endpoint = server.url("/chat/completions").toString(), auditSink = ledger.sink(access))
            val client = OkHttpCloudModelStreamClient(onTiming = {})
            repeat(3) { assertTrue(client.stream(request).toList().any { it is ModelStreamEvent.Completed }) }
            val failure = client.stream(request).toList().filterIsInstance<ModelStreamEvent.Failed>().single().error
            assertEquals(ModelCallAdmissionDenied.CODE, failure.code)
            assertFalse(failure.retryable)
            assertEquals(3, server.requestCount)
            assertEquals(3L, count(ledger))
            assertTrue(ledger.page("group", "run").first.all { it.getLong("http_request_attempts") == 1L })
        }
    }
}
