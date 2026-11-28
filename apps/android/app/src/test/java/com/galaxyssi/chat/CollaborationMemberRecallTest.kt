package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMemberRecallTest {
    private val binding = CollaborationWorkspaceAccess("fixture-group", "run", "turn", 1, "review-node", "member")
    private val member = CollaborationMember("member", "Member", "fixture:codex", "Desktop")
    private val group = CollaborationGroup(binding.groupId, listOf(member))
    private val owner = AgentManagedResponseRecord(stableAgentTeamMemberRunId("run", "review-node"),
        "run", member.agentId, AgentDeliveryMode.RESPOND, 17, "fixture:codex", binding.groupId, "turn", "task")

    @Test fun membershipMustMatchLiveOwnerNodePersonAndProvider() {
        fun matches(b: CollaborationWorkspaceAccess = binding, o: AgentManagedResponseRecord = owner,
            g: CollaborationGroup? = group, c: AgentTeamUserControl = AgentTeamUserControl.RUN) =
            CollaborationMemberRecall.matches(b, o, g, c)
        assertTrue(matches())
        assertFalse(matches(g = null))
        assertFalse(matches(g = group.copy(members = emptyList())))
        assertFalse(matches(g = group.copy(members = listOf(member.copy(agentId = "other:codex")))))
        assertFalse(matches(g = group.copy(conversationId = "other-group")))
        assertFalse(matches(b = binding.copy(nodeId = "other-node")))
        assertFalse(matches(b = binding.copy(personId = "other-member")))
        assertFalse(matches(o = owner.copy(conversationId = "private-chat")))
        assertFalse(matches(o = owner.copy(turnId = "other-turn")))
        assertFalse(matches(o = owner.copy(supervisorRunId = "other-run")))
        assertFalse(matches(o = owner.copy(deliveryMode = AgentDeliveryMode.OBSERVE)))
        assertFalse(matches(o = owner.copy(state = AgentManagedResponseState.COMPLETED)))
        assertFalse(matches(c = AgentTeamUserControl.PAUSE))
        assertFalse(matches(c = AgentTeamUserControl.STOP))
    }

    @Test fun contactIsTheVerifiedCodexChildOfTheAuthenticatedDesktop() {
        fun contact() = JSONObject().put("agent_id", "codex").put("desktop_id", "fixture")
            .put("delivery_mode", "pc_connector").put("trust_state", "verified")
        assertTrue(CollaborationMemberRecall.codexContact(contact(), "fixture"))
        assertFalse(CollaborationMemberRecall.codexContact(contact(), "elsewhere"))
        for ((key, value) in mapOf("agent_id" to "other", "desktop_id" to "",
                "delivery_mode" to "cloud_api", "trust_state" to "pending", "deleted" to true)) {
            assertFalse(key, CollaborationMemberRecall.codexContact(contact().put(key, value), "fixture"))
        }
    }

    @Test fun replayReauthenticatesWithoutContentOrCachedSuccessAndCannotSwitchAssignment() {
        val request = JSONObject().apply {
            AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
            put("execution_generation", 1).put("request_id", "nonce").put("expires_at", 20_000)
            put("phase", "authorize").put("arguments", JSONObject())
            put("type", CollaborationRemoteRecallProtocol.REQUEST).put("contract", CollaborationRemoteRecallProtocol.CONTRACT)
        }
        val replies = CollaborationExchangeReplay(clock = { 1 })
        fun probe(first: CollaborationWorkspaceAccess?, last: CollaborationWorkspaceAccess?): JSONObject {
            val lease = requireNotNull(replies.acquire("desktop", request, 1).lease)
            return try {
                var reads = 0
                assertNull(replies.read(lease, binding))
                CollaborationMemberRecall.authorize(replies, lease) {
                    (if (++reads == 1) first else last)?.let { CollaborationMemberRecall.Probe(it) }
                }.also {
                    if (it.getBoolean("success")) assertEquals(2, reads)
                }
            } finally { replies.release(lease) }
        }
        repeat(2) {
            val result = probe(binding, binding)
            assertEquals(setOf("success", "status"), result.keys().asSequence().toSet())
            assertEquals(true, result.get("success"))
            assertEquals("authorized", result.get("status"))
        }
        assertFalse(probe(binding, null).getBoolean("success"))
        assertFalse(probe(null, binding).getBoolean("success"))
        val changed = binding.copy(dependencyNodes = setOf("new-node"))
        assertFalse(probe(binding, changed).getBoolean("success"))
        assertFalse(probe(changed, changed).getBoolean("success"))
        assertEquals(CollaborationExchangeReplay.Outcome.CONFLICT,
            replies.acquire("desktop", request.put("phase", "read"), 1).outcome)
    }

    @Test fun onlyNextObservedGenerationGetsANegativeHintAndCatchUpRequiresAFreshNonce() {
        val current = CollaborationMemberRecall.Generation.CURRENT
        val next = CollaborationMemberRecall.Generation.NEXT
        val unavailable = CollaborationMemberRecall.Generation.UNAVAILABLE
        assertEquals(current, CollaborationMemberRecall.generation(null, 1))
        assertEquals(unavailable, CollaborationMemberRecall.generation(null, 2))
        assertEquals(unavailable, CollaborationMemberRecall.generation(3, 2))
        assertEquals(unavailable, CollaborationMemberRecall.generation(3, 5))
        assertEquals(next, CollaborationMemberRecall.generation(3, 4))
        assertEquals(current, CollaborationMemberRecall.generation(4, 4))
        val replies = CollaborationExchangeReplay(clock = { 1 })
        fun probe(nonce: String, vararg observations: CollaborationMemberRecall.Probe?): JSONObject {
            val request = JSONObject().apply {
                AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
                put("execution_generation", 4).put("request_id", nonce).put("expires_at", 20_000)
                put("phase", "authorize").put("arguments", JSONObject())
                put("type", CollaborationRemoteRecallProtocol.REQUEST).put("contract", CollaborationRemoteRecallProtocol.CONTRACT)
            }
            val lease = requireNotNull(replies.acquire("desktop", request, 1).lease)
            val states = observations.iterator()
            return try { CollaborationMemberRecall.authorize(replies, lease) { states.next() } }
                finally { replies.release(lease) }
        }
        val waiting = CollaborationMemberRecall.Probe(binding, next)
        val ready = CollaborationMemberRecall.Probe(binding)
        val hint = probe("first", waiting, waiting)
        assertEquals(setOf("success", "status"), hint.keys().asSequence().toSet())
        assertEquals(false, hint.get("success"))
        assertEquals("generation_not_ready", hint.getString("status"))
        assertEquals("unavailable", probe("first", ready, ready).getString("status"))
        assertEquals("authorized", probe("fresh", ready, ready).getString("status"))
        assertEquals("unavailable", probe("revoked", waiting, null).getString("status"))
        assertEquals("unavailable", probe("rebound", waiting, waiting.copy(binding = binding.copy(round = 2))).getString("status"))
        assertEquals("authorized", probe("in-flight", waiting, ready, ready).getString("status"))
        assertEquals("unavailable", probe("lost", waiting, ready, null).getString("status"))
    }
}
