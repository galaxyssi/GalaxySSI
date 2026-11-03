package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Accepts answer-only responses without fabricating a phone tool action. */
internal object AgentSupervisedProjectDirectResponseCodec {
    /** Repaired/continued answers still pass through the normal completion evidence checks. */
    fun completionPlan(rawResponse: String): String? {
        val answer = parse(rawResponse) ?: return null
        val root = AgentVisualOutputContract.envelope(rawResponse)
        val requirements = root?.optJSONObject("completion_requirements")
        if (root?.has("completion_requirements") == true && requirements == null) return null
        if (requirements != null && AgentCompletionRequirements.parse(requirements) == null) return null
        return JSONObject().put("execution_location", AgentRequestedExecutionSite.PHONE.wireValue)
            .apply { if (requirements != null) put("completion_requirements", requirements) }
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
        val rich = json.optJSONObject("rich_output")?.let { AgentRichContentCodec.normalize(it.toString()) }.orEmpty()
        val declared = json.opt("final_response")
        if (declared != null && declared != JSONObject.NULL && declared !is String) return null
        val answer = (declared as? String).orEmpty().trim().ifBlank {
            AgentRichContentCodec.decode(rich).firstNotNullOfOrNull { block ->
                block.fallbackText.ifBlank { block.title }.takeIf(String::isNotBlank)
            }.orEmpty()
        }.takeIf { it.isNotBlank() && !AgentSupervisedControlContent.isProtocol(it) } ?: return null
        return if (rich.isBlank() || answer.contains("```galaxyssi-rich")) answer
            else "$answer\n\n```galaxyssi-rich\n$rich\n```"
    }
}
