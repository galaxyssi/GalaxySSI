package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class DesktopAgentRequestPayloadTest {
    private fun payload(member: String, team: String, model: String, effort: String) = desktopAgentRequestPayload(
        content = "synthetic input", contactId = "desktop-test:codex", taskId = "task", conversationId = "chat",
        turnId = "turn", executionMode = AgentTaskExecutionMode.AUTO_COMPLETE,
        budget = AgentTaskBudget.forProfile(AgentTaskBudgetProfile.ADAPTIVE), connectorMode = "",
        policyPrompt = "", requestKind = "", model = model, effort = AgentModelReasoningEffort.fromWireValue(effort),
        runId = "", resultContract = CollaborationResultContract.WORKSPACE,
        teamId = team, instanceId = member, teamMessage = false
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
}
