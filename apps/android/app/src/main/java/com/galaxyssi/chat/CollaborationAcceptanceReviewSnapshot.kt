package com.galaxyssi.chat

import org.json.JSONObject

/** Evaluation-local index. Isolated revisions are inspected for continuity, never used as verdicts. */
internal class CollaborationAcceptanceReviewSnapshot private constructor(
    internal val owner: CollaborationResearchWorkspace,
    internal val access: CollaborationWorkspaceAccess,
    internal val mutationToken: String?,
    private val index: Map<Binding, List<String>>
) {
    data class Target(val objectId: String, val revision: Long, val sha256: String) {
        companion object {
            fun of(ref: JSONObject): Target {
                CollaborationReviewContract.validateReference(ref)
                return Target(ref.getString("object_id"), ref.getLong("revision"), ref.getString("sha256"))
            }
        }
    }

    data class Binding(val target: Target, val field: String, val criterionId: String = "", val requirement: String = "") {
        companion object {
            fun of(target: JSONObject, field: String, criterionId: String = "", requirement: String = "") =
                Binding(Target.of(target), field, if (field == CollaborationReviewContract.KIND) criterionId else "",
                    if (field == CollaborationReviewContract.KIND) requirement else "")

            fun fromBody(body: JSONObject): Binding {
                CollaborationReviewContract.validate(CollaborationReviewContract.KIND, body)
                val field = if (body.has(CollaborationSemanticGoalCoverage.REVIEW))
                    CollaborationSemanticGoalCoverage.REVIEW else CollaborationReviewContract.KIND
                val check = body.getJSONObject(field)
                return of(check.getJSONObject("target"), field, check.optString("criterion_id"), check.optString("requirement"))
            }
        }
    }

    internal data class Head(val key: String, val revision: JSONObject)

    fun reviews(binding: Binding): List<JSONObject> = index[binding].orEmpty().map(::JSONObject)

    internal fun allReviews(): List<JSONObject> = index.values.flatMap { values -> values.map(::JSONObject) }

    companion object {
        const val PAGE_SIZE = 100

        internal fun scan(owner: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, token: String?,
                          page: (String) -> List<Head>, read: (String, Int) -> JSONObject,
                          relevant: (JSONObject, Binding) -> Boolean): CollaborationAcceptanceReviewSnapshot {
            val index = linkedMapOf<Binding, MutableList<String>>()
            val visited = hashSetOf<String>()
            var cursor = ""

            fun binding(saved: JSONObject): Binding? {
                if (saved.getString("run_id") != access.runId || saved.getString("turn_id") != access.turnId ||
                    saved.getString("kind") != CollaborationReviewContract.KIND) return null
                return Binding.fromBody(saved.getJSONObject("body")).takeIf { relevant(saved, it) }
            }

            fun previous(current: JSONObject): JSONObject {
                val earlier = read(current.getString("object_id"), current.getInt("revision") - 1)
                require(earlier.getString("sha256") == current.getString("previous_sha256")) {
                    "Acceptance review history digest changed"
                }
                return earlier
            }

            fun validateHistory(saved: JSONObject, expected: Binding) {
                val author = saved.getString("person_id")
                var current = saved
                val versions = hashSetOf<Int>()
                while (current.getInt("revision") > 1) {
                    require(versions.add(current.getInt("revision"))) { "Acceptance review history contains a cycle" }
                    current = previous(current)
                    require(access.canRead(current)) { "Acceptance review history is incomplete or isolated" }
                    require(current.getString("kind") == CollaborationReviewContract.KIND &&
                        current.getString("person_id") == author && Binding.fromBody(current.getJSONObject("body")) == expected) {
                        "Acceptance review history changed its author or binding"
                    }
                }
                require(current.getString("previous_sha256").isEmpty()) { "Initial review revision has a previous digest" }
            }

            while (true) {
                val heads = page(cursor)
                require(heads.size <= PAGE_SIZE) { "Acceptance review directory returned an oversized page" }
                if (heads.isEmpty()) break
                heads.forEach { head ->
                    require(head.key > cursor && visited.add(head.key)) {
                        "Acceptance review directory has invalid or non-advancing pagination"
                    }
                    cursor = head.key
                    val saved = head.revision
                    if (!access.canRead(saved)) {
                        var current = saved
                        val versions = hashSetOf<Int>()
                        while (current.getInt("revision") > 1) {
                            require(versions.add(current.getInt("revision"))) { "Acceptance review history contains a cycle" }
                            current = previous(current)
                            if (access.canRead(current)) {
                                require(binding(current) == null) {
                                    "A review of this target has a newer isolated revision; wait for readable review state"
                                }
                                break
                            }
                        }
                        if (current.getInt("revision") == 1) require(current.getString("previous_sha256").isEmpty()) {
                            "Initial review revision has a previous digest"
                        }
                    } else {
                        binding(saved)?.let { key ->
                            validateHistory(saved, key)
                            index.getOrPut(key) { mutableListOf() }.add(saved.toString())
                        }
                    }
                }
            }
            return CollaborationAcceptanceReviewSnapshot(owner, access, token, index)
        }
    }
}
