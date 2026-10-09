package com.galaxyssi.chat

import kotlinx.coroutines.delay

/** Uses production admission, expansion, acceptance and checkpoints; the harness selects no work. */
internal class CollaborationAdaptivePilotRunner(
    private val store: AgentTeamExecutionStore, private val runtime: AgentTeamExecutionRuntime,
    private val admission: CollaborationAdaptivePilotAdmission,
    private val projectRecruits: (List<AgentTeamMember>) -> Map<String, String> = { emptyMap() },
    private val checkpoint: (AgentTeamExecutionSnapshot, AgentTeamExecutionCheckpoint) -> Unit = { _, _ -> },
    private val singleAgent: Boolean = false
) {
    var activeHandle: AgentTeamExecutionHandle? = null
        private set

    suspend fun run(definition: AgentTeamDefinition, request: AgentRunRequest, worker: AgentTeamMemberWorker): String {
        if (singleAgent) require(definition.members.size == 1 && definition.members.all {
            it.context[CollaborationGoalLoop.ENABLED] == null && CollaborationResearchWorkflow.stage(it) == null
        }) { "Single-agent calibration cannot execute a team graph" }
        activeHandle = runtime.start(definition, request, worker)
        while (true) {
            val result = requireNotNull(activeHandle).await()
            val snapshot = result.snapshot
            checkpoint(snapshot, requireNotNull(store.deliveryCheckpoint(request.runId)))
            if (singleAgent) return if (snapshot.state == AgentTeamExecutionState.SUCCEEDED)
                "single_agent_returned_goal_unverified" else "execution_settled_without_goal_acceptance"
            if (snapshot.goalDisposition == "achieved") return "host_goal_accepted"
            if (admission.exhausted()) return "phone_dispatch_envelope_reached"
            if (snapshot.goalDisposition != "continue") return when (snapshot.goalDisposition) {
                "blocked" -> "observable_blocker"
                "unverified_history" -> "unverified_history_not_goal_acceptance"
                else -> "execution_settled_without_goal_acceptance"
            }
            val waitMillis = snapshot.nextGoalAttemptAtMillis - System.currentTimeMillis()
            if (waitMillis > 0) delay(waitMillis)
            check(store.advanceGoal(request.runId, snapshot.primaryMemberId, System.currentTimeMillis())) {
                "Production coordinator did not advance; preserve its checkpoint instead of replacing its plan"
            }
            val current = requireNotNull(store.deliveryCheckpoint(request.runId))
            check(store.reconcileGoalRecruits(request.runId, current.definition.primaryMemberId, projectRecruits)) {
                "Production recruitment projection remains pending"
            }
            activeHandle = runtime.resume(requireNotNull(store.resumeCheckpoint(request.runId)), worker)
        }
    }
}
