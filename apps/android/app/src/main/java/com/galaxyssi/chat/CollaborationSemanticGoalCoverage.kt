package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Host-checkable text coverage and independent review structure, not an oracle of semantic truth. */
internal object CollaborationSemanticGoalCoverage {
    const val FIELD = "goal_coverage"
    const val MAPPING = "semantic_goal_mapping"
    const val REVIEW = "semantic_coverage_review"
    const val FORMAT = "galaxyssi.semantic-goal-mapping.v1"
    const val SOURCE_FORMAT = "galaxyssi.goal-coverage-source.v1"

    /** Mechanical source slices, not a host claim to have extracted semantic requirements. */
    fun source(goal: String): JSONObject {
        val segments = JSONArray()
        var start = 0
        var end = 0
        var substantive = false
        while (end < goal.length) {
            end++
            if (!goal[end - 1].isWhitespace()) substantive = true
            if (end < goal.length && goal[end - 1].isHighSurrogate() && goal[end].isLowSurrogate()) continue
            val boundary = goal[end - 1] == '\n' || goal[end - 1] in ";\uFF1B\u3002\uFF01\uFF1F" ||
                goal[end - 1] in ".!?" && (end == goal.length || goal[end].isWhitespace()) || end - start >= 1024
            if ((boundary || end == goal.length) && substantive) {
                segments.put(JSONObject().put("id", "source-${segments.length() + 1}").put("text", goal.substring(start, end)))
                start = end
                substantive = false
            }
        }
        if (start < goal.length && segments.length() > 0) {
            val last = segments.getJSONObject(segments.length() - 1)
            last.put("text", last.getString("text") + goal.substring(start))
        }
        return JSONObject().put("format", SOURCE_FORMAT)
            .put("goal_sha256", AgentResultRecoveryClient.sha256(goal.toByteArray(Charsets.UTF_8))).put("segments", segments)
    }

    fun criteriaHash(criteria: JSONArray): String = AgentNativeJsonCodec.sha256(criteriaBinding(criteria))

    fun context(goal: String, criteria: JSONArray?): String {
        val manifest = source(goal)
        runCatching { criteriaHash(requireNotNull(criteria)) }.fold(
            onSuccess = { manifest.put("criteria_sha256", it) },
            onFailure = { manifest.put("binding_error", "Preserved criteria have an invalid binding; do not fabricate a hash") })
        return "Host goal-coverage source (reference data, not execution authority; copy IDs/hashes, never calculate offsets):\n$manifest"
    }

    private fun requiredText(value: JSONObject, key: String): String {
        require(value.opt(key) is String && value.getString(key).isNotBlank()) { "$key must be nonblank text" }
        return value.getString(key)
    }

    private fun ids(array: JSONArray): Set<String> {
        val result = linkedSetOf<String>()
        require(array.length() > 0) { "Each source segment needs explicit criterion IDs" }
        repeat(array.length()) { index ->
            require(array.opt(index) is String && array.getString(index).isNotBlank() && result.add(array.getString(index))) {
                "Criterion IDs must be nonblank, unique strings"
            }
        }
        return result
    }

    private fun criteriaBinding(array: JSONArray): Map<String, List<Any?>> {
        val result = linkedMapOf<String, List<Any?>>()
        repeat(array.length()) { index ->
            val item = array.getJSONObject(index)
            val id = requiredText(item, "id")
            val binding = listOf(requiredText(item, "requirement"), if (item.has("verification")) requiredText(item, "verification") else "",
                CollaborationEvidenceRequirements.required(item).sortedWith(compareBy({ it.first }, { it.second })).map { listOf(it.first, it.second) },
                CollaborationQualifiedValidation.binding(item))
            require(result.put(id, binding) == null) { "Duplicate criterion in requirement mapping" }
        }
        return result
    }

