package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateVerificationStateTest {
    @Test fun emptyAndStructurallyCompleteTerminalCheckpointsAreSettledNotCertified() {
        assertFalse(CollaborationCandidateVerificationState.pending("[]"))
        assertFalse(CollaborationCandidateVerificationState.pending(state(cycle("done"))))
    }

    @Test fun allActivePhasesRemainPending() {
        listOf("validate", "repair", "recheck").forEach { phase ->
            val raw = state(cycle(phase))
            assertEquals(1, CollaborationCandidateVerificationState.read(raw).length())
            assertTrue(CollaborationCandidateVerificationState.pending(raw))
        }
    }

    @Test fun everyRequiredTerminalFieldIsCheckedEvenAfterAnActiveCycle() {
        listOf("id", "object_id", "target", "phase", "editor", "reviewer", "criterion", "result").forEach { key ->
            val broken = cycle("done", 2).apply { remove(key) }
            rejected(state(broken))
            rejected(state(cycle(), broken))
        }
    }

    @Test fun exactTargetAndBasisReferencesRejectCoercedOrOutOfRangeVersions() {
        listOf<Any>("1", 1.5, 0, -1, Int.MAX_VALUE.toLong() + 1).forEach { version ->
            listOf("target", "review").forEach { key ->
                rejected(state(cycle("repair").apply { getJSONObject(key).put("revision", version) }))
            }
        }
        rejected(state(cycle().apply { getJSONObject("target").put("object_id", hash(50)) }))
        rejected(state(cycle().apply { getJSONObject("target").put("sha256", "forged") }))
    }

    @Test fun duplicateObjectCycleAndDispatchIdentitiesFailClosed() {
        listOf("object_id", "id", "node_id").forEach { key ->
            val first = cycle()
            val duplicate = cycle(number = 2).put(key, first.get(key))
            if (key == "object_id") duplicate.getJSONObject("target").put(key, first.get(key))
            rejected(state(first, duplicate))
        }
    }

    @Test fun activeCheckpointNeedsDispatchAndRepairOrRecheckNeedsBasis() {
        listOf("validate", "repair", "recheck").forEach { phase ->
            rejected(state(cycle(phase).apply { remove("node_id") }))
            rejected(state(cycle(phase).put("node_id", " ")))
            rejected(state(cycle(phase).put("result", "supported")))
            if (phase != "validate") rejected(state(cycle(phase).apply { remove("review") }))
        }
    }

    @Test fun malformedContractOrMemberIdentityDoesNotBecomeSettled() {
        listOf("editor", "reviewer", "result").forEach { key -> rejected(state(cycle("done").put(key, " "))) }
        rejected(state(cycle("done").put("editor", "reviewer")))
        listOf("id", "requirement", "verification", "required_observations").forEach { key ->
            rejected(state(cycle("done").apply { getJSONObject("criterion").remove(key) }))
        }
        rejected(state(cycle("done").apply { getJSONObject("criterion").put("verification", "physical") }))
        rejected(state(cycle("done").apply { getJSONObject("criterion").put("required_observations", JSONArray()) }))
    }

    @Test fun activeAndCompletedCandidateCountsHaveNoFixedLimit() {
        val active = JSONArray((1..1000).map { cycle(number = it) }).toString()
        assertEquals(1000, CollaborationCandidateVerificationState.read(active).length())
        assertTrue(CollaborationCandidateVerificationState.pending(active))
        val completed = (1..30).map { cycle("done", it) }
        assertFalse(CollaborationCandidateVerificationState.pending(JSONArray(completed).toString()))
    }

    @Test fun pendingRequestEnvelopeRoundTripsAndPreventsFalseSettlement() {
        val pending = (1..1000).map { JSONObject().put("target", JSONObject().put("object_id", hash(it))) }
        val raw = CollaborationCandidateVerificationState.encode(JSONArray().put(cycle("done")), pending)
        val saved = CollaborationCandidateVerificationState.checkpoint(raw)
        assertEquals(1000, saved.pendingRequests.length())
        assertEquals(1, saved.cycles.length())
        assertTrue(CollaborationCandidateVerificationState.pending(raw))
        val corrected = JSONObject().put("target", JSONObject().put("object_id", hash(1))).put("reviewer", "corrected")
        val merged = CollaborationCandidateVerificationState.requests(saved.pendingRequests, JSONArray().put(corrected))
        assertEquals(1000, merged.size)
        assertEquals("corrected", merged.first().getString("reviewer"))
    }

    @Test fun staleRequestReplayCannotOverwriteANewerPendingVersion() {
        val newer = JSONObject().put("target", JSONObject().put("object_id", hash(1)).put("revision", 3).put("sha256", hash(3)))
        val older = JSONObject().put("target", JSONObject().put("object_id", hash(1)).put("revision", 1).put("sha256", hash(1)))
        val merged = CollaborationCandidateVerificationState.requests(JSONArray().put(newer), JSONArray().put(older))
        assertEquals(2, merged.size)
        assertEquals(newer.toString(), merged.first().toString())
        val corrected = JSONObject(newer.toString()).put("reviewer", "authorized-reviewer")
        val next = CollaborationCandidateVerificationState.requests(JSONArray(merged), JSONArray().put(corrected))
        assertEquals(2, next.size)
        assertEquals("authorized-reviewer", next.first().getString("reviewer"))
    }

    @Test fun malformedJsonAndUnknownPhasesFailClosedWithoutRewritingInput() {
        listOf("not-json", "{}", "[null]", "[7]", state(cycle("unknown"))).forEach(::rejected)
        val raw = state(cycle("done"))
        val copy = CollaborationCandidateVerificationState.read(raw)
        copy.getJSONObject(0).put("phase", "corrupt")
        assertFalse(CollaborationCandidateVerificationState.pending(raw))
    }

    private fun rejected(raw: String) {
        assertTrue(raw, runCatching { CollaborationCandidateVerificationState.read(raw) }.isFailure)
        assertTrue(raw, CollaborationCandidateVerificationState.pending(raw))
    }

    private fun state(vararg cycles: JSONObject) = JSONArray(cycles.toList()).toString()
    private fun hash(value: Int) = value.toString(16).padStart(64, '0')
    private fun cycle(phase: String = "validate", number: Int = 1): JSONObject = JSONObject()
        .put("id", hash(number + 100)).put("object_id", hash(number)).put("phase", phase)
        .put("target", JSONObject().put("object_id", hash(number)).put("revision", 1).put("sha256", hash(10)))
        .put("editor", "editor").put("reviewer", "reviewer").put("node_id", "dispatch-$number")
        .put("criterion", JSONObject().put("id", "accuracy").put("requirement", "Documented accuracy")
            .put("verification", "documentary").put("required_observations", JSONArray().put(JSONObject()
                .put("origin", "android_cloud_tool").put("tool", "original_check"))))
        .apply {
            if (phase in setOf("repair", "recheck")) put("review", JSONObject()
                .put("object_id", hash(500)).put("revision", 1).put("sha256", hash(501)))
            if (phase == "done") put("result", "Member assessment recorded, not host verified")
        }
}
