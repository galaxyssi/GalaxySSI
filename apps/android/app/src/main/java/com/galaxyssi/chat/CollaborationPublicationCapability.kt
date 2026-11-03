package com.galaxyssi.chat

import org.json.JSONObject

/** Assignment facts, not an invitation for a model to repair or grant its own authority. */
internal object CollaborationPublicationCapability {
    fun describe(contract: JSONObject?, finalized: Boolean): JSONObject {
        val reason = when {
            contract == null -> "assignment_not_enrolled"
            contract.has("candidate_task") -> "candidate_transition_final_only"
            finalized -> "assignment_finalized"
            else -> "available"
        }
        val guidance = when (reason) {
            "assignment_not_enrolled" -> "This dispatch has no interim-publication contract. Return its required planning or final-response format; " +
                "put useful research into a work item for an enrolled member. Do not repair artifact JSON, retry publication, or repeat completed tools to obtain enrollment."
            "candidate_transition_final_only" -> "This host candidate-transition assignment uses its final publication contract. Return the required final artifact instead of an interim milestone."
            "assignment_finalized" -> "This assignment has already committed its final publication. List saved milestone IDs or read the original result; new work requires a new host assignment."
            else -> "Interim publication is available for this assignment. Preserve stable milestone IDs and exact versions; a receipt is not verification or task completion."
        }
        return JSONObject().put("format", "galaxyssi.publication-capability.v1")
            .put("publish_allowed", reason == "available").put("reason_code", reason)
            .put("retry_changes_availability", false).put("guidance", guidance)
            .put("scope", "current_host_assignment").put("grants_authority", false)
    }

    fun instructions(execution: AgentTeamMemberExecutionContext): String = when {
        CollaborationLiveGraph.planner(execution.member) ||
            CollaborationResearchWorkflow.stage(execution.member) == CollaborationResearchStage.DELIVER ->
            "interim_publication=unavailable_for_this_dispatch. This is a coordination/assessment dispatch, not an enrolled research publication. " +
                "Globally listed connector tools do not grant enrollment. Return the required response protocol to commit decisions and dispatch work. " +
                "Do not retry publication or fetch its schemas; assign artifact production, challenges and revisions to enrolled work items. " +
                "Read evidence or run checks needed for the next decision, then let ready work start."
        !execution.member.context[CollaborationCandidateEvolution.TASK].isNullOrBlank() ->
            "interim_publication=final_contract_only. Follow this host candidate-transition assignment's final publication contract, not interim milestones."
        else -> "interim_publication=enrolled_research_assignment. Use interim milestones for useful exact-version handover while continuing your work. " +
            "If availability is uncertain, collaboration_publish mode=status reports the current host assignment without publishing."
    }
}
