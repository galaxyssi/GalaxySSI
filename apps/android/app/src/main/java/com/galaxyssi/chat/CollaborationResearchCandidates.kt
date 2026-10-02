package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Documentary branch history in workspace rows, not a scorer or a scientific verifier. */
internal class CollaborationResearchCandidates(
    private val access: CollaborationWorkspaceAccess,
    private val read: (String, Int) -> JSONObject?,
    private val current: (String, Int) -> Boolean,
    private val changingIds: Set<String>
) {
    fun validate(item: JSONObject, head: JSONObject?, revision: JSONObject) {
        when (revision.getString("kind")) {
            CANDIDATE -> candidate(item, head, revision)
            EVENT -> event(head, revision)
        }
    }

    private fun candidate(item: JSONObject, head: JSONObject?, revision: JSONObject) {
        val body = revision.getJSONObject("body")
        text(body, "content")
        val change = body.getJSONObject(CANDIDATE)
        val operation = text(change, "operation")
        text(change, "rationale")
        require(!item.has("base_revision") || integer(item, "base_revision") != null) { "base_revision must be an integer" }
        val criteria = strings(change.getJSONArray("criteria"))
        require(criteria.isNotEmpty()) { "Candidates need explicit, nonempty criteria" }
        val parents = exactLinks(item.optJSONArray("parents") ?: JSONArray())
        val resolves = exactLinks(item.optJSONArray("resolves") ?: JSONArray())
        require(operation in setOf("propose", "revise", "combine", "retire")) { "Unknown candidate operation" }
        if (operation == "propose") {
            require(head == null && parents.isEmpty() && resolves.isEmpty()) { "Propose creates an independent new candidate" }
        } else {
            observations(revision, review = false)
            require(parents.all { it.getString("kind") == CANDIDATE && active(it) }) { "Parents must be active candidates" }
            if (operation == "combine") {
                require(head == null && parents.size >= 2 && parents.map { it.getString("object_id") }.toSet().size == parents.size) {
                    "Combine creates a distinct candidate from at least two distinct parents"
                }
                parents.forEach(::unchangedCurrent)
            } else {
                require(head != null && active(head) && parents.size == 1 && same(parents.single(), head)) {
                    "Revise/retire requires the exact active head as its sole parent"
                }
                require(integer(item, "base_revision") == head.getInt("revision")) { "Copy the exact integer base revision" }
            }
            val inheritedCriteria = parents.flatMap { strings(it.getJSONObject("body").getJSONObject(CANDIDATE).getJSONArray("criteria")) }
            require(criteria.containsAll(inheritedCriteria)) { "A candidate cannot discard inherited criteria" }
            if (operation == "retire") {
                require(body.getString("content") == head!!.getJSONObject("body").getString("content") &&
                    criteria == strings(head.getJSONObject("body").getJSONObject(CANDIDATE).getJSONArray("criteria"))) {
                    "Retirement preserves content and criteria; it is not a silent revision"
                }
            }
            resolves.forEach { resolved ->
                if (resolved.getString("kind") == EVENT) {
                    val challenge = resolved.getJSONObject("host_candidate_event")
                    require(challenge.getString("operation") == "challenge" && parents.any {
                        same(it, challenge.getJSONArray("targets").getJSONObject(0))
                    }) { "Addressed challenges must target an exact parent revision" }
                } else require(resolved.getString("kind") in setOf("counterexample", "question")) {
                    "Only preserved challenges, counterexamples or questions can be addressed"
                }
            }
        }
        val contributors = parents.flatMap { strings(it.getJSONObject("host_candidate").getJSONArray("contributors")) }
            .toMutableSet().apply { add(access.personId) }
        val basis = if (change.has("basis")) exactLinks(JSONArray().put(change.getJSONObject("basis"))).single().also { assessment ->
            val event = assessment.optJSONObject("host_candidate_event")
            require(operation == "revise" && event?.optString("operation") == "review" &&
                parents.any { same(it, event.getJSONArray("targets").getJSONObject(0)) } &&
                assessment.getJSONObject("body").getJSONObject(EVENT).getString("outcome") == "refuted") {
                "A repair basis must be an exact refutation of its parent"
            }
        } else null
        revision.put("host_candidate", JSONObject().put("operation", operation)
            .put("status", if (operation == "retire") "retired" else "active")
            .put("contributors", JSONArray(contributors.sorted()))
            .put("verification_state", if (operation == "retire") "ineligible_retired" else "requires_independent_review")
            .put("trust", "candidate_history_not_claim_verified").apply { basis?.let { put("basis", reference(it)) } })
    }

    private fun event(head: JSONObject?, revision: JSONObject) {
        require(head == null) { "Candidate events are immutable; publish a new event for a new assessment" }
        require(revision.getJSONArray("resolves").length() == 0) { "Repairs belong to new candidate revisions" }
        val event = revision.getJSONObject("body").getJSONObject(EVENT)
        val operation = text(event, "operation")
        require(operation in setOf("compare", "challenge", "review")) { "Unknown candidate event" }
        val targets = exactLinks(event.getJSONArray("targets"))
        require(if (operation == "compare") targets.size >= 2 else targets.size == 1) { "Invalid candidate event target count" }
        require(targets.map { it.getString("object_id") }.toSet().size == targets.size) { "Compare distinct candidates, not duplicate targets" }
        targets.forEach {
            require(it.getString("kind") == CANDIDATE && active(it)) { "Events address active candidate revisions" }
            unchangedCurrent(it)
        }
        val suppliedParents = revision.getJSONArray("parents")
        require(suppliedParents.length() == 0 || suppliedParents.length() == targets.size &&
            (0 until suppliedParents.length()).all { index -> targets.any { same(it, suppliedParents.getJSONObject(index)) } }) {
            "Event parents must match its exact targets"
        }
        val criterion = text(event, "criterion")
        require(targets.all { criterion in strings(it.getJSONObject("body").getJSONObject(CANDIDATE).getJSONArray("criteria")) }) {
            "The event must name an exact criterion shared by its targets"
        }
        text(event, "check")
        text(event, "rationale")
        val outcome = text(event, "outcome")
        require(outcome in if (operation == "compare") setOf("differentiated", "inconclusive") else setOf("supported", "refuted", "not_tested")) {
            "Invalid candidate assessment outcome; comparisons are not votes or truth certificates"
        }
        observations(revision, review = operation == "review")
        if (operation == "challenge") {
            require(outcome != "supported") { "A challenge must preserve a refutation or an untested weakness" }
            text(event, "correction")
        }
        if (operation == "review") {
            require(access.personId !in strings(targets.single().getJSONObject("host_candidate").getJSONArray("contributors"))) {
                "A candidate contributor or ancestor author cannot independently review it"
            }
            val unresolved = strings(event.getJSONArray("unresolved"))
            require(outcome != "supported" || unresolved.isEmpty()) { "Supported reviews cannot retain blockers" }
        }
        // The host retains only resolved identities here; body text is still a member assessment.
        revision.put("parents", JSONArray(targets.map(::reference)))
        revision.put("host_candidate_event", JSONObject().put("operation", operation)
            .put("targets", JSONArray(targets.map(::reference))).put("criterion", criterion)
            .put("trust", if (operation == "review") "independent_review_not_claim_verified" else "assessment_not_claim_verified"))
    }

    private fun exactLinks(links: JSONArray): List<JSONObject> {
        val seen = hashSetOf<String>()
        return (0 until links.length()).map { index ->
            val ref = links.getJSONObject(index)
            val id = text(ref, "object_id")
            val hash = text(ref, "sha256")
            val version = integer(ref, "revision")
            require(id.matches(HASH) && hash.matches(HASH) && version != null && version > 0 && seen.add("$id:$version")) {
                "Copy unique exact object_id, integer revision and sha256 references"
            }
            val saved = requireNotNull(read(id, version)) { "Candidate reference is missing or isolated" }
            require(saved.getString("sha256") == hash) { "Candidate reference digest mismatch" }
            saved
        }
    }

    private fun unchangedCurrent(target: JSONObject) {
        require(target.getString("object_id") !in changingIds && current(target.getString("object_id"), target.getInt("revision"))) {
            "Candidate target is stale or changes in this publication; re-read it in new work"
        }
    }

    private fun observations(revision: JSONObject, review: Boolean) {
        val refs = revision.getJSONArray("host_observations")
        require(refs.length() > 0) { "Candidate evolution and assessments require exact host observations" }
        repeat(refs.length()) {
            val ref = refs.getJSONObject(it)
            require(ref.optString("observation_kind") == "tool_output_recorded" &&
                ref.optString("status") in if (review) setOf("returned") else setOf("returned", "failed")) {
                "Member assessments are not observed evidence; independent reviews require returned tool originals"
            }
        }
    }

    companion object {
        const val CANDIDATE = "candidate"
        const val EVENT = "candidate_event"
        private val HASH = Regex("[a-f0-9]{64}")
        fun active(revision: JSONObject) = revision.optJSONObject("host_candidate")?.optString("status") == "active"
        fun same(a: JSONObject, b: JSONObject) = listOf("object_id", "revision", "sha256").all { a.opt(it) == b.opt(it) }
        fun reference(revision: JSONObject) = JSONObject().apply {
            listOf("object_id", "revision", "sha256").forEach { put(it, revision.get(it)) }
        }
        private fun text(value: JSONObject, key: String): String =
            requireNotNull(value.opt(key) as? String) { "$key must be a string" }.also { require(it.isNotBlank()) { "$key must not be blank" } }
        private fun integer(value: JSONObject, key: String): Int? = when (val number = value.opt(key)) {
            is Int -> number
            is Long -> number.takeIf { it in 0..Int.MAX_VALUE.toLong() }?.toInt()
            else -> null
        }
        private fun strings(values: JSONArray): List<String> = (0 until values.length()).map {
            requireNotNull(values.opt(it) as? String) { "Expected a string array" }.also { value -> require(value.isNotBlank()) }
        }.also { require(it.distinct().size == it.size) { "Duplicate criteria or issues are not meaningful" } }
    }
}
