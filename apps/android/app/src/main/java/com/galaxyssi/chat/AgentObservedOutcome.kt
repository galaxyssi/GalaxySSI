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

        private fun validPath(value: String): Boolean = value.startsWith('/') && value.length <= 512 &&
            value.split('/').drop(1).all { it.isNotEmpty() && it.all { c -> c.isLetterOrDigit() || c in "_.-~" } }
    }
}

internal object AgentObservedOutcomeEvidence {
    fun missing(requirements: List<AgentObservedOutcome>, history: List<AgentAction>): List<String> =
        requirements.mapNotNull { requirement ->
            val lastMutation = if (requirement.afterToolId.isEmpty()) -1 else history.indexOfLast {
                it.parameters["tool_id"] == requirement.afterToolId && it.status != AgentActionStatus.PENDING_CONFIRMATION
            }
            // Check the newest subject-matched observation, never an older successful state.
            val observed = history.withIndex().toList().asReversed().firstNotNullOfOrNull { (index, action) ->
                if (index < lastMutation || action.kind != AgentActionKind.CALL_NATIVE_TOOL ||
                    action.parameters["tool_id"] != requirement.toolId) return@firstNotNullOfOrNull null
                val raw = runCatching { JSONObject(action.evidence) }.getOrNull() ?: return@firstNotNullOfOrNull null
                val output = raw.optJSONObject("output") ?: raw
                if (requirement.subject.any { (path, value) -> at(output, path)?.toString() != value }) return@firstNotNullOfOrNull null
                (action.status == AgentActionStatus.COMPLETED) && output.opt("state_verified") != false &&
                    requirement.checks.all { (path, value) ->
                    val actual = at(output, path)
                    if (value is Number && actual is Number) value.toDouble() == actual.toDouble() else actual == value
                }
            }
            if (observed == true) null else "Observed outcome ${requirement.id}: require fresh ${requirement.toolId} " +
                "evidence for ${requirement.subject} with ${requirement.checks}; do not repeat mutations blindly"
        }

    private fun at(root: JSONObject, pointer: String): Any? {
        var value: Any? = root
        for (part in pointer.removePrefix("/").split('/')) {
            val key = part.replace("~1", "/").replace("~0", "~")
            value = when (val current = value) {
                is JSONObject -> current.opt(key)
                is JSONArray -> key.toIntOrNull()?.let(current::opt)
                else -> null
            }
        }
        return value?.takeUnless { it == JSONObject.NULL }
    }
}
