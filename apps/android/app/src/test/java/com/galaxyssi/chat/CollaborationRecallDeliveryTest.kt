package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationRecallDeliveryTest {
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "review", "reader")
    private fun request() = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
        put("execution_generation", 1).put("request_id", "read-request").put("phase", "read")
        put("arguments", JSONObject().put("mode", "evidence").put("evidence_id", "a".repeat(64)).put("sha256", "b".repeat(64)))
    }
    private fun result() = JSONObject().put("success", true).put("content", "Original \uD83D\uDE00 evidence")
    private fun acknowledgement(request: JSONObject, result: JSONObject) = JSONObject(request.toString())
        .put("phase", "confirm").put("request_id", "confirmation").put("delivery", result.getJSONObject("delivery"))
    private fun commit(args: JSONObject, hash: String) = JSONObject().put("complete", true)

    @Test fun wireDigestUsesRawUtf8NotJsonStringEncoding() {
        val store = CollaborationRecallDelivery()
        val text = "\u8bc1\u636e\n\"quoted\"\uD83D\uDE00"
        val served = store.prepare(request(), access, result().put("content", text))
        assertEquals("d04a7261a11ea301be4dffc134a83f7bace52437f78289152f19f49d1f452db5",
            served.getJSONObject("delivery").getString("content_sha256"))
        assertNotEquals(AgentNativeJsonCodec.sha256(text), served.getJSONObject("delivery").getString("content_sha256"))
    }

    @Test fun preparingDoesNotCommitAndDuplicateConfirmationUsesOnlyExactOriginalSelectors() {
        val store = CollaborationRecallDelivery()
        val request = request()
        val served = store.prepare(request, access, result())
        var writes = 0
        val confirm = acknowledgement(request, served)
        repeat(2) {
            val reply = store.confirm(confirm, access) { args, hash ->
                assertEquals(request.getJSONObject("arguments").getString("evidence_id"), args.getString("evidence_id"))
                assertEquals(MqttImmutableContent.sha256(served.getString("content")), hash)
                writes++
                JSONObject().put("complete", true)
            }
            assertTrue(reply.getBoolean("success"))
        }
        assertEquals(2, writes) // The ledger merges identical intervals idempotently.
    }

    @Test fun wrongPeerGenerationSelectorsMemberAndDigestNeverCommit() {
        val store = CollaborationRecallDelivery()
        val request = request()
        val confirm = acknowledgement(request, store.prepare(request, access, result()))
        val invalid = AgentResultRecoveryClient.FIELDS.map { JSONObject(confirm.toString()).put(it, "other") } + listOf(
            JSONObject(confirm.toString()).put("execution_generation", 2),
            JSONObject(confirm.toString()).apply { getJSONObject("arguments").put("offset", 8000) },
            JSONObject(confirm.toString()).apply { getJSONObject("delivery").put("content_sha256", "0".repeat(64)) },
            JSONObject(confirm.toString()).apply { getJSONObject("delivery").put("receipt_id", "unknown") })
        invalid.forEach { changed ->
            assertFalse(store.confirm(changed, access) { _, _ -> fail("Unauthorized confirmation"); null }.getBoolean("success"))
        }
        assertFalse(store.confirm(confirm, access.copy(nodeId = "other")) { _, _ -> fail("Wrong dispatch"); null }.getBoolean("success"))
    }

    @Test fun expiryProcessRecreationAndCapacityFailClosedWithoutDeletingSavedEvidence() {
        var now = 0L
        val store = CollaborationRecallDelivery(clock = { now }, capacity = 1)
        val request = request()
        val confirm = acknowledgement(request, store.prepare(request, access, result()))
        assertTrue(runCatching { store.prepare(request, access, result()) }.isFailure)
        assertFalse(CollaborationRecallDelivery().confirm(confirm, access, ::commit).getBoolean("success"))
        now = 60_000
        assertFalse(store.confirm(confirm, access) { _, _ -> fail("Expired receipt"); null }.getBoolean("success"))
        assertTrue(store.prepare(request, access, result()).has("delivery"))
    }

    @Test fun failedReadsAndNonEvidencePagesDoNotReserveChallenges() {
        val store = CollaborationRecallDelivery(capacity = 0)
        assertFalse(store.prepare(request(), access, result().put("success", false)).has("delivery"))
        assertFalse(store.prepare(request().apply { getJSONObject("arguments").put("mode", "workspace") }, access, result()).has("delivery"))
        assertFalse(store.prepare(request().apply { getJSONObject("arguments").remove("evidence_id") }, access, result()).has("delivery"))
    }

    @Test fun completedChallengesNeverBlockNewWorkAtCapacity() {
        val store = CollaborationRecallDelivery(capacity = 1)
        val request = request()
        repeat(1_000) {
            val confirm = acknowledgement(request, store.prepare(request, access, result()))
            assertTrue(store.confirm(confirm, access, ::commit).getBoolean("success"))
        }
    }

    @Test fun failedStorageAcknowledgementRemainsRetryableWithoutCreditingCoverage() {
        val store = CollaborationRecallDelivery()
        val request = request()
        val confirm = acknowledgement(request, store.prepare(request, access, result()))
        assertFalse(store.confirm(confirm, access) { _, _ -> null }.getBoolean("success"))
        assertTrue(runCatching { store.confirm(confirm, access) { _, _ -> error("storage unavailable") } }.isFailure)
        assertTrue(store.confirm(confirm, access, ::commit).getBoolean("success"))
    }
}
