package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A review's subject is distinct from the evidence it consumes, including the reviewer's own tests. */
internal object CollaborationReviewTargets {
    const val FIELD = "review_targets"
    const val CONTEXT = "collaboration_research_review_targets"

    fun read(item: JSONObject): Set<String> {
        require(!item.has("independent_review") || item.opt("independent_review") is Boolean) {
            "Work ${CollaborationWorkGraph.id(item)}: independent_review must be Boolean"
        }
        val independent = item.optBoolean("independent_review")
        if (!item.has(FIELD)) return if (independent) CollaborationWorkGraph.dependencies(item) else emptySet()
        val prefix = "Work ${CollaborationWorkGraph.id(item)}.$FIELD"
        require(independent) { "$prefix requires independent_review=true" }
        val array = requireNotNull(item.optJSONArray(FIELD)) { "$prefix must be an array of work IDs" }
        val targets = linkedSetOf<String>()
        repeat(array.length()) { index ->
            val target = array.opt(index)
            require(target is String && target.isNotBlank() && targets.add(target)) {
                "$prefix[$index] must be a nonblank, unique work ID"
            }
        }
        require(targets.isNotEmpty() || CollaborationMilestoneDispatch.uses(item).isNotEmpty()) {
            "$prefix cannot be empty without exact milestone review subjects"
        }
        require(CollaborationWorkGraph.dependencies(item).containsAll(targets)) {
            "$prefix must be a subset of depends_on; retain every input dependency"
        }
        return targets
    }

    fun context(item: JSONObject): Map<String, String> = mapOf(CONTEXT to
        if (item.optBoolean("independent_review") && (item.has(FIELD) || read(item).isNotEmpty())) JSONArray(read(item).sorted()).toString() else "")

    fun restore(item: JSONObject, context: Map<String, String>): JSONObject = item.apply {
        context[CONTEXT]?.takeIf(String::isNotBlank)?.let { put(FIELD, JSONArray(it)) }
    }

    fun instructions() = "For independent_review=true, review_targets optionally lists the exact work IDs whose artifacts " +
        "are being reviewed; each must also be in depends_on and have a different, known author. " +
        "depends_on contains ALL required inputs, including the reviewer's own independently collected test data. " +
        "Without review_targets, every dependency is treated as a review target. Do not disable independence or drop " +
        "real input dependencies to bypass an author conflict. Target selection does not certify scientific independence " +
        "or accept a result; exact artifact-version and acceptance checks still apply."
}
