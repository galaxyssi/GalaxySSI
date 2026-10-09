package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Explicit operation/resource ordering is not replaceable by published data. */
internal object CollaborationCompletionBarriers {
    const val FIELD = "completion_barriers"
    const val CONTEXT = "collaboration_research_completion_barriers"

    fun read(item: JSONObject): Map<String, String> {
        if (!item.has(FIELD)) return emptyMap()
        val rows = requireNotNull(item.optJSONArray(FIELD)) { "completion_barriers must be an array" }
        val dependencies = CollaborationWorkGraph.dependencies(item)
        val data = CollaborationDataDependencies.read(item)
        return buildMap {
            repeat(rows.length()) { index ->
                val row = rows.getJSONObject(index)
                require(row.keys().asSequence().toSet() == setOf("work_id", "reason") &&
                    row.opt("work_id") is String && row.opt("reason") is String) {
                    "completion_barriers[$index] requires only string work_id and reason"
                }
                val id = row.getString("work_id")
                val reason = row.getString("reason")
                require(id.isNotBlank() && id in dependencies && id !in this && id !in data) {
                    "A completion barrier must name a unique non-data depends_on work ID"
                }
                require(reason.isNotBlank() && reason.length <= 2000) { "A concrete completion barrier reason within 2000 characters is required" }
                put(id, reason)
            }
        }
    }

    fun from(member: AgentTeamMember): Map<String, String> = member.context[CONTEXT]?.let { raw ->
        val rows = JSONArray(raw)
        read(JSONObject().put(FIELD, rows).put("depends_on",
            JSONArray((0 until rows.length()).map { rows.getJSONObject(it).getString("work_id") })))
    }.orEmpty()

    fun context(item: JSONObject): Map<String, String> = if (!item.has(FIELD)) emptyMap()
        else mapOf(CONTEXT to array(read(item)).toString())

    fun restore(item: JSONObject, context: Map<String, String>) = item.also {
        context[CONTEXT]?.let { raw -> it.put(FIELD, JSONArray(raw)) }
    }

    fun array(values: Map<String, String>) = JSONArray(values.entries.sortedBy { it.key }.map {
        JSONObject().put("work_id", it.key).put("reason", it.value)
    })
}
