package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Authority comes from the current host checkpoint, never from a tool argument or a model's role claim. */
internal object CollaborationCoordinatorUpdates {
    const val MODE = "team_updates"
    const val OFFERED = "collaboration_research_coordinator_offered"

    fun member(checkpoint: AgentTeamExecutionCheckpoint, access: CollaborationWorkspaceAccess,
               control: AgentTeamUserControl, terminal: Boolean): AgentTeamMember {
        require(control == AgentTeamUserControl.RUN && !terminal && CollaborationLiveGraph.enabled(checkpoint.definition)) {
            "Coordinator assignment is not active"
        }
        val member = requireNotNull(checkpoint.definition.members.singleOrNull { it.memberId == access.nodeId }) {
            "Coordinator assignment is unavailable"
        }
        val record = AgentTeamExecutionRecord(checkpoint.definition, checkpoint.request)
        require(CollaborationLiveGraph.planner(member) && member.context[CollaborationResearchWorkflow.STAGE] == "BRIEF" &&
            member.memberId !in checkpoint.completed && CollaborationMilestoneDispatch.access(record, member) == access) {
            "Live updates require this exact active incremental coordinator binding"
        }
        return member
    }

    private fun current(context: Context, access: CollaborationWorkspaceAccess): Pair<AgentTeamExecutionCheckpoint, AgentTeamMember> {
        require(CollaborationEvidenceLedger(context).authorizes(access)) { "An exact source binding is required" }
        val (checkpoint, snapshot) = AgentTeamExecutionLocations(context).state(access)
        return checkpoint to member(checkpoint, access, AgentTeamDurableControl(context).get(access.runId), snapshot.state.isTerminal)
    }

    fun read(context: Context, access: CollaborationWorkspaceAccess, cursor: String): JSONObject {
        val (checkpoint, member) = current(context, access)
        val producers = checkpoint.definition.members.filter { !it.context[CollaborationGoalLoop.WORK_ID].isNullOrBlank() }
            .mapTo(hashSetOf()) { it.memberId }
        val covered = CollaborationMilestoneDispatch.inputs(member).mapTo(hashSetOf()) { it.getString("token") }
        return CollaborationResearchWorkspace(context).coordinatorUpdates(access, cursor, covered, producers)
    }

    fun readAccess(context: Context, access: CollaborationWorkspaceAccess): CollaborationWorkspaceAccess {
        if (access.nodeId.isBlank() || access.personId.isBlank()) return access
        val offered = CollaborationResearchWorkspace(context).coordinatorOffered(access)
        if (offered.isEmpty()) return access
        // Ordinary workers and stale/paused bindings keep their original isolation scope.
        if (runCatching { current(context, access) }.isFailure) return access
        return withGrants(access, offered)
    }

    fun withGrants(access: CollaborationWorkspaceAccess, offered: List<JSONObject>) = access.copy(
        pinnedReads = access.pinnedReads + offered.flatMap { CollaborationMilestoneDispatch.strings(it.getJSONArray("grants").toString()) })

    fun offered(member: AgentTeamMember): List<JSONObject> = member.context[OFFERED]?.let(::JSONArray)?.let { array ->
        (0 until array.length()).map(array::getJSONObject)
    }.orEmpty()

    fun capture(record: AgentTeamExecutionRecord, member: AgentTeamMember,
                workspace: CollaborationResearchWorkspace?): AgentTeamMember {
        if (workspace == null) return member
        val offered = workspace.coordinatorOffered(CollaborationMilestoneDispatch.access(record, member))
        return if (offered.isEmpty()) member else member.copy(context = member.context + (OFFERED to JSONArray(offered).toString()))
    }
}
