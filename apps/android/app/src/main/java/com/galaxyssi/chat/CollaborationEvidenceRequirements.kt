package com.galaxyssi.chat

import org.json.JSONObject

/** Preserved source constraints cannot be satisfied by a receipt for reading a peer's summary. */
internal object CollaborationEvidenceRequirements {
    const val FIELD = "required_observations"

    fun required(criterion: JSONObject): Set<Pair<String, String>> {
        if (!criterion.has(FIELD)) return emptySet()
        val items = requireNotNull(criterion.optJSONArray(FIELD)) { "$FIELD must be an array" }
        return (0 until items.length()).mapTo(linkedSetOf()) { index ->
            val item = items.getJSONObject(index)
            require(item.keys().asSequence().toSet() == setOf("origin", "tool")) { "Evidence requirements need origin and tool" }
            require(item.opt("origin") is String && item.getString("origin") in CollaborationEvidenceOrigin.entries.map { it.wireValue }) {
                "Unknown required observation origin"
            }
            require(item.opt("tool") is String && item.getString("tool").isNotBlank()) { "An exact required tool name is needed" }
            item.getString("origin") to item.getString("tool")
        }
    }

    fun preserved(before: JSONObject, after: JSONObject?): Boolean = after != null && runCatching {
        required(after).containsAll(required(before))
    }.getOrDefault(false)

    fun validate(criterion: JSONObject, reviewedObservations: List<JSONObject>) {
        required(criterion).forEach { (origin, tool) ->
            require(reviewedObservations.any { it.getString("origin") == origin && it.getString("tool") == tool &&
                it.getString("status") == "returned" && it.getString("observation_kind") == "tool_output_recorded" }) {
                "${criterion.getString("id")}: the review must cite original $origin/$tool evidence; reading a peer document is not a substitute"
            }
        }
    }
}
