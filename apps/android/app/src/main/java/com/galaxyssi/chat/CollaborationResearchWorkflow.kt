package com.galaxyssi.chat

internal enum class CollaborationWorkflow { AUTO, PARALLEL, RESEARCH }

internal enum class CollaborationResearchStage {
    BRIEF, EXPLORE, CHALLENGE, REVISE, COMBINE, VERIFY, REPAIR, RECHECK, DELIVER, EXECUTE
}

internal object CollaborationResearchWorkflow {
    const val STAGE = "collaboration_research_stage"
    const val PERSON = "collaboration_research_person"
    const val CANDIDATE = "collaboration_research_candidate"
    private val researchIntent = Regex(
        "研究|調研|调研|调查|調查|设计|設計|方案|创新|創新|探索|改进|改進|脑洞|腦洞|" +
            "\\b(research|investigat\\w*|design|propos\\w*|innovate|brainstorm|improv\\w*)\\b", RegexOption.IGNORE_CASE)

    fun enabled(goal: String, requested: List<AgentRequestedMember>): Boolean {
        if (requested.size < 2 || requested.any { it.collaborationGroupId.isBlank() }) return false
        if (requested.map { it.collaborationGroupId }.distinct().size != 1) return false
        return when (requested.first().collaborationWorkflow) {
            CollaborationWorkflow.PARALLEL.name -> false
            CollaborationWorkflow.RESEARCH.name -> true
            else -> researchIntent.containsMatchIn(goal) || AgentTeamControlIntent.parse(goal) == AgentTeamUserControl.RUN
        }
    }

    fun stage(member: AgentTeamMember): CollaborationResearchStage? =
        member.context[STAGE]?.let { runCatching { CollaborationResearchStage.valueOf(it) }.getOrNull() }

    fun isResearch(members: List<AgentTeamMember>): Boolean = members.isNotEmpty() &&
        members.all { stage(it) != null && !it.context["collaboration_group_id"].isNullOrBlank() }

    fun expand(members: List<AgentTeamMember>, goal: String): List<AgentTeamMember> =
        CollaborationGoalLoop.initial(members, goal).map { it.copy(context = it.context + (CollaborationLiveGraph.ENABLED to "1")) }
}
