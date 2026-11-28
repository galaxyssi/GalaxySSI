package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMemberRecallDispatchTest {
    private val offer = CollaborationMemberRecallDispatch.Offer(
        AgentPendingDelivery(17, "group", "turn", "task", "fixture:codex"), "team", "node", "route")
    private fun payload() = JSONObject().put("type", "text").put("contact_id", "fixture:codex")
        .put("conversation_id", "group").put("task_id", "task").put("turn_id", "turn")
    private fun wire(p: JSONObject = payload(), team: String = "team", member: String = "node") =
        p.apply { CollaborationResultContract.encode(this, CollaborationResultContract.WORKSPACE, team, member) }

    @Test fun originalRequiresHostManagedOwnershipNotJustGroupFieldsOrModelFlag() {
        val params = mapOf(MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true", "team_id" to "team",
            "agent_instance_id" to "node", "idempotency_key" to "key", CollaborationMemberRecall.FLAG to "true") +
            CollaborationResultContract.assignment("group")
        val action = AgentAction(id = "a", kind = AgentActionKind.CALL_CONNECTOR, target = "member",
            risk = AgentRisk.LOW, status = AgentActionStatus.RUNNING, description = "Fixture",
            parameters = params, requiresConfirmation = false)
        val delivery = offer.delivery.copy(sourceMessageId = AgentTeamDispatchIds.sourceMessageId("member:key"))
        fun owner(a: AgentAction) = CollaborationMemberRecallDispatch.originalOwner(a, delivery)
        assertNull(owner(action))
        val request = AgentRunRequest("group", "turn", "task", stableAgentTeamMemberRunId("run", "node"),
            "run", "fixture", context = mapOf("managed_team" to true))
        val original = AgentManagedDispatchIntent.bind(action, request, delivery.contactId)
        assertEquals(request.runId, owner(original)?.ownerRunId)
        for ((key, value) in mapOf("agent_team_message" to "true", "request_kind" to "other",
                "connector_task_mode" to "other", "result_contract" to "", "team_id" to ""))
            assertNull(key, owner(original.copy(parameters = original.parameters + (key to value))))
    }

    @Test fun onlyMatchingOriginalSerializationGetsThePinnedOptIn() {
        val flag = CollaborationMemberRecall.FLAG
        assertFalse(wire().has(flag))
        CollaborationMemberRecallDispatch.during(offer) {
            for ((key, value) in mapOf("type" to "peer_chat", "conversation_id" to "private",
                    "contact_id" to "elsewhere:codex", "task_id" to "sibling-task", "turn_id" to "next",
                    "request_kind" to "screen", "connector_task_mode" to "other", "execution_mode" to "plan_only"))
                assertFalse(key, wire(payload().put(key, value)).has(flag))
            assertFalse(wire(team = "other").has(flag))
            assertFalse(wire(member = "sibling").has(flag))
            assertFalse(CollaborationMemberRecallDispatch.during(null) { wire().has(flag) })
            val sibling = java.util.concurrent.FutureTask { wire().has(flag) }
            Thread(sibling).start()
            assertFalse(sibling.get(5, java.util.concurrent.TimeUnit.SECONDS))
            val result = wire()
            assertEquals(true, result.get(flag))
            assertEquals("route", result.getString("client_route_id"))
            assertFalse(wire().has(flag))
        }
        assertFalse(wire().has(flag))
    }

    @Test fun exceptionBeforeSerializationCannotOptInAnotherSend() {
        assertThrows(IllegalStateException::class.java) {
            CollaborationMemberRecallDispatch.during(offer) { error("send cancelled") }
        }
        assertFalse(wire().has(CollaborationMemberRecall.FLAG))
    }
}
