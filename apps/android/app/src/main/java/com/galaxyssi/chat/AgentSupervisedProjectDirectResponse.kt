package com.galaxyssi.chat

import org.json.JSONObject

/** Lets the reasoning model finish the initial turn without fabricating a phone tool action. */
internal object AgentSupervisedProjectDirectResponseCodec {
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
