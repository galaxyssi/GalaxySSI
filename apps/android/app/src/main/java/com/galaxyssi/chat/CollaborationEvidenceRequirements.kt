package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Preserved source constraints cannot be satisfied by a receipt for reading a peer's summary. */
internal object CollaborationEvidenceRequirements {
    const val FIELD = "required_observations"

    fun required(criterion: JSONObject, path: String = "$"): Set<Pair<String, String>> {
        if (!criterion.has(FIELD)) return emptySet()
        fun failure(field: String, code: String, expected: String, actual: Any?): Nothing =
            throw CollaborationAssessmentValidation.Failure("$path.$FIELD$field", code, expected,
                CollaborationAssessmentValidation.describe(actual))
        val items = criterion.optJSONArray(FIELD) ?: failure("", "invalid_type", "array", criterion.opt(FIELD))
        return (0 until items.length()).mapTo(linkedSetOf()) { index ->
            val item = items.optJSONObject(index) ?: failure("[$index]", "invalid_type", "object", items.opt(index))
            if (item.keys().asSequence().toSet() != setOf("origin", "tool"))
                failure("[$index]", "invalid_fields", "exactly origin and tool", item.keys().asSequence().sorted().joinToString(", "))
            val origins = CollaborationEvidenceOrigin.entries.map { it.wireValue }
            if (item.opt("origin") !is String || item.getString("origin") !in origins)
                failure("[$index].origin", "unknown_origin", origins.joinToString(", "), item.opt("origin"))
            if (item.opt("tool") !is String || item.getString("tool").isBlank())
                failure("[$index].tool", "invalid_tool", "exact nonblank tool name from host observation receipts", item.opt("tool"))
            item.getString("origin") to item.getString("tool")
        }
    }

    fun preserved(before: JSONObject, after: JSONObject?): Boolean = after != null && runCatching {
        required(after).containsAll(required(before))
    }.getOrDefault(false)

    /** Check new bindings before they become immutable; never reinterpret a saved contract. */
    fun validateAdmission(prior: JSONArray, proposed: JSONArray) {
        val previous = (0 until prior.length()).associate { index ->
            prior.getJSONObject(index).let { it.getString("id") to required(it) }
        }
        repeat(proposed.length()) { index ->
            val criterion = proposed.getJSONObject(index)
            required(criterion, "$.criteria[$index]")
            val existing = previous[criterion.getString("id")].orEmpty()
            val entries = criterion.optJSONArray(FIELD) ?: return@repeat
            for (entryIndex in 0 until entries.length()) {
                val entry = entries.getJSONObject(entryIndex)
                val source = entry.getString("origin") to entry.getString("tool")
                if (source in existing || source.first != CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL.wireValue) continue
                if (source.second !in CollaborationRemoteEvidenceProtocol.RECORDED_TOOLS)
                    throw CollaborationAssessmentValidation.Failure(
                        "$.criteria[$index].$FIELD[$entryIndex].tool", "unknown_recorded_tool",
                        CollaborationRemoteEvidenceProtocol.RECORDED_TOOLS.joinToString(", "), source.second,
                        "These are recorded Desktop event families, not callable tool names. " +
                            "No new binding or assignment was admitted. Correct the draft using the host protocol; " +
                            "do not execute a command just to discover its receipt name or rewrite an established binding.")
            }
        }
    }

    fun validate(criterion: JSONObject, reviewedObservations: List<JSONObject>) {
        required(criterion).forEach { (origin, tool) ->
            require(reviewedObservations.any { it.getString("origin") == origin && it.getString("tool") == tool &&
                it.getString("status") == "returned" && it.getString("observation_kind") == "tool_output_recorded" }) {
                "${criterion.getString("id")}: the review must cite original $origin/$tool evidence; reading a peer document is not a substitute"
            }
        }
    }
}
