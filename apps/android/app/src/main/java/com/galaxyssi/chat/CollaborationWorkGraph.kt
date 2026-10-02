package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Work IDs describe business dependencies; dispatch IDs remain host-owned and round-specific. */
internal object CollaborationWorkGraph {
    const val FEEDBACK = "collaboration_research_graph_feedback"
    const val POLICY = "collaboration_research_dependency_policy"
    const val INDEPENDENT = "collaboration_research_independent_review"
    const val PREVIOUS_DEPENDENCIES = "collaboration_research_previous_dependencies"
    data class Plan(val work: List<JSONObject>, val error: String = "")

    fun id(item: JSONObject): String = item.optString("id").ifBlank {
        UUID.nameUUIDFromBytes("${item.optString("member")}:${item.optString("stage")}:${item.optString("assignment")}".toByteArray()).toString()
    }

    fun dependencies(item: JSONObject): Set<String> = item.optJSONArray("depends_on")?.let { array ->
        (0 until array.length()).mapTo(linkedSetOf()) { array.getString(it).also { value ->
            require(value.isNotBlank()) { "Empty dependency ID" }
        } }
    }.orEmpty()

    fun compile(work: List<JSONObject>, finished: Set<String>, finishedAuthors: Map<String, String> = emptyMap()): Plan = runCatching {
        val byId = work.associateBy(::id)
        require(byId.size == work.size) { "Duplicate work IDs; use one stable ID per assignment" }
        val pending = byId.filterKeys { it !in finished }
        val edges = pending.mapValues { (id, item) ->
            require(!item.has("depends_on") || item.optJSONArray("depends_on") != null) { "depends_on must be an array" }
            require(!item.has("dependency_policy") || item.optString("dependency_policy") in setOf("success", "terminal")) {
                "dependency_policy must be success or terminal"
            }
            val dependencies = dependencies(item)
            require(id !in dependencies) { "Work cannot depend on itself: $id" }
            require(dependencies.all { it in byId || it in finished }) { "Unknown or unfinished dependency for $id" }
            if (item.optBoolean("independent_review")) {
                require(dependencies.isNotEmpty()) { "Independent review must name the work being reviewed" }
                require(dependencies.all { dependency ->
                    val author = if (dependency in finished) finishedAuthors[dependency] else byId[dependency]?.optString("member")
                    !author.isNullOrBlank() && author != item.optString("member")
                }) { "Independent review requires a known, different author for every target" }
            }
            dependencies.filterTo(linkedSetOf()) { it in pending }
        }
        require(AgentDependencyGraph.isAcyclic(edges)) { "Work dependencies contain a cycle" }
        Plan(pending.values.toList())
    }.getOrElse { Plan(emptyList(), it.message ?: "Invalid work dependency graph") }

    fun completedDependencies(item: JSONObject, finished: Set<String>): String =
        JSONArray(dependencies(item).filter { it in finished }).toString()
}
