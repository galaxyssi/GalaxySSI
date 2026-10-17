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
            it.parameters["tool_id"] == requirement.afterToolId && it.status != AgentActionStatus.PENDING_CONFIRMATION
        }
        var latestMismatch: JSONObject? = null
        var stale = false
        for (index in history.indices.reversed()) {
            val action = history[index]
            if (action.kind != AgentActionKind.CALL_NATIVE_TOOL ||
                action.parameters["tool_id"] != requirement.toolId) continue
            if (index < lastMutation) { stale = true; continue }
            val output = AgentObservedOutputFields.output(action)
            if (output == null) {
                if (latestMismatch == null) latestMismatch = failure(requirement, "invalid_receipt", action)
                continue
            }
            if (requirement.subject.any { (path, value) -> AgentObservedOutputFields.at(output, path)?.toString() != value }) {
                if (latestMismatch == null) latestMismatch = failure(requirement, "subject_not_matched", action,
                    issues(requirement.subject, output, identity = true))
                continue
            }
            // Only the latest matching subject can prove state; old success must not hide new failure.
            if (action.status != AgentActionStatus.COMPLETED) return failure(requirement, "observation_not_completed", action)
            if (output.opt("state_verified") == false) return failure(requirement, "state_unverified", action)
            val checkIssues = issues(requirement.checks, output, identity = false)
            return if (checkIssues.isEmpty()) null else failure(requirement, "checks_not_satisfied", action, checkIssues)
        }
        return latestMismatch ?: failure(requirement, if (stale) "observation_stale" else "observation_missing")
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
            action?.let { result.put("action_id", it.id).put("action_status", it.status.name) }
            if (issues.isNotEmpty()) {
                result.put("fields", JSONArray(issues.take(8)))
                result.put("fields_partial", issues.size > 8)
            }
        }
}
