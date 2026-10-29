package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Accepts answer-only responses without fabricating a phone tool action. */
internal object AgentSupervisedProjectDirectResponseCodec {
    /** Repaired/continued answers still pass through the normal completion evidence checks. */
    fun completionPlan(rawResponse: String): String? {
        val answer = parse(rawResponse) ?: return null
        return JSONObject().put("execution_location", AgentRequestedExecutionSite.PHONE.wireValue)
            .put("actions", JSONArray().put(JSONObject()
                .put("kind", AgentActionKind.DRAFT_PLAN.name).put("target", "task-complete")
                .put("description", answer).put("parameters", JSONObject())))
            .toString()
    }

    fun parse(rawResponse: String): String? {
        val normalized = rawResponse.trim()
        if (normalized.isBlank() || AgentSupervisedControlContent.isProtocol(normalized)) return null

        val unwrapped = normalized
            .removePrefix("```json")
            .removePrefix("```JSON")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()
        if (!unwrapped.startsWith('{')) return normalized

        val json = runCatching { JSONObject(unwrapped) }.getOrNull() ?: return null
        if (!json.optString("disposition").equals("respond", ignoreCase = true)) return null
        return (json.opt("final_response") as? String)?.trim()
            ?.takeIf { it.isNotBlank() && !AgentSupervisedControlContent.isProtocol(it) }
    }
}
