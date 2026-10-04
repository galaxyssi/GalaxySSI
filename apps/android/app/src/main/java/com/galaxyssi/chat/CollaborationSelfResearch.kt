package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.GAP
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.RESULT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.strings
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** A research checkpoint joins existing evidence contracts; it grants neither execution nor deployment. */
internal object CollaborationSelfResearch {
    const val CYCLE = "self_research_cycle"
    const val REVIEW = "self_research_review"

    fun cycle(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
              historical: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        listOf("question", "component", "scope", "success_test", "new_information", "goal_tradeoff").forEach { text(value, it) }
        val diagnosis = exact(value.getJSONObject("diagnosis"), setOf(CollaborationCapabilityDiagnosis.DIAGNOSIS))
        val gap = exact(diagnosis.getJSONObject(HOST).getJSONObject("gap"), setOf(GAP))
        val agenda = exact(value.getJSONObject("agenda"), setOf(CollaborationLearningAgenda.KIND))
        val choice = objects(agenda.getJSONObject("body").getJSONObject(CollaborationLearningAgenda.KIND), "options")
            .singleOrNull { it.getString("id") == text(value, "option_id") }
        require(choice != null && choice.getString("decision") == "select" &&
            CollaborationResearchCandidates.same(gap, choice.getJSONObject("gap"))) { "Self research needs a selected learning option for the diagnosed gap" }
        val opportunity = CollaborationInnovationValidation.currentOpportunity(value.getJSONObject("opportunity"), exact)
        val basis = opportunity.getJSONObject(HOST).getJSONArray("basis")
        require((0 until basis.length()).any { CollaborationResearchCandidates.same(gap, basis.getJSONObject(it)) ||
            CollaborationResearchCandidates.same(diagnosis, basis.getJSONObject(it)) }) { "Research opportunity must cite the diagnosed bottleneck" }
        val host = JSONObject().put("state", "registered_not_executed").put("diagnosis", reference(diagnosis)).put("gap", reference(gap))
            .put("agenda", reference(agenda)).put("option_id", choice.getString("id")).put("opportunity", reference(opportunity))
            .put("goal_sha256", opportunity.getJSONObject(HOST).getString("goal_sha256"))
            .put("grants_permissions", false).put("improvement_verified", false)
        value.optJSONObject("previous_review")?.let { ref ->
            val previous = historical(ref, setOf(REVIEW))
            require(previous.getJSONObject(HOST).getString("goal_sha256") == host.getString("goal_sha256")) {
                "Continue the same authorized goal; cross-goal transfer needs a separately scoped study"
            }
            host.put("previous_review", reference(previous)).put("previous_decision", previous.getJSONObject(HOST).getString("decision"))
        }
        return host
    }

    fun idea(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val ref = value.optJSONObject(CYCLE) ?: return null
        val cycle = exact(ref, setOf(CYCLE))
        require(CollaborationResearchCandidates.same(cycle.getJSONObject(HOST).getJSONObject("opportunity"),
            value.getJSONObject(CollaborationInnovationValidation.OPPORTUNITY))) { "Self-research innovation belongs to another opportunity" }
        return reference(cycle)
    }

