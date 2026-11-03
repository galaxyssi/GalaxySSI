package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSavedToolTestTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.sorted().take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "person")
    private fun input() = JSONObject().put("mode", "start").put("execution_id", "candidate-v1")
        .put("tool_test_plan", JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)))
        .put("timeout_ms", 10_000)

    @Test fun retryAndFreshTransportNonceDoNotRerun() {
        val rows = Rows()
        val first = CollaborationSavedToolTest(rows, access, "process")
        assertTrue(first.start(input()).launch)
        assertFalse(first.start(input()).launch)
        assertFalse(CollaborationSavedToolTest(rows, access, "process").start(input()).launch)
        assertEquals(1, rows.values.size)
    }

    @Test fun sameIdCannotChangePlanTimeoutOrCode() {
        val store = CollaborationSavedToolTest(Rows(), access, "process")
        store.start(input())
        val variants = listOf(input().put("timeout_ms", 20_000), input().apply { getJSONObject("tool_test_plan").put("revision", 2) }, input().put("source", "pass"))
        variants.forEach { assertTrue(runCatching { store.start(it) }.isFailure) }
    }

    @Test fun finishedReceiptSurvivesRestartWithoutEffect() {
        val rows = Rows()
        val store = CollaborationSavedToolTest(rows, access, "one")
        store.start(input())
        assertTrue(store.running("candidate-v1"))
        store.finish("candidate-v1", JSONObject().put("passed", false).put("evidence", "original"))
        val restarted = CollaborationSavedToolTest(rows, access, "two")
        assertFalse(restarted.start(input()).launch)
        val result = restarted.describe(restarted.read("candidate-v1"))
        assertEquals("finished", result.getString("status"))
        assertFalse(result.getJSONObject("result").getBoolean("passed"))
        assertEquals("original", result.getJSONObject("result").getString("evidence"))
    }

    @Test fun processLossPreservesUncertaintyAndNeverAutomaticallyRetries() {
        for (running in listOf(false, true)) {
            val rows = Rows()
            val old = CollaborationSavedToolTest(rows, access, "old")
            old.start(input())
            if (running) old.running("candidate-v1")
            val fresh = CollaborationSavedToolTest(rows, access, "new")
            assertEquals("interrupted", fresh.read("candidate-v1")!!.getString("state"))
            assertFalse(fresh.start(input()).launch)
            assertFalse(fresh.running("candidate-v1"))
            assertTrue(runCatching { fresh.finish("candidate-v1", JSONObject()) }.isFailure)
        }
    }

    @Test fun cancelBeforeExecutionPreventsLaunch() {
        val store = CollaborationSavedToolTest(Rows(), access, "process")
        store.start(input())
        assertEquals("cancelled", store.cancel("candidate-v1")!!.getString("state"))
        assertFalse(store.running("candidate-v1"))
        assertFalse(store.start(input()).launch)
    }

    @Test fun cancellingRunningTestKeepsFinalEvidence() {
        val store = CollaborationSavedToolTest(Rows(), access, "process")
        store.start(input()); store.running("candidate-v1")
        assertEquals("cancelling", store.cancel("candidate-v1")!!.getString("state"))
        store.finish("candidate-v1", JSONObject().put("native_status", "cancelled"))
        assertEquals("finished", store.read("candidate-v1")!!.getString("state"))
        assertEquals("finished", store.cancel("candidate-v1")!!.getString("state"))
    }

    @Test fun noObservationCanBeBorrowedFromAnotherMemberRunOrTurn() {
        val rows = Rows()
        CollaborationSavedToolTest(rows, access, "process").start(input())
        for (other in listOf(access.copy(personId = "other"), access.copy(nodeId = "other"), access.copy(groupId = "other"),
            access.copy(runId = "other"), access.copy(turnId = "other"), access.copy(round = 2))) {
            assertNull(CollaborationSavedToolTest(rows, other, "process").read("candidate-v1"))
        }
    }

    @Test fun invalidRequestsDoNotReachExecution() {
        val variants = listOf(input().put("execution_id", "../other"), input().put("execution_id", ""), input().put("member_id", "other"),
            input().put("timeout_ms", 0), input().put("timeout_ms", true), input().put("timeout_ms", 1.5),
            input().put("timeout_ms", 1_800_001), input().put("mode", "run"),
            input().apply { getJSONObject("tool_test_plan").put("revision", 1.0) },
            input().apply { getJSONObject("tool_test_plan").put("sha256", "A".repeat(64)) },
            input().apply { getJSONObject("tool_test_plan").put("expected", true) })
        variants.forEach { assertTrue(it.toString(), runCatching { CollaborationSavedToolTest.validate(it) }.isFailure) }
    }

    @Test fun statusAndCancelCannotSupplyNewCodeOrRuntime() {
        for (mode in listOf("status", "cancel")) {
            val value = JSONObject().put("mode", mode).put("execution_id", "test")
            CollaborationSavedToolTest.validate(value)
            assertTrue(runCatching { CollaborationSavedToolTest.validate(value.put("timeout_ms", 100)) }.isFailure)
        }
    }

    @Test fun nativeInputUsesExistingSavedCodeCompilerAndDisablesNetwork() {
        val native = CollaborationSavedToolTest.nativeInput(input())
        assertFalse(native["network_enabled"] as Boolean)
        assertFalse(native.containsKey("source"))
        val saved = JSONObject(native).getJSONObject(CollaborationToolRuntime.INPUT)
        assertEquals("test", saved.getString("mode"))
        assertEquals(input().getJSONObject("tool_test_plan").toString(), saved.getJSONObject("tool_test_plan").toString())
    }

    @Test fun unknownStatusDoesNotCreateExecution() {
        val rows = Rows(); val store = CollaborationSavedToolTest(rows, access, "process")
        assertEquals("not_recorded", store.describe(store.read("unknown")).getString("status"))
        assertNull(store.cancel("unknown"))
        assertTrue(rows.values.isEmpty())
    }

    @Test fun reorderedJsonStillNamesSameAttempt() {
        val store = CollaborationSavedToolTest(Rows(), access, "process")
        store.start(input())
        val changedOrder = JSONObject().put("timeout_ms", 10_000).put("tool_test_plan", input().getJSONObject("tool_test_plan"))
            .put("execution_id", "candidate-v1").put("mode", "start")
        assertFalse(store.start(changedOrder).launch)
    }

    @Test fun simultaneousDuplicateAdmissionHasOneExecutorOwner() {
        val store = CollaborationSavedToolTest(Rows(), access, "process")
        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
        try {
            val work = (1..20).map { java.util.concurrent.Callable { store.start(input()).launch } }
            assertEquals(1, pool.invokeAll(work).count { it.get() })
        } finally { pool.shutdownNow() }
    }

    @Test fun envelopeRequiresExactProtocolScopePhaseAndLiveNonce() {
        val request = JSONObject().put("type", CollaborationSavedToolTest.REQUEST).put("contract", CollaborationSavedToolTest.CONTRACT)
            .put("request_id", "nonce").put("expires_at", 2_000).put("execution_generation", 1)
            .put("arguments", input()).put("phase", "start")
        AgentResultRecoveryClient.FIELDS.forEach { request.put(it, if (it == "agent_id") "codex" else "fixture") }
        assertTrue(CollaborationSavedToolTest.valid(request, 1_000))
        for ((field, value) in listOf("type" to "collaboration_recall_request", "contract" to "wrong", "phase" to "read",
            "execution_generation" to 0, "expires_at" to 999, "expires_at" to 62_000, "agent_id" to "other")) {
            assertFalse(field, CollaborationSavedToolTest.valid(JSONObject(request.toString()).put(field, value), 1_000))
        }
        assertFalse(CollaborationSavedToolTest.valid(JSONObject(request.toString()).put("delivery", JSONObject()), 1_000))
    }

    @Test fun revokedGroupCannotBeResurrectedByLateExecutionResult() {
        val rows = Rows()
        var authorized = true
        val workspace = CollaborationResearchWorkspace(rows, authorized = { authorized })
        val journal = workspace.savedToolTests(access, "process")
        journal.start(input()); journal.running("candidate-v1")
        authorized = false
        rows.values.clear()
        assertTrue(runCatching { journal.finish("candidate-v1", JSONObject().put("passed", true)) }.isFailure)
        assertTrue(rows.values.isEmpty())
    }
}
