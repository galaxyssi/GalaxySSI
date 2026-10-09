package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Data waits may bind published versions; completion waits still require the producer to finish. */
internal object CollaborationDataDependencies {
    const val FIELD = "data_dependencies"
    const val CONTEXT = "collaboration_research_data_dependencies"

    fun read(item: JSONObject): Map<String, String> {
        if (!item.has(FIELD)) return emptyMap()
        val rows = item.optJSONArray(FIELD)
        require(rows != null) { "data_dependencies must be an array" }
        val dependencies = CollaborationWorkGraph.dependencies(item)
        return buildMap {
            repeat(rows.length()) { index ->
                val row = rows.getJSONObject(index)
                require(row.keys().asSequence().toSet() == setOf("work_id", "requirement")) {
                    "data_dependencies[$index] requires only work_id and requirement"
                }
                require(row.opt("work_id") is String && row.opt("requirement") is String) {
                    "Data dependency work_id and requirement must be strings"
                }
                val id = row.getString("work_id")
                val requirement = row.getString("requirement")
                require(id.isNotBlank() && id in dependencies && id !in this) {
                    "Each data dependency must name a unique depends_on work ID"
                }
                require(requirement.isNotBlank() && requirement.length <= 2000) {
                    "A concrete data requirement within 2000 characters is required"
                }
                put(id, requirement)
            }
        }
    }

    fun from(member: AgentTeamMember): Map<String, String> {
        val rows = member.context[CONTEXT]?.let(::JSONArray) ?: return emptyMap()
        return read(JSONObject().put(FIELD, rows).put("depends_on",
            JSONArray((0 until rows.length()).map { rows.getJSONObject(it).getString("work_id") })))
    }

    fun context(item: JSONObject): Map<String, String> =
        (if (!item.has(FIELD)) emptyMap() else mapOf(CONTEXT to array(read(item)).toString())) +
            CollaborationCompletionBarriers.context(item)

    fun restore(item: JSONObject, context: Map<String, String>): JSONObject = CollaborationCompletionBarriers.restore(item, context).also {
        context[CONTEXT]?.let { raw -> it.put(FIELD, JSONArray(raw)) }
    }

    fun remaining(member: AgentTeamMember, removed: Set<String>): Map<String, String> =
        if (CONTEXT !in member.context) emptyMap() else mapOf(CONTEXT to array(from(member) - removed).toString())

    fun array(values: Map<String, String>) = JSONArray(values.entries.sortedBy { it.key }.map {
        JSONObject().put("work_id", it.key).put("requirement", it.value)
    })

    fun instructions() = """
        Distinguish data availability from execution completion when assigning work. For a depends_on edge that
        needs only published data, add data_dependencies:[{"work_id":"producer ID","requirement":"exact data needed"}].
        All other edges still wait for completion (including side effects, resource release and unfinished operations).
        Declaring a data dependency does not make it ready: the coordinator must inspect exact published versions
        and use rebind_inputs if they satisfy the original requirement. Use data_dependencies:[] to keep every edge
        completion-only until a separately validated plan revision; rebind_inputs/rebind_reviews cannot change that.
        For necessary operation ordering, side effects, resource release or full-producer acceptance, also declare
        completion_barriers:[{"work_id":"producer ID","reason":"why actual completion is required"}]. These edges
        cannot be revised to data waits. Do not declare barriers merely because a report has not finished writing.
        If you later find a non-barrier completion edge was a planning mistake, revise_input_dependencies explicitly
        records the correction and pins sufficient original evidence; it does not authorize skipping real operations.
    """.trimIndent()
}