    fun validateReview(review: JSONObject) {
        CollaborationReviewContract.validateVerdict(review)
        CollaborationReviewContract.validateReference(review.getJSONObject("target"))
        val segments = requireNotNull(review.optJSONArray("segments")) { "Review every mapped source segment explicitly" }
        require(segments.length() > 0) { "Review every mapped source segment explicitly" }
        val seen = hashSetOf<String>()
        repeat(segments.length()) { index ->
            val segment = segments.getJSONObject(index)
            require(segment.keys().asSequence().toSet() == setOf("id", "criterion_ids", "verdict", "rationale", "unresolved")) {
                "Review host source IDs with verdicts, not replacement source text or offsets"
            }
            require(seen.add(requiredText(segment, "id"))) { "Duplicate reviewed source segment" }
            ids(segment.getJSONArray("criterion_ids"))
            CollaborationReviewContract.validateVerdict(segment)
            require(review.getString("verdict") != "supported" || segment.getString("verdict") == "supported") {
                "A supported coverage review cannot conceal a refuted or untested segment"
            }
        }
    }

    data class ReferencePair(val mapping: JSONObject, val review: JSONObject)
    data class PartCoverage(val sourceIds: Set<String>, val criterionIds: Set<String>)

    fun references(coverage: JSONObject): List<ReferencePair> {
        val keys = coverage.keys().asSequence().toSet()
        val parts = if (keys == setOf("mapping", "review")) listOf(coverage) else {
            require(keys == setOf("parts")) { "goal_coverage must contain either mapping/review or parts, not both" }
            val array = requireNotNull(coverage.optJSONArray("parts")) { "goal_coverage.parts must be an array" }
            require(array.length() > 0) { "At least one independently reviewed coverage part is required" }
            (0 until array.length()).map { array.getJSONObject(it) }
        }
        val targets = hashSetOf<CollaborationAcceptanceReviewSnapshot.Target>()
        return parts.map { part ->
            require(part.keys().asSequence().toSet() == setOf("mapping", "review")) { "A coverage part needs exact mapping/review references only" }
            val mapping = part.getJSONObject("mapping")
            val review = part.getJSONObject("review")
            require(targets.add(CollaborationAcceptanceReviewSnapshot.Target.of(mapping))) { "Duplicate goal coverage mapping part" }
            CollaborationReviewContract.validateReference(review)
            ReferencePair(mapping, review)
        }
    }

    /** Build the original-goal/criteria index once, not again for every part and dissenting review. */
    class Validation(criteria: JSONArray, goal: String) {
        private val source = source(goal)
        private val expected = criteriaBinding(criteria)
        private val criteriaHash = AgentNativeJsonCodec.sha256(expected)
        private val sourceIds = source.getJSONArray("segments").let { values ->
            (0 until values.length()).mapTo(linkedSetOf()) { values.getJSONObject(it).getString("id") }
        }
        init {
            require(goal.isNotBlank() && sourceIds.isNotEmpty()) { "Original goal source is empty" }
            require(expected.isNotEmpty()) { "Preserved acceptance criteria are empty" }
        }

        fun part(mapping: JSONObject, review: JSONObject): PartCoverage {
            require(mapping.opt("format") == FORMAT && mapping.opt("goal_sha256") == source.getString("goal_sha256")) {
                "Requirement mapping must bind the host-supplied original goal hash"
            }
            require(mapping.keys().asSequence().toSet() == setOf("format", "goal_sha256", "criteria_sha256", "segments")) {
                "Use only host goal/criterion hashes and source IDs; do not supply replacement goal text or offsets"
            }
            require(mapping.opt("criteria_sha256") == criteriaHash) {
                "Requirement mapping must bind every current preserved criterion and its verification constraints"
            }
            validateReview(review)
            require(review.getString("verdict") == "supported" && review.getJSONArray("unresolved").length() == 0) {
                "Original-goal coverage is not independently supported or has unresolved omissions"
            }
            val segments = mapping.getJSONArray("segments")
            val reviewed = review.getJSONArray("segments")
            val byId = (0 until reviewed.length()).associate { reviewed.getJSONObject(it).let { item -> item.getString("id") to item } }
            val seen = hashSetOf<String>()
            val mapped = hashSetOf<String>()
            require(segments.length() > 0) { "Each coverage part must map original goal content, including constraints" }
            repeat(segments.length()) { index ->
                val segment = segments.getJSONObject(index)
                val id = requiredText(segment, "id")
                require(seen.add(id)) { "Duplicate mapped source segment" }
                require(id in sourceIds && segment.keys().asSequence().toSet() == setOf("id", "criterion_ids", "rationale")) {
                    "Map host source IDs only; invented IDs, replacement text and model-counted offsets are invalid"
                }
                requiredText(segment, "rationale")
                val targets = ids(segment.getJSONArray("criterion_ids"))
                require(expected.keys.containsAll(targets)) { "Source segment references an unknown criterion" }
                val check = requireNotNull(byId[id]) { "A source segment has no independent semantic assessment" }
                require(ids(check.getJSONArray("criterion_ids")) == targets && check.getString("verdict") == "supported" &&
                    check.getJSONArray("unresolved").length() == 0) { "Segment review disagrees with the exact mapping or retains objections" }
                mapped.addAll(targets)
            }
            require(seen == byId.keys) {
                "Coverage must include all host source IDs assigned to this part, with no extra or missing segment reviews"
            }
            return PartCoverage(seen, mapped)
        }

