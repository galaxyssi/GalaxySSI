package com.galaxyssi.chat

/** Bounds failed supervision, not successful tools or the lifetime of a goal. */
internal object AgentSupervisorFailurePolicy {
    const val MAX_CONSECUTIVE_PROVIDER_FAILURES = 2
    const val MAX_FORMAT_REPAIRS = 3

    fun stopReason(history: List<AgentAction>, failed: AgentAction, result: AgentActionResult?): String? {
        if (!failed.isSupervisedProjectConnector()) return null
        val metadata = result?.takeIf { it.actionId == failed.id && !it.success }?.metadata.orEmpty()
        if (metadata["non_retriable"] == "true" || metadata["recovery_exhausted"] == "true") {
            return "supervisor_failure_non_retriable"
        }
        if (metadata["failure_kind"] == "invalid_supervised_project_plan" &&
            (metadata["structured_repair_attempts"]?.toIntOrNull() ?: 0) >= MAX_FORMAT_REPAIRS) {
            return "supervisor_format_repair_exhausted"
        }
        val failures = history.filter { it.status in setOf(AgentActionStatus.FAILED, AgentActionStatus.COMPLETED) }
            .distinctBy(AgentAction::id).asReversed()
            .takeWhile { it.isSupervisedProjectConnector() && it.status == AgentActionStatus.FAILED }.size
        return "supervisor_consecutive_failures".takeIf { failures >= MAX_CONSECUTIVE_PROVIDER_FAILURES }
    }
}