    fun review(value: JSONObject, revision: JSONObject, person: String,
               exact: (JSONObject, Set<String>) -> JSONObject, historical: (JSONObject, Set<String>) -> JSONObject,
               coverage: (JSONObject) -> Unit): JSONObject {
        val cycle = historical(value.getJSONObject("cycle"), setOf(CYCLE))
        val decision = text(value, "decision")
        require(decision in setOf("adopt", "reject", "revise", "wait")) { "Research decision must be adopt, reject, revise or wait" }
        listOf("reason", "limitations", "next_question", "information_gained").forEach { text(value, it) }
        strings(value, "alternatives")
        require(person != cycle.getString("person_id")) { "Research review requires a different member from the cycle proposer" }
        val evaluations = value.getJSONArray("evaluations")
        require(evaluations.length() > 0 || decision in setOf("wait", "revise")) { "Adopt/reject requires actual experiment results" }
        val seen = hashSetOf<String>()
        val retained = linkedMapOf<String, JSONObject>()
        val refs = revision.getJSONArray("host_observations")
        val measured = JSONArray()
        repeat(evaluations.length()) { index ->
            val evaluation = evaluations.getJSONObject(index)
            val lesson = historical(evaluation.getJSONObject("lesson"), setOf(LESSON))
            val result = historical(evaluation.getJSONObject("result"), setOf(RESULT))
            require(seen.add(result.getString("sha256")) && CollaborationResearchCandidates.same(result,
                lesson.getJSONObject(HOST).getJSONObject("result"))) { "Each research result needs its exact learning decision, without duplicates" }
            val plan = historical(result.getJSONObject(HOST).getJSONObject("plan"), setOf(PLAN))
            val idea = historical(plan.getJSONObject("body").getJSONObject(PLAN).getJSONObject("innovation"), setOf(IDEA))
            require(CollaborationResearchCandidates.same(cycle, idea.getJSONObject(HOST).getJSONObject(CYCLE))) {
                "Review cannot borrow an experiment from another research cycle"
            }
            val contributors = idea.getJSONObject(HOST).getJSONArray("contributors")
            val trialAuthors = result.getJSONObject(HOST).getJSONArray("trial_authors")
            require(person !in listOf(idea.getString("person_id"), plan.getString("person_id")) &&
                (0 until contributors.length()).none { contributors.getString(it) == person } &&
                (0 until trialAuthors.length()).none { trialAuthors.getString(it) == person }) {
                "Research review must be independent of candidate, plan and trial authors"
            }
            val originals = result.getJSONArray("host_observations")
            require((0 until originals.length()).all { i -> (0 until refs.length()).any { j ->
                originals.getJSONObject(i).let { r -> refs.getJSONObject(j).let { cited ->
                    r.getString("evidence_id") == cited.getString("evidence_id") && r.getString("sha256") == cited.getString("sha256") } }
            } }) { "Research review must cite every original trial observation" }
            val state = lesson.getJSONObject(HOST).getString("state")
            if (state == "eligible_for_scoped_reuse") retained[lesson.getString("sha256")] = lesson
            if (decision == "reject") require(state == "reject") { "Reject requires rejected learning decisions for every reported candidate" }
            if (decision == "adopt") require(state in setOf("eligible_for_scoped_reuse", "reject")) { "Resolve incomplete candidates before adoption" }
            measured.put(JSONObject().put("result", reference(result)).put("lesson", reference(lesson)).put("state", state))
        }
        if (refs.length() > 0) coverage(revision)
        val channels = value.getJSONArray("channels")
        val selections = JSONArray()
        if (decision == "adopt") {
            require(retained.isNotEmpty() && channels.length() > 0) { "Adoption needs retained measured results and a protected capability selection" }
            val used = hashSetOf<String>()
            repeat(channels.length()) { i ->
                val channel = exact(channels.getJSONObject(i), setOf(CollaborationCapabilityChannel.KIND))
                val host = channel.getJSONObject(HOST)
                val lesson = requireNotNull(retained[host.getJSONObject("lesson").getString("sha256")]) {
                    "Selected capability must originate from this cycle's retained result"
                }
                require(used.add(lesson.getString("sha256"))) { "List each retained candidate once" }
                require(!host.optBoolean("newer_capabilities_require_revalidation")) { "A rollback awaiting regression checks is not an adopted improvement" }
                CollaborationInnovationValidation.checkRecord(exact(reference(lesson), setOf(LESSON)), exact)
                selections.put(reference(channel))
            }
            require(used == retained.keys) { "Every retained candidate needs an explicit protected selection" }
        } else require(channels.length() == 0) { "Non-adoption research must not claim capability selection" }
        if (decision == "wait") {
            require(refs.length() > 0) { "Waiting needs original evidence of the blocker, not only a proposed explanation" }
            val blocker = value.getJSONObject("blocker")
            listOf("reason", "resume_when", "checked_alternatives").forEach { text(blocker, it) }
        }
        return JSONObject().put("state", "reviewed_$decision").put("decision", decision).put("cycle", reference(cycle))
            .put("goal_sha256", cycle.getJSONObject(HOST).getString("goal_sha256")).put("evaluations", measured)
            .put("channels", selections).put("improvement_verified", decision == "adopt").put("scope", "registered measurements only")
            .put("goal_verified", false).put("grants_permissions", false)
    }

    private fun reference(record: JSONObject) = CollaborationResearchCandidates.reference(record)
}
