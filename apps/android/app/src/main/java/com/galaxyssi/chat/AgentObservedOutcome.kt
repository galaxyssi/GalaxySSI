package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** The model declares a postcondition; only host-owned tool observations can satisfy it. */
data class AgentObservedOutcome(
    val id: String,
    val toolId: String,
    val subject: Map<String, String>,
    val checks: Map<String, Any>,
    val afterToolId: String = ""
) {
    fun toJson() = JSONObject().put("id", id).put("tool_id", toolId)
        .put("subject", JSONObject(subject)).put("checks", JSONObject(checks)).put("after_tool_id", afterToolId)

    companion object {
        fun parse(json: JSONObject): AgentObservedOutcome? {
            val id = json.opt("id") as? String ?: return null
            val tool = json.opt("tool_id") as? String ?: return null
            val after = if (json.has("after_tool_id")) json.opt("after_tool_id") as? String ?: return null else ""
            if (!id.matches(Regex("[A-Za-z0-9_.-]{1,128}")) || !tool.startsWith("galaxyssi.") ||
                tool.length > 256 || after.isNotEmpty() && !after.startsWith("galaxyssi.")) return null
            val subjectJson = json.optJSONObject("subject") ?: return null
            val checksJson = json.optJSONObject("checks") ?: return null
            if (subjectJson.length() == 0 || checksJson.length() == 0) return null
            val subject = linkedMapOf<String, String>()
            val checks = linkedMapOf<String, Any>()
            for (key in subjectJson.keys()) {
                val value = subjectJson.opt(key) as? String ?: return null
                if (!validPath(key) || value.isBlank() || value.length > 4096) return null
                subject[key] = value
            }
            for (key in checksJson.keys()) {
                val value = checksJson.opt(key)
                if (!validPath(key) || value !is String && value !is Boolean && value !is Number) return null
                // Accepting/queuing a command or model-authored prose cannot prove an external outcome.
                if (key.substringAfterLast('/') in setOf("accepted", "success", "message", "summary", "text",
                        "exit_code", "queued", "dispatched", "ui_changed", "request_accepted", "dispatch_attempted",
                        "requested_enabled", "requested_percent", "target_volume", "requested_muted")) return null
                if (value is String && value.length > 1024) return null
                checks[key] = value
            }
            return AgentObservedOutcome(id, tool, subject, checks, after)
        }

        internal fun validPath(value: String): Boolean = value.startsWith('/') && value.length <= 512 &&
            value.split('/').drop(1).all { it.isNotEmpty() && it.all { c -> c.isLetterOrDigit() || c in "_.-~" } }
    }
}

internal object AgentObservedOutcomeEvidence {
    fun missing(requirements: List<AgentObservedOutcome>, history: List<AgentAction>): List<String> =
        requirements.mapNotNull { requirement -> diagnose(requirement, history)?.let { diagnosis ->
            "Observed outcome ${requirement.id}: $diagnosis. Missing fields: correct pointers from the receipt; " +
                "alternative paths are hints, not equivalent identities. Mismatched/unverified state: inspect and repair " +
                "actual state, never weaken expected checks or repeat mutations blindly."
        } }

