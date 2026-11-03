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
    const val REPAIR_REASON = "collaboration_research_repair_reason"
    const val REPAIR_INSTRUCTIONS = "For an incomplete/rejected delivery, use a NEW work id, repair_of=<finished original work ID>, " +
        "and repair_reason=<nonempty concrete missing delivery or failed check>. Finished means execution ended, not goal acceptance. " +
        "Preserve the original evidence and repair only the missing result; never replay completed side effects. " +
        "Declare dependencies for original outputs you need to read; repair_of alone grants no access. " +
        "Omit both repair fields for ordinary new work."
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
                "$REPAIR_INSTRUCTIONS No work was dispatched."
    }

    fun compile(work: List<JSONObject>, finished: Set<String>, finishedAuthors: Map<String, String> = emptyMap(),
                milestoneAuthors: Map<String, String> = emptyMap()): Plan = runCatching {
        val byId = work.associateBy(::id)
        require(byId.size == work.size) { "Duplicate work IDs; use one stable ID per assignment" }
        // Checkpoint graphs include ended nodes; only admission of new requests diagnoses reused IDs.
        val pending = byId.filterKeys { it !in finished }
        val edges = pending.mapValues { (id, item) ->
            validateRepair(item, id, finished)
            require(!item.has("depends_on") || item.optJSONArray("depends_on") != null) { "depends_on must be an array" }
            require(!item.has("dependency_policy") || item.optString("dependency_policy") in setOf("success", "terminal")) {
                "dependency_policy must be success or terminal"
            }
            val dependencies = dependencies(item)
            require(id !in dependencies) { "Work cannot depend on itself: $id" }
            require(dependencies.all { it in byId || it in finished }) { "Unknown or unfinished dependency for $id" }
            CollaborationDataDependencies.read(item)
            CollaborationCompletionBarriers.read(item)
            CollaborationPeerExchangePolicy.read(item)
            val targets = CollaborationReviewTargets.read(item)
            val milestones = CollaborationMilestoneDispatch.uses(item)
            val reviewMilestones = CollaborationReviewTargets.milestones(item)
            require(milestones.all { !milestoneAuthors[it].isNullOrBlank() }) { "Unknown or ungranted milestone for $id" }
            if (item.optBoolean("independent_review")) {
                require(targets.isNotEmpty() || reviewMilestones.isNotEmpty()) { "Independent review $id must name the work being reviewed" }
                require(reviewMilestones.all { milestoneAuthors[it] != item.optString("member") }) {
                    "Independent review $id requires a different author for each reviewed milestone"
                }
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

    fun repairContext(item: JSONObject): Map<String, String> = mapOf(
        REPAIR_OF to item.optString("repair_of"), REPAIR_REASON to item.optString("repair_reason"))

    fun restoreRepair(item: JSONObject, context: Map<String, String>): JSONObject = item.apply {
        mapOf("repair_of" to REPAIR_OF, "repair_reason" to REPAIR_REASON).forEach { (field, key) ->
            context[key]?.takeIf(String::isNotBlank)?.let { put(field, it) }
        }
    }

    fun sameRepair(left: JSONObject, right: JSONObject): Boolean = listOf("repair_of", "repair_reason").all {
        left.has(it) == right.has(it) && left.opt(it) == right.opt(it)
    }

    private fun validateRepair(item: JSONObject, id: String, finished: Set<String>) {
        if (!item.has("repair_of") && !item.has("repair_reason")) return
        fun fieldError(field: String, expected: String, actual: String): String =
            "REPAIR_CONTRACT_INVALID work_id=$id field=$field: expected $expected; actual $actual. " +
                "JSON syntax is valid. No work was dispatched. Preserve the original output and correct this field."
        for (field in listOf("repair_of", "repair_reason")) {
            val value = item.opt(field)
            require(value is String && value.isNotBlank()) {
                fieldError(field, "a nonempty string", when {
                    !item.has(field) -> "missing"
                    value == JSONObject.NULL -> "null"
                    value is String -> "blank string"
                    else -> "${value.javaClass.simpleName} (not a string)"
                })
            }
        }
        val original = item.getString("repair_of")
        require(original != id) { fieldError("repair_of", "an original work ID distinct from the NEW repair ID", "self-reference") }
        require(original in finished) {
            fieldError("repair_of", "a finished original work ID", "$original is not in finished work")
        }
    }
}
