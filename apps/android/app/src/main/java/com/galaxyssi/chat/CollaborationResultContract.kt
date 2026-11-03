package com.galaxyssi.chat

import org.json.JSONObject

/** Describes where a member publishes results; it is not execution permission or goal acceptance. */
internal object CollaborationResultContract {
    const val PARAMETER = "result_contract"
    const val WORKSPACE = "galaxyssi.collaboration-workspace.v1"

    fun assignment(groupId: String): Map<String, String> =
        if (groupId.isBlank()) emptyMap() else mapOf(PARAMETER to WORKSPACE)

    fun forAction(action: AgentAction): String = WORKSPACE.takeIf {
        action.parameters[MANAGED_AGENT_TEAM_ACTION_PARAMETER] == "true" &&
            action.parameters[PARAMETER] == WORKSPACE &&
            !action.parameters["team_id"].isNullOrBlank() &&
            !action.parameters["agent_instance_id"].isNullOrBlank()
    }.orEmpty()

    fun encode(payload: JSONObject, value: String, teamId: String, agentInstanceId: String) {
        agentInstanceId.trim().takeIf { it.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,95}")) }
            ?.let { payload.put("agent_instance_id", it) }
        teamId.trim().takeIf { it.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")) }
            ?.let { payload.put("team_id", it) }
        if (value == WORKSPACE && payload.optString("team_id").isNotBlank() &&
            payload.optString("agent_instance_id").isNotBlank()) payload.put(PARAMETER, WORKSPACE)
    }
}