    internal fun diagnose(requirement: AgentObservedOutcome, history: List<AgentAction>): JSONObject? {
        val lastMutation = if (requirement.afterToolId.isEmpty()) -1 else history.indexOfLast {
            it.kind == AgentActionKind.CALL_NATIVE_TOOL && toolId(it) == requirement.afterToolId &&
                !isUndispatched(it) && it.status != AgentActionStatus.BLOCKED
        }
        if (requirement.afterToolId.isNotEmpty() && lastMutation < 0)
            return failure(requirement, "required_action_not_observed").put("after_tool_id", requirement.afterToolId)
        if (lastMutation >= 0 && history[lastMutation].status in setOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE))
            return failure(requirement, "required_action_still_pending", history[lastMutation])
        if (lastMutation >= 0 && history[lastMutation].status == AgentActionStatus.ROLLED_BACK) {
            val action = history[lastMutation]
            val superseded = action.evidence.startsWith("superseded_by_plan_revision:") ||
                action.parameters.containsKey(SUPERSEDED_SOURCE_STATUS_PARAMETER)
            return failure(requirement, if (superseded) "required_action_superseded_unresolved" else "required_action_rolled_back", action)
        }
        var latestMismatch: JSONObject? = null
        var stale = false
        for (index in history.indices.reversed()) {
            val action = history[index]
            if (action.kind != AgentActionKind.CALL_NATIVE_TOOL ||
                toolId(action) != requirement.toolId || isUndispatched(action)) continue
            if (index < lastMutation) { stale = true; continue }
            val raw = runCatching { JSONObject(action.evidence) }.getOrNull()
                ?: return failure(requirement, "invalid_receipt", action)
            val output = raw.optJSONObject("output") ?: raw
            if (requirement.subject.any { (path, value) -> AgentObservedOutputFields.at(output, path)?.toString() != value }) {
                val mismatch = failure(requirement, "subject_not_matched", action, issues(requirement.subject, output, identity = true))
                // A proven different subject is unrelated; a missing identity is uncertainty, not permission to use old success.
                val differentSubject = requirement.subject.any { (path, value) ->
                    AgentObservedOutputFields.at(output, path)?.toString()?.let { it != value } == true
                }
                if (!differentSubject) return mismatch
                if (latestMismatch == null) latestMismatch = mismatch
                continue
            }
            // Only the latest matching subject can prove state; old success must not hide new failure.
            if (action.status != AgentActionStatus.COMPLETED) return failure(requirement, "observation_not_completed", action)
            if (raw.optJSONObject("output") != null) {
                if (raw.has("tool_id") && raw.optString("tool_id") != requirement.toolId)
                    return failure(requirement, "receipt_tool_mismatch", action)
                if (raw.has("status") && raw.optString("status") != "succeeded" ||
                    raw.optJSONObject("receipt")?.let { it.has("status") && it.optString("status") != "succeeded" } == true)
                    return failure(requirement, "receipt_not_succeeded", action)
            }
            if (isUnverified(output) || raw !== output && isUnverified(raw))
                return failure(requirement, "state_unverified", action)
            val checkIssues = issues(requirement.checks, output, identity = false)
            return if (checkIssues.isEmpty()) null else failure(requirement, "checks_not_satisfied", action, checkIssues)
        }
        return latestMismatch ?: failure(requirement, if (stale) "observation_stale" else "observation_missing")
    }

    private fun toolId(action: AgentAction): String = action.parameters["tool_id"].orEmpty().ifBlank { action.target }

    internal fun isUndispatched(action: AgentAction): Boolean =
        action.status in setOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION) ||
            action.status == AgentActionStatus.ROLLED_BACK && action.parameters[SUPERSEDED_SOURCE_STATUS_PARAMETER] in
                setOf(AgentActionStatus.PROPOSED.name, AgentActionStatus.PENDING_CONFIRMATION.name)

    private fun isUnverified(output: JSONObject): Boolean {
        val metadata = output.optJSONObject("metadata")
        return output.opt("state_verified") == false || output.opt("delivery_verified") == false ||
            metadata?.opt("business_success_verified")?.toString() == "false" ||
            metadata?.optString("goal_status") in setOf("dispatched", "blocked", "unknown", "failed")
    }

    private fun issues(expected: Map<String, Any>, output: JSONObject, identity: Boolean): List<JSONObject> {
        val index by lazy { AgentObservedOutputFields.index(output) }
        return expected.mapNotNull { (path, value) ->
            val actual = AgentObservedOutputFields.at(output, path)
            val matches = if (identity) actual?.toString() == value
                else if (value is Number && actual is Number) value.toDouble() == actual.toDouble() else actual == value
            if (matches) null else JSONObject().put("path", path)
                .put("issue", if (actual == null) "field_missing_or_null" else "value_mismatch")
                .also {
                    if (actual == null) it.put("alternative_paths", JSONArray(AgentObservedOutputFields.alternatives(index, path)))
                        .put("index_partial", index.partial)
                }
        }
    }

    private fun failure(
        requirement: AgentObservedOutcome, code: String, action: AgentAction? = null,
        issues: List<JSONObject> = emptyList()
    ): JSONObject = JSONObject().put("code", code).put("outcome_id", requirement.id)
        .put("tool_id", requirement.toolId).also { result ->
            result.put("next_action", when (code) {
                "required_action_not_observed" -> "inspect_execution_history; correct after_tool_id only for a genuinely read-only goal; never replay an effect solely to manufacture evidence"
                "required_action_still_pending" -> "resolve the existing action using its status or receipt before declaring completion; do not dispatch it again"
                "required_action_superseded_unresolved" -> "the plan replaced an action without proof it never executed; reconcile its receipt and current state, do not resend the effect"
                "required_action_rolled_back" -> "the prior action was rolled back; inspect current state and the latest user goal, never reapply it without a current request"
                "invalid_receipt", "observation_not_completed", "receipt_tool_mismatch", "receipt_not_succeeded", "state_unverified", "observation_stale", "observation_missing" ->
                    "obtain a fresh read-only observation of the requested subject; preserve the goal and do not repeat mutations blindly"
                else -> "inspect receipt fields and actual state; correct pointer errors without rerunning tools, otherwise repair missing work and verify again"
            })
            action?.let { result.put("action_id", it.id).put("action_status", it.status.name) }
            if (issues.isNotEmpty()) {
                result.put("fields", JSONArray(issues.take(8)))
                result.put("fields_partial", issues.size > 8)
            }
        }
}
