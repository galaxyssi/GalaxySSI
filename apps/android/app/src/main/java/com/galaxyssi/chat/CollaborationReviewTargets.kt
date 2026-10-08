package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A review's subject is distinct from the evidence it consumes, including the reviewer's own tests. */
internal object CollaborationReviewTargets {
    const val FIELD = "review_targets"
    const val CONTEXT = "collaboration_research_review_targets"
    const val MILESTONES = "review_milestones"
    const val MILESTONE_CONTEXT = "collaboration_research_review_milestones"

    fun milestones(item: JSONObject): Set<String> {
        val uses = CollaborationMilestoneDispatch.uses(item)
        if (!item.has(MILESTONES)) return if (item.optBoolean("independent_review")) uses else emptySet()
        require(item.optBoolean("independent_review")) { "$MILESTONES requires independent_review=true" }
        val array = requireNotNull(item.optJSONArray(MILESTONES)) { "$MILESTONES must be an array of exact host tokens" }
        val targets = linkedSetOf<String>()
        repeat(array.length()) { index ->
            val token = array.opt(index)
            require(token is String && token in uses && targets.add(token)) {
                "$MILESTONES[$index] must be a unique token from uses_milestones"
            }
        }
        return targets
    }

    fun milestones(member: AgentTeamMember): Set<String> =
        member.context[MILESTONE_CONTEXT]?.takeIf(String::isNotBlank)?.let(CollaborationMilestoneDispatch::strings)
            ?: if (member.context[CollaborationWorkGraph.INDEPENDENT] == "true")
                CollaborationMilestoneDispatch.inputs(member).mapTo(linkedSetOf()) { it.getString("token") } else emptySet()

    fun prompt(member: AgentTeamMember): String? {
        if (member.context[CollaborationWorkGraph.INDEPENDENT] != "true") return null
        val reviewed = milestones(member)
        return JSONObject().put(FIELD, member.context[CONTEXT]?.takeIf(String::isNotBlank)?.let(::JSONArray) ?: JSONObject.NULL)
            .put(MILESTONES, JSONArray(reviewed.sorted()))
            .put("supporting_milestones", JSONArray(CollaborationMilestoneDispatch.inputs(member)
                .map { it.getString("token") }.filter { it !in reviewed }))
            .put("scope", "Null review_targets means all task dependencies remain review subjects. " +
                "Supporting data are not the reviewed solution. Check exact versions against the original assignment; " +
                "publication is not validation or proof of scientific independence.").toString()
    }

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
        require(targets.isNotEmpty() || milestones(item).isNotEmpty()) {
            "$prefix cannot be empty without exact milestone review subjects"
        }
        require(CollaborationWorkGraph.dependencies(item).containsAll(targets)) {
            "$prefix must be a subset of depends_on; retain every input dependency"
        }
        return targets
    }

    fun context(item: JSONObject): Map<String, String> = mapOf(CONTEXT to
        if (item.optBoolean("independent_review") && (item.has(FIELD) || read(item).isNotEmpty())) JSONArray(read(item).sorted()).toString() else "",
        MILESTONE_CONTEXT to if (item.has(MILESTONES)) JSONArray(milestones(item).sorted()).toString() else "")

    fun restore(item: JSONObject, context: Map<String, String>): JSONObject = item.apply {
        context[CONTEXT]?.takeIf(String::isNotBlank)?.let { put(FIELD, JSONArray(it)) }
        context[MILESTONE_CONTEXT]?.takeIf(String::isNotBlank)?.let { put(MILESTONES, JSONArray(it)) }
    }

    fun instructions() = "For independent_review=true, review_targets optionally lists the exact work IDs whose artifacts " +
        "are being reviewed; each must also be in depends_on and have a different, known author. " +
        "depends_on contains ALL required inputs, including the reviewer's own independently collected test data. " +
        "Without review_targets, every dependency is treated as a review target. Do not disable independence or drop " +
        "real input dependencies to bypass an author conflict. Target selection does not certify scientific independence " +
        "or accept a result; exact artifact-version and acceptance checks still apply. " +
        "For pinned inputs, uses_milestones lists ALL required versions; optional review_milestones lists only the " +
        "review subjects among those tokens. Without review_milestones, all listed milestones are review subjects. " +
        "Frozen test data may be an input without being the reviewed solution. Never relabel the reviewed solution " +
        "as test data to bypass independence; the review must still name a known different author's subject. " +
        "A frozen dataset does not certify holdout independence, data quality, or completion of its producer's whole assignment."
}
