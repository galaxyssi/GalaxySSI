package com.galaxyssi.chat

import org.json.JSONObject

/** A saved evidence report is not a passing integration test or a scientific quality score. */
internal data class CollaborationAdaptivePilotVerdict(val failures: List<String>) {
    val passed: Boolean get() = failures.isEmpty()

    fun requirePassed(cause: Throwable? = null) {
        if (!passed) throw AssertionError("Adaptive pilot failed: ${failures.joinToString("; ")}").also {
            if (cause != null) it.initCause(cause)
        }
    }

    companion object {
        fun evaluate(report: JSONObject): CollaborationAdaptivePilotVerdict {
            val failures = mutableListOf<String>()
            if (report.has("execution_mode") && report.optString("execution_mode") !in setOf("single_agent", "adaptive_team"))
                failures += "Unknown execution mode"
            val singleAgent = report.optString("execution_mode") == "single_agent"
            if (singleAgent && (report.optString("test_scope") != "execution_delivery_only" ||
                    report.opt("goal_verified_by_external_evaluator") != false ||
                    report.opt("scientific_capability_gain_proven") != false)) {
                failures += "Single-agent delivery cannot claim external goal or capability verification"
            }
            val expectedStatus = if (singleAgent) "single_agent_returned_goal_unverified" else "host_goal_accepted"
            if (report.optString("status") != expectedStatus) {
                failures += "Host did not accept the goal: ${report.optString("status", "missing_status")}"
            }
            if (report.has("failure_type") || report.has("failure") || report.has("cleanup_failure")) {
                failures += "Execution or cleanup recorded a failure"
            }
            if (report.opt("finished") != true) failures += "Report is not finalized"
            if (report.opt("cleanup_confirmed") != true) failures += "Remote cleanup is unconfirmed"
            val pending = report.optJSONArray("pending_remote_owners")
            if (pending == null || pending.length() != 0) failures += "Pending remote owners are not confirmed empty"
            if (report.opt("active_conversation_preserved") != true) failures += "User conversation was not preserved"
            if (report.optBoolean("interim_publication_enabled")) {
                val archive = report.optJSONObject("interim_evidence")
                if (report.opt("milestone_archive_complete") != true ||
                    archive?.optString("format") != "galaxyssi.adaptive-pilot-milestones.v1" ||
                    archive.optJSONArray("milestones") == null || archive.opt("peer_read_proven") != false ||
                    archive.opt("scientific_acceptance_proven") != false) {
                    failures += "Interim publication archive is incomplete; retain the trial state"
                }
            }

            val dispatches = report.optJSONArray("phone_dispatches")
            val admitted = (0 until (dispatches?.length() ?: 0)).mapNotNull { index ->
                dispatches?.optJSONObject(index)?.optString("node_id")?.takeIf(String::isNotBlank)
            }.toSet()
            if (admitted.isEmpty()) failures += "No phone dispatch was recorded"

            // A reservation alone does not prove remote execution. Require a bound, intact worker result.
            val results = report.optJSONArray("worker_results")
            if (singleAgent && (dispatches?.length() != 1 || results?.length() != 1)) {
                failures += "Single-agent calibration must contain exactly one dispatch and one result"
            }
            var verifiedResults = 0
            for (index in 0 until (results?.length() ?: 0)) {
                val result = results?.optJSONObject(index)
                val content = result?.optString("content").orEmpty()
                val valid = result != null && result.optString("node_id") in admitted && content.isNotBlank() &&
                    result.optString("content_sha256") == CollaborationRemotePilotDispatch.sha256(content.toByteArray(Charsets.UTF_8))
                if (valid) verifiedResults++ else failures += "Worker result $index is missing, unbound or corrupt"
            }
            if (verifiedResults == 0) failures += "No verified worker result was received"
            val rounds = report.optJSONArray("rounds")
            val finalRound = rounds?.optJSONObject(rounds.length() - 1)
            if (singleAgent) {
                if (finalRound?.optString("state") != AgentTeamExecutionState.SUCCEEDED.name)
                    failures += "Single-agent execution did not complete"
                if (finalRound?.optString("goal_disposition") == "achieved")
                    failures += "Single-agent execution cannot be labeled host goal acceptance"
            } else if (finalRound?.optString("goal_disposition") != "achieved") failures += "Final checkpoint did not accept the goal"
            return CollaborationAdaptivePilotVerdict(failures)
        }
    }
}
