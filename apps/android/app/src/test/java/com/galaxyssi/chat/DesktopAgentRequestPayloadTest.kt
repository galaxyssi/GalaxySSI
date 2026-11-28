package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class DesktopAgentRequestPayloadTest {
    private fun payload(member: String, team: String, model: String, effort: String, followup: Boolean = false) = desktopAgentRequestPayload(
        content = "synthetic input", contactId = "desktop-test:codex", taskId = "task", conversationId = "chat",
        turnId = "turn", executionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
        budget = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE), connectorMode = "",
        policyPrompt = "", requestKind = "", model = model, effort = AgentModelReasoningEffort.fromWireValue(effort),
        runId = "", resultContract = CollaborationResultContract.WORKSPACE,
        teamId = team, instanceId = member, teamMessage = followup
    )

    @Test fun researchMemberCarriesModelEffortAndIndependentIdentifiers() {
        val p = payload("member-b", "team-a", "gpt-6.2-astra", "xhigh")
        assertEquals("chat", p.getString("conversation_id"))
        assertEquals("member-b", p.getString("agent_instance_id"))
        assertEquals("team-a", p.getString("team_id"))
        assertEquals(CollaborationResultContract.WORKSPACE, p.getString("result_contract"))
        assertEquals("gpt-6.2-astra", p.getJSONObject("agent_invocation").getString("model_id"))
        assertEquals("xhigh", p.getJSONObject("agent_invocation").getString("reasoning_effort"))
    }

    @Test fun ordinaryTurnDoesNotAcquireTeamOrPhonePlannerSemantics() {
        val p = payload("", "", "", "auto")
        for (field in listOf("team_id", "agent_instance_id", "result_contract", "agent_invocation",
                "agent_team_message", "connector_task_mode", "execution_policy_prompt", "request_kind", "run_id"))
            assertFalse(field, p.has(field))
        assertEquals("synthetic input", p.getString("content"))
    }

    @Test fun originalRecallOfferPreservesThePinAndDoesNotAttachToFollowups() {
        val offer = CollaborationMemberRecallDispatch.Offer(
            AgentPendingDelivery(17, "chat", "turn", "task", "desktop-test:codex"), "team-a", "member-b", "route")
        CollaborationMemberRecallDispatch.during(offer) {
            val followup = payload("member-b", "team-a", "gpt-6.2-astra", "xhigh", followup = true)
            assertTrue(followup.getBoolean("agent_team_message"))
            assertFalse(followup.has(CollaborationMemberRecall.FLAG))
            val original = payload("member-b", "team-a", "gpt-6.2-astra", "xhigh")
            assertTrue(original.getBoolean(CollaborationMemberRecall.FLAG))
            assertEquals("route", original.getString("client_route_id"))
            assertEquals("gpt-6.2-astra", original.getJSONObject("agent_invocation").getString("model_id"))
            assertEquals("xhigh", original.getJSONObject("agent_invocation").getString("reasoning_effort"))
            assertFalse(payload("member-b", "team-a", "gpt-6.2-astra", "xhigh").has(CollaborationMemberRecall.FLAG))
        }
    }
}
