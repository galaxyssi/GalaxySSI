package com.galaxyssi.chat

import org.json.JSONObject

/** Encodes an outgoing agent task; it does not select a destination or authorize publication. */
internal fun desktopAgentRequestPayload(
    content: String, contactId: String, taskId: String, conversationId: String, turnId: String,
    executionMode: AgentTaskExecutionMode, budget: AgentTaskBudget, connectorMode: String,
    policyPrompt: String, requestKind: String, model: String, effort: AgentModelReasoningEffort,
    runId: String, resultContract: String, teamId: String, instanceId: String, teamMessage: Boolean
) = JSONObject().apply {
    put("type", "text")
    put("content", content)
    put("contact_id", contactId)
    put("task_id", taskId)
    put("conversation_id", conversationId)
    put("turn_id", turnId)
    put("execution_mode", executionMode.wireValue)
    put("task_budget", AgentTaskBudgetJsonCodec.encode(budget))
    put("time", System.currentTimeMillis())
    connectorMode.trim().takeIf(String::isNotBlank)?.let { put("connector_task_mode", it.take(96)) }
    if (policyPrompt.isNotBlank()) put("execution_policy_prompt", policyPrompt)
    (requestKind.takeIf { it == PhoneAssistantTaskControl.SCREEN_ANALYSIS_REQUEST_KIND }
        ?: PhoneAssistantTaskControl.requestKind(turnId)).takeIf(String::isNotBlank)?.let { put("request_kind", it) }
    AgentInvocationRequestJsonCodec.encode(model, effort)?.let { put("agent_invocation", it) }
    runId.trim().takeIf(String::isNotBlank)?.let { put("run_id", it) }
    CollaborationResultContract.encode(this, resultContract, teamId, instanceId)
    if (teamMessage) put("agent_team_message", true)
}
