package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSavedToolRunTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = linkedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.sorted().take(limit)
    }
    private val access = CollaborationWorkspaceAccess("group", "future-run", "future-turn", 0, "reuse", "worker")
    private fun input(record: String = "tool_release") = JSONObject().put("mode", "start").put("execution_id", "reuse-v1")
        .put(record, JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)))
        .put("parameters", JSONObject().put("values", JSONArray("[3,1,2]"))).put("timeout_ms", 10_000)

    @Test fun releaseAndChannelReuseExactNativeCompilerWithoutCodeOrNetworkOverride() {
        for (record in listOf("tool_release", "capability_channel")) {
            val native = JSONObject(CollaborationSavedToolTest.nativeInput(input(record)))
            assertFalse(native.getBoolean("network_enabled"))
            val call = native.getJSONObject(CollaborationToolRuntime.INPUT)
            assertEquals(setOf("mode", record, "parameters"), call.keys().asSequence().toSet())
            assertEquals("run", call.getString("mode"))
            assertEquals(input(record).getJSONObject(record).toString(), call.getJSONObject(record).toString())
            assertEquals("[3,1,2]", call.getJSONObject("parameters").getJSONArray("values").toString())
        }
    }

    @Test fun retriesAndRestartRecoverCompletedReuseWithoutRunningAgain() {
        val rows = Rows()
        val first = CollaborationSavedToolTest(rows, access, "one")
        assertTrue(first.start(input()).launch)
        assertFalse(first.start(input()).launch)
        assertTrue(first.running("reuse-v1"))
        first.finish("reuse-v1", JSONObject().put("passed", true).put("execution_mode", "run").put("evidence", "original"))
        val fresh = CollaborationSavedToolTest(rows, access, "two")
        assertFalse(fresh.start(input()).launch)
        val result = fresh.describe(fresh.read("reuse-v1"))
        assertEquals("run", result.getString("execution_mode"))
        assertEquals("finished", result.getString("status"))
        assertEquals("original", result.getJSONObject("result").getString("evidence"))
    }

    @Test fun sameIdCannotSwapInputsReleaseChannelTimeoutOrOperation() {
        val first = CollaborationSavedToolTest(Rows(), access, "one")
        first.start(input())
        val changed = listOf(input().put("parameters", JSONObject().put("values", JSONArray("[42]"))),
            input("capability_channel"), input().put("timeout_ms", 20_000),
            input().apply { getJSONObject("tool_release").put("revision", 2) },
            input().apply { put("tool_test_plan", remove("tool_release")); remove("parameters") })
        changed.forEach { assertTrue(runCatching { first.start(it) }.isFailure) }
        assertEquals(input().toString(), first.read("reuse-v1")!!.getJSONObject("input").toString())
    }

    @Test fun invalidRequestsAndAmbiguousSelectorsAreRejectedBeforeNativeExecution() {
        val invalid = listOf(input().put("source", "print(1)"), input().put("network_enabled", true),
            input().put("parameters", JSONArray()), input().put("parameters", JSONObject.NULL),
            input().apply { remove("parameters") }, input().put("member_id", "other"),
            input().put("tool_test_plan", input().getJSONObject("tool_release")),
            input().put("capability_channel", input().getJSONObject("tool_release")),
            input().put("mode", "run"), input().apply { getJSONObject("tool_release").put("revision", 1.0) })
        invalid.forEach { assertTrue(it.toString(), runCatching { CollaborationSavedToolTest.nativeInput(it) }.isFailure) }
    }

    @Test fun cancellationAndProcessLossNeverAutomaticallyRepeatSavedRun() {
        for (cancel in listOf(false, true)) {
            val rows = Rows()
            val first = CollaborationSavedToolTest(rows, access, "one")
            first.start(input())
            if (cancel) first.cancel("reuse-v1") else first.running("reuse-v1")
            val fresh = CollaborationSavedToolTest(rows, access, "two")
            assertEquals(if (cancel) "cancelled" else "interrupted", fresh.read("reuse-v1")!!.getString("state"))
            assertFalse(fresh.start(input()).launch)
            assertFalse(fresh.running("reuse-v1"))
        }
    }

    @Test fun reuseCannotBorrowAnotherMemberOrTurnOutcome() {
        val rows = Rows()
        CollaborationSavedToolTest(rows, access, "one").start(input())
        for (other in listOf(access.copy(personId = "other"), access.copy(nodeId = "other"),
            access.copy(groupId = "other"), access.copy(runId = "other"), access.copy(turnId = "other"))) {
            assertNull(CollaborationSavedToolTest(rows, other, "one").read("reuse-v1"))
        }
    }

    @Test fun authenticatedEnvelopeAcceptsReuseButNotReadOnlyRecall() {
        val request = JSONObject().put("type", CollaborationSavedToolTest.REQUEST).put("contract", CollaborationSavedToolTest.CONTRACT)
            .put("request_id", "nonce").put("expires_at", 2_000).put("execution_generation", 1)
            .put("arguments", input()).put("phase", "start")
        AgentResultRecoveryClient.FIELDS.forEach { request.put(it, if (it == "agent_id") "codex" else "fixture") }
        assertTrue(CollaborationSavedToolTest.valid(request, 1_000))
        assertFalse(CollaborationSavedToolTest.valid(JSONObject(request.toString()).put("type", "collaboration_recall_request"), 1_000))
        assertFalse(CollaborationSavedToolTest.valid(JSONObject(request.toString()).put("execution_generation", 0), 1_000))
    }
}
