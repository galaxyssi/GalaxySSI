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
    const val REPAIR_OF = "collaboration_research_repair_of"
    data class Plan(val work: List<JSONObject>, val error: String = "")

    fun id(item: JSONObject): String = item.optString("id").ifBlank {
        UUID.nameUUIDFromBytes("${item.optString("member")}:${item.optString("stage")}:${item.optString("assignment")}".toByteArray()).toString()
    }

    fun dependencies(item: JSONObject): Set<String> = item.optJSONArray("depends_on")?.let { array ->
        (0 until array.length()).mapTo(linkedSetOf()) { array.getString(it).also { value ->
            require(value.isNotBlank()) { "Empty dependency ID" }
        } }
    }.orEmpty()

    fun reusedRequestError(work: List<JSONObject>, finished: Set<String>): String {
        val repeated = work.map(::id).toSet().intersect(finished)
        return if (repeated.isEmpty()) "" else
            "COMPLETED_DISPATCH_REUSED: ${repeated.joinToString()}. Execution ended; this does NOT prove delivery or goal acceptance. " +
                "To repair an incomplete delivery, use a NEW work id with repair_of=<original work id> and repair_reason. " +
                "Read the saved output and repair only the missing delivery; do not replay completed side effects. No work was dispatched."
    }

    fun compile(work: List<JSONObject>, finished: Set<String>, finishedAuthors: Map<String, String> = emptyMap()): Plan = runCatching {
        val byId = work.associateBy(::id)
        require(byId.size == work.size) { "Duplicate work IDs; use one stable ID per assignment" }
        // Checkpoint graphs include ended nodes; only admission of new requests diagnoses reused IDs.
        val pending = byId.filterKeys { it !in finished }
        val edges = pending.mapValues { (id, item) ->
            if (item.has("repair_of")) {
                require(item.opt("repair_of") is String && item.getString("repair_of") in finished &&
                    item.getString("repair_of") != id && item.opt("repair_reason") is String &&
                    item.getString("repair_reason").isNotBlank()) {
                    "Repair needs a completed original work id, a distinct new id and a concrete repair_reason"
                }
            }
            require(!item.has("depends_on") || item.optJSONArray("depends_on") != null) { "depends_on must be an array" }
            require(!item.has("dependency_policy") || item.optString("dependency_policy") in setOf("success", "terminal")) {
                "dependency_policy must be success or terminal"
            }
            val dependencies = dependencies(item)
            require(id !in dependencies) { "Work cannot depend on itself: $id" }
            require(dependencies.all { it in byId || it in finished }) { "Unknown or unfinished dependency for $id" }
            val targets = CollaborationReviewTargets.read(item)
            if (item.optBoolean("independent_review")) {
                require(targets.isNotEmpty()) { "Independent review $id must name the work being reviewed" }
                targets.forEach { dependency ->
                    val author = if (dependency in finished) finishedAuthors[dependency] else byId[dependency]?.optString("member")
                    require(!author.isNullOrBlank() && author != item.optString("member")) {
                        "Independent review $id requires a known, different author for target $dependency; " +
                            "reviewer=${item.optString("member")}, author=${author ?: "unknown"}. " +
                            "If this dependency is the reviewer's test data, keep it in depends_on and list only " +
                            "the actual reviewed artifacts in review_targets; never exclude an artifact you are reviewing."
                    }
                }
            }
            dependencies.filterTo(linkedSetOf()) { it in pending }
        }
        require(AgentDependencyGraph.isAcyclic(edges)) { "Work dependencies contain a cycle" }
        Plan(pending.values.toList())
    }.getOrElse { Plan(emptyList(), it.message ?: "Invalid work dependency graph") }

    fun completedDependencies(item: JSONObject, finished: Set<String>): String =
        JSONArray(dependencies(item).filter { it in finished }).toString()
}
