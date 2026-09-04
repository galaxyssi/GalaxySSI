package com.galaxyssi.chat

import org.json.JSONObject
import java.util.Locale

internal enum class AgentRequestedExecutionSite(val wireValue: String) {
    PHONE("phone"),
    DESKTOP("desktop")
}

internal data class AgentExecutionSiteDecision(
    val site: AgentRequestedExecutionSite,
    val evidence: String = ""
)

/**
 * Parses the model's execution-site decision without using a host keyword list.
 * Desktop execution requires a short verbatim excerpt from the user's goal so a
 * model cannot silently move a phone-owned task to another machine.
 */
internal object AgentExecutionSiteDecisionCodec {
    fun parse(raw: String, userGoal: String): AgentExecutionSiteDecision? {
        val json = extractJsonObject(raw) ?: return null
        val site = when (json.optString("execution_location").trim().lowercase(Locale.US)) {
            AgentRequestedExecutionSite.PHONE.wireValue -> AgentRequestedExecutionSite.PHONE
            AgentRequestedExecutionSite.DESKTOP.wireValue -> AgentRequestedExecutionSite.DESKTOP
            else -> return null
        }
        val evidence = json.optString("execution_location_evidence")
            .trim()
            .replace(Regex("\\s+"), " ")
            .take(MAX_EVIDENCE_CHARACTERS)
        if (site == AgentRequestedExecutionSite.DESKTOP) {
            if (evidence.isBlank()) return null
            val normalizedGoal = userGoal.trim().replace(Regex("\\s+"), " ").lowercase(Locale.US)
            if (!normalizedGoal.contains(evidence.lowercase(Locale.US))) return null
            if (desktopEvidenceIsNegated(evidence)) return null
        }
        return AgentExecutionSiteDecision(site = site, evidence = evidence)
    }

    private fun desktopEvidenceIsNegated(evidence: String): Boolean {
        val normalized = evidence.lowercase(Locale.US)
        return Regex("\\b(?:do not|don't|never|without)\\b").containsMatchIn(normalized) ||
            listOf("\u4e0d\u8981", "\u7981\u6b62", "\u4e0d\u5f97", "\u4e0d\u80fd\u5728", "\u522b\u5728").any(normalized::contains)
    }

    fun acceptsActions(
        decision: AgentExecutionSiteDecision,
        actions: List<AgentAction>
    ): Boolean = when (decision.site) {
        AgentRequestedExecutionSite.PHONE -> actions.all { action ->
            action.isTaskCompleteMarker() ||
                (action.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                    AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(
                        action.parameters["tool_id"].orEmpty()
                    ))
        }

        AgentRequestedExecutionSite.DESKTOP -> actions.size == 1 &&
            actions.single().kind == AgentActionKind.CALL_CONNECTOR
    }

    internal fun extractJsonObject(raw: String): JSONObject? {
        val clean = raw.trim()
            .removePrefix("```json")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()
        val start = clean.indexOf('{')
        if (start < 0) return null
        var depth = 0
        var inString = false
        var escaped = false
        for (index in start until clean.length) {
            val char = clean[index]
            if (inString) {
                when {
                    escaped -> escaped = false
                    char == '\\' -> escaped = true
                    char == '"' -> inString = false
                }
                continue
            }
            when (char) {
                '"' -> inString = true
                '{' -> depth += 1
                '}' -> {
                    depth -= 1
                    if (depth == 0) {
                        return runCatching { JSONObject(clean.substring(start, index + 1)) }.getOrNull()
                    }
                }
            }
        }
        return null
    }

    private const val MAX_EVIDENCE_CHARACTERS = 240
}
