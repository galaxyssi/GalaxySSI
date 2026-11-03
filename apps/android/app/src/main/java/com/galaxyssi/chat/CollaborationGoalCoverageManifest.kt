package com.galaxyssi.chat

import org.json.JSONObject
import org.json.JSONArray

/** Resolve only exact saved workspace references, never model-supplied URLs or inline verdicts. */
internal object CollaborationGoalCoverageManifest {
    const val FIELD = "semantic_goal_manifest"
    const val FORMAT = "galaxyssi.semantic-goal-manifest.v1"
    data class Resolved(val parts: List<CollaborationSemanticGoalCoverage.ReferencePair>, val manifests: List<JSONObject>)

    fun resolve(coverage: JSONObject, criteria: JSONArray, goal: String, read: (JSONObject) -> JSONObject): Resolved {
        if (!coverage.has("manifest")) return Resolved(CollaborationSemanticGoalCoverage.references(coverage), emptyList())
        require(coverage.keys().asSequence().toSet() == setOf("manifest")) { "A coverage manifest cannot be mixed with inline coverage" }
        val goalHash = CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256")
        val criteriaHash = CollaborationSemanticGoalCoverage.criteriaHash(criteria)
        val pending = ArrayDeque<JSONObject>()
        pending.add(coverage.getJSONObject("manifest"))
        val visited = hashSetOf<CollaborationAcceptanceReviewSnapshot.Target>()
        val mappingTargets = hashSetOf<CollaborationAcceptanceReviewSnapshot.Target>()
        val manifests = mutableListOf<JSONObject>()
        val parts = mutableListOf<CollaborationSemanticGoalCoverage.ReferencePair>()
        while (pending.isNotEmpty()) {
            val ref = pending.removeFirst()
            require(visited.add(CollaborationAcceptanceReviewSnapshot.Target.of(ref))) {
                "Goal coverage manifests contain a cycle or repeated branch"
            }
            val saved = read(ref)
            require(saved.getString("kind") == "artifact") { "Goal coverage manifest must be a saved artifact" }
            val body = requireNotNull(saved.getJSONObject("body").optJSONObject(FIELD)) { "Missing saved goal coverage manifest" }
            val header = setOf("format", "goal_sha256", "criteria_sha256")
            val keys = body.keys().asSequence().toSet()
            require(keys == header + "parts" || keys == header + "manifests") {
                "A coverage manifest must contain either leaf parts or child manifests, without other fields"
            }
            require(body.optString("format") == FORMAT && body.optString("goal_sha256") == goalHash &&
                body.optString("criteria_sha256") == criteriaHash) { "Goal coverage manifest uses a different original goal or criterion binding" }
            val parents = saved.getJSONArray("parents").let { values -> (0 until values.length()).mapTo(hashSetOf()) {
                CollaborationAcceptanceReviewSnapshot.Target.of(values.getJSONObject(it))
            } }
            fun preserved(child: JSONObject) {
                require(CollaborationAcceptanceReviewSnapshot.Target.of(child) in parents) {
                    "Every manifest child mapping, review or manifest must be preserved in parents"
                }
            }
            if (body.has("parts")) {
                CollaborationSemanticGoalCoverage.references(JSONObject().put("parts", body.getJSONArray("parts"))).forEach { part ->
                    preserved(part.mapping)
                    preserved(part.review)
                    require(mappingTargets.add(CollaborationAcceptanceReviewSnapshot.Target.of(part.mapping))) {
                        "Duplicate mapping across goal coverage manifests"
                    }
                    parts += part
                }
            } else {
                val children = body.getJSONArray("manifests")
                require(children.length() > 0) { "A coverage manifest cannot have an empty branch" }
                repeat(children.length()) { index ->
                    val child = children.getJSONObject(index)
                    preserved(child)
                    pending.addLast(child)
                }
            }
            manifests += ref
        }
        require(parts.isNotEmpty()) { "A coverage manifest must resolve to reviewed mapping parts" }
        return Resolved(parts, manifests)
    }

    fun instructions() = "For too many parts to inline, publish kind=artifact with body.$FIELD:{format:'$FORMAT'," +
        "goal_sha256:copy full host goal hash,criteria_sha256:copy full host criteria hash,parts:[{mapping:exact reference,review:exact reference},...]}. " +
        "Cite every mapping and review in parents. Larger directories can instead contain manifests:[exact child manifest references], " +
        "also cited in parents; do not mix parts and manifests in one artifact. Finish with goal_coverage:{manifest:exact root reference}. " +
        "Directories aggregate references only; they never replace source-level independent reviews or confer scientific validation. "
}
