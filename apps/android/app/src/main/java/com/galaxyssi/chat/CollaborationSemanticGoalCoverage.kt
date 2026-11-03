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

    private fun kind(segment: JSONObject): String {
        val value = if (segment.has("coverage_kind")) requiredText(segment, "coverage_kind") else "outcome"
        require(value in setOf("outcome", "constraint", "context")) { "coverage_kind must be outcome, constraint or context" }
        return value
    }

    private fun keysMatch(segment: JSONObject, keys: Set<String>) =
        segment.keys().asSequence().toSet().let { it == keys || it == keys + "coverage_kind" }

    private fun ids(array: JSONArray, allowEmpty: Boolean = false): Set<String> {
        val result = linkedSetOf<String>()
        require(allowEmpty || array.length() > 0) { "Each outcome segment needs explicit criterion IDs" }
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
            require(keysMatch(segment, setOf("id", "criterion_ids", "verdict", "rationale", "unresolved"))) {
                "Review host source IDs with verdicts, not replacement source text or offsets"
            }
            require(seen.add(requiredText(segment, "id"))) { "Duplicate reviewed source segment" }
            ids(segment.getJSONArray("criterion_ids"), allowEmpty = kind(segment) != "outcome")
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
                require(id in sourceIds && keysMatch(segment, setOf("id", "criterion_ids", "rationale"))) {
                    "Map host source IDs only; invented IDs, replacement text and model-counted offsets are invalid"
                }
                requiredText(segment, "rationale")
                val type = kind(segment)
                val targets = ids(segment.getJSONArray("criterion_ids"), allowEmpty = type != "outcome")
                require(expected.keys.containsAll(targets)) { "Source segment references an unknown criterion" }
                val check = requireNotNull(byId[id]) { "A source segment has no independent semantic assessment" }
                require(kind(check) == type && ids(check.getJSONArray("criterion_ids"), allowEmpty = type != "outcome") == targets && check.getString("verdict") == "supported" &&
                    check.getJSONArray("unresolved").length() == 0) { "Segment review disagrees with the exact mapping or retains objections" }
                if (type == "outcome") mapped.addAll(targets)
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

    fun instructions() = "Completion needs goal_coverage:{mapping:{object_id,revision,sha256},review:{object_id,revision,sha256}}. " +
        "Copy source IDs and goal_sha256/criteria_sha256 from host acceptance feedback. Do not count offsets or invent hashes/source text. " +
        "Publish kind=artifact, body.semantic_goal_mapping:{format:'$FORMAT',goal_sha256,criteria_sha256," +
        "segments:[{id,coverage_kind:'outcome|constraint|context',criterion_ids:[],rationale}]}. " +
        "Outcome means requested deliverable and needs criterion IDs; mixed segments remain outcome with qualifiers. " +
        "Constraint means operating restriction; context means explanation. Their links may be empty, but explain continued applicability. " +
        "This classification neither grants authority nor proves compliance, receipt or unobserved events. " +
        "Cover every original source ID exactly once and every criterion through an outcome; omit no restrictions. " +
        "Large mappings may split non-overlapping source IDs into parts sharing both complete host hashes: " +
        "goal_coverage:{parts:[{mapping:exact reference,review:exact reference},...]}. Each part needs its own independent review. " +
        CollaborationGoalCoverageManifest.instructions() +
        "A reviewer distinct from the coordinator and all mapping contributors publishes kind=acceptance_review with " +
        "body.semantic_coverage_review:{target:exact mapping reference,verdict,rationale,unresolved:[]," +
        "segments:[{id,coverage_kind,criterion_ids,verdict,rationale,unresolved:[]}]}, citing the mapping in parents. " +
        "Independently check classifications, exact links and qualifiers. Reject a requested outcome misclassified as context/constraint. " +
        "Use supported/refuted/not_tested; preserve omissions/ambiguity, never narrow the goal. " +
        "A two-person team suffices: coordinator/author EXECUTE maps, peer VERIFY reviews delivery and mapping in separate objects. " +
        "Changed criteria require a new host binding and mapping review. The host checks integrity, not semantic/scientific truth. "
}