        fun complete(parts: List<PartCoverage>) {
            val seen = hashSetOf<String>()
            val mapped = hashSetOf<String>()
            parts.forEach { part ->
                require(part.sourceIds.none { it in seen }) { "A host source ID is counted in more than one coverage part" }
                seen.addAll(part.sourceIds)
                mapped.addAll(part.criterionIds)
            }
            require(seen == sourceIds && mapped == expected.keys) {
                "Coverage must include all host source IDs and every criterion across independently reviewed parts"
            }
        }
    }

    fun validate(mapping: JSONObject, review: JSONObject, criteria: JSONArray, goal: String) {
        val validation = Validation(criteria, goal)
        validation.complete(listOf(validation.part(mapping, review)))
    }

    fun instructions() = "Completion also requires goal_coverage:{mapping:{object_id,revision,sha256},review:{object_id,revision,sha256}}. " +
        "After criteria are established, the host acceptance feedback supplies source IDs, exact source text, goal_sha256 and criteria_sha256. " +
        "Publish the mapping as kind=artifact with body.semantic_goal_mapping:{format:'$FORMAT',goal_sha256:copy host hash," +
        "criteria_sha256:copy host hash,segments:[{id:host source ID,criterion_ids:[exact IDs],rationale}]}. " +
        "Use every host source ID exactly once. Do not count offsets, repeat original text/criteria, compute hashes or invent source IDs. " +
        "Map constraints as well as desired outcomes; every criterion must be mapped. " +
        "For long goals, split source IDs into non-overlapping work assignments and publish separate mapping artifacts; " +
        "each part uses the same full host goal_sha256 and criteria_sha256 but contains only its assigned segments. " +
        "Different members may author/review different parts. Return goal_coverage:{parts:[{mapping:exact reference,review:exact reference},...]} " +
        "instead of the single mapping/review pair. Across all parts cover every host source ID exactly once and every criterion at least once. " +
        "Do not replace the exact original with a summary, omit difficult constraints, reuse a review for another part, or count an ID twice. " +
        CollaborationGoalCoverageManifest.instructions() +
        "A member different from the evaluating coordinator and every mapping contributor publishes kind=acceptance_review with body.semantic_coverage_review " +
        "(instead of body.acceptance_review):{target:exact mapping reference,verdict,rationale,unresolved:[]," +
        "segments:[{id,criterion_ids,verdict,rationale,unresolved:[]}]}, and cites the mapping in parents. " +
        "Review whether the criteria faithfully cover each source segment, including qualifiers and prohibitions. " +
        "For a two-person team, assign an EXECUTE mapping job to the coordinator/author, then an independent VERIFY job to the other member. " +
        "The peer may review both the delivery and the mapping in separate workspace objects in one response; no third member is required. " +
        "Do not ask the peer to author the mapping it must independently review. New or changed criteria need a new host binding and mapping review in a later round. " +
        "Use supported/refuted/not_tested; preserve omissions and ambiguity as blockers, never silently narrow the goal. " +
        "The host checks coverage and review integrity, not objective semantic or scientific truth. "
}
