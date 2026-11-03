package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Preserves what peers challenged and what a combination actually changes, without certifying prose. */
internal object CollaborationTeamInvention {
    const val EXCHANGE = "team_exchange"
    const val SYNTHESIS = "team_synthesis"
    const val EVALUATION = "team_evaluation"
    val KINDS = setOf(EXCHANGE, SYNTHESIS, EVALUATION)

    fun authors(record: JSONObject): Set<String> = buildSet {
        add(record.getString("person_id"))
        record.optJSONObject(HOST)?.optJSONArray("contributors")?.let { a -> repeat(a.length()) { add(a.getString(it)) } }
    }

    fun exchange(value: JSONObject, revision: JSONObject, person: String,
                 exact: (JSONObject, Set<String>) -> JSONObject, coverage: (JSONObject) -> Unit): JSONObject {
        val idea = exact(value.getJSONObject("innovation"), setOf(IDEA))
        CollaborationInnovationValidation.currentIdea(idea, exact)
        val operation = text(value, "operation")
        require(operation in setOf("challenge", "response")) { "team_exchange.operation must be challenge or response" }
        listOf("issue", "reasoning", "discriminating_test", "uncertainty").forEach { text(value, it) }
        val host = JSONObject().put("state", "peer_argument_not_verified").put("innovation", ref(idea))
            .put("operation", operation).put("contributors", JSONArray(listOf(person)))
        if (operation == "challenge") {
            require(person !in authors(idea)) { "A peer challenge must come from outside the idea's contributors" }
            text(value, "suggested_change")
            require(!value.has("challenge")) { "A challenge cannot masquerade as a response" }
        } else {
            val challenge = exact(value.getJSONObject("challenge"), setOf(EXCHANGE))
            val prior = challenge.getJSONObject(HOST)
            require(prior.getString("operation") == "challenge" && same(idea, prior.getJSONObject("innovation"))) {
                "Respond to a challenge on this exact innovation version"
            }
            require(person in authors(idea) && person != challenge.getString("person_id")) { "An idea contributor must answer the independent challenge" }
            require(text(value, "decision") in setOf("adopt", "adapt", "reject", "test_needed")) { "Unknown response decision" }
            text(value, "change_or_reason"); text(value, "remaining_question")
            host.put("challenge", ref(challenge))
        }
        if (revision.getJSONArray("host_observations").length() > 0) coverage(revision)
        return host
    }

    fun synthesis(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val opportunity = CollaborationInnovationValidation.currentOpportunity(value.getJSONObject("opportunity"), exact)
        listOf("mechanism", "interaction_hypothesis", "why_not_concatenation", "discriminating_test", "limitations").forEach { text(value, it) }
        val parts = objects(value, "contributions")
        val ids = hashSetOf<String>()
        val people = sortedSetOf<String>()
        val primaryAuthors = hashSetOf<String>()
        val basis = JSONArray()
        parts.forEach { part ->
            listOf("retained", "changed", "response_effect").forEach { text(part, it) }
            val idea = exact(part.getJSONObject("innovation"), setOf(IDEA))
            CollaborationInnovationValidation.currentIdea(idea, exact)
            require(ids.add(idea.getString("object_id"))) { "Count each source idea once" }
            require(same(opportunity, idea.getJSONObject(HOST).getJSONObject(CollaborationInnovationValidation.OPPORTUNITY))) {
                "Team contributions must serve the same exact goal opportunity"
            }
            val challenge = exact(part.getJSONObject("challenge"), setOf(EXCHANGE))
            val response = exact(part.getJSONObject("response"), setOf(EXCHANGE))
            require(challenge.getJSONObject(HOST).getString("operation") == "challenge" &&
                same(idea, challenge.getJSONObject(HOST).getJSONObject("innovation")) &&
                response.getJSONObject(HOST).getString("operation") == "response" &&
                same(challenge, response.getJSONObject(HOST).getJSONObject("challenge"))) {
                "Each contribution needs its preserved challenge and matching contributor response"
            }
            primaryAuthors += idea.getString("person_id")
            listOf(idea, challenge, response).forEach { people += authors(it); basis.put(ref(it)) }
        }
        require(ids.size >= 2 && primaryAuthors.size >= 2) { "Team synthesis needs distinct ideas from at least two members, not one author's duplicate variants" }
        return JSONObject().put("state", "combined_hypothesis_not_verified").put("contributors", JSONArray(people.toList()))
            .put("basis", basis).put(CollaborationInnovationValidation.OPPORTUNITY, ref(opportunity))
            .put("cognitive_independence_verified", false)
    }

    fun idea(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        if (!value.has(SYNTHESIS)) return null
        val synthesis = exact(value.getJSONObject(SYNTHESIS), setOf(SYNTHESIS))
        CollaborationInnovationValidation.checkRecord(synthesis, exact)
        require(value.getString("origin") == "combination" && same(value.getJSONObject(CollaborationInnovationValidation.OPPORTUNITY),
            synthesis.getJSONObject(HOST).getJSONObject(CollaborationInnovationValidation.OPPORTUNITY))) { "Team idea must preserve its combination opportunity" }
        val parents = objects(revision, "parents")
        val sources = objects(synthesis.getJSONObject("body").getJSONObject(SYNTHESIS), "contributions").map { it.getJSONObject("innovation") }
        require((sources + ref(synthesis)).all { source -> parents.any { same(source, it) } }) { "Preserve synthesis and every source idea in parents" }
        return ref(synthesis)
    }

    fun work(spec: JSONObject, idea: JSONObject?, opportunity: JSONObject, member: String,
             exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val phase = spec.getString("phase")
        val result = JSONObject()
        spec.optJSONObject("exchange")?.let { source ->
            val exchange = exact(source, setOf(EXCHANGE))
            CollaborationInnovationValidation.checkRecord(exchange, exact)
            require(idea != null && same(idea, exchange.getJSONObject(HOST).getJSONObject("innovation"))) { "Peer task and exchange target differ" }
            result.put("exchange", ref(exchange))
        }
        if (phase == "challenge") require(idea != null && member !in authors(idea)) { "Assign challenge to a non-contributor" }
        if (phase == "respond") {
            val exchange = exact(result.getJSONObject("exchange"), setOf(EXCHANGE))
            require(idea != null && member in authors(idea) && exchange.getJSONObject(HOST).getString("operation") == "challenge") {
                "Assign response to an idea contributor with the exact independent challenge"
            }
        }
        spec.optJSONObject(SYNTHESIS)?.let { source ->
            val synthesis = exact(source, setOf(SYNTHESIS))
            CollaborationInnovationValidation.checkRecord(synthesis, exact)
            require(same(opportunity, synthesis.getJSONObject(HOST).getJSONObject(CollaborationInnovationValidation.OPPORTUNITY))) { "Synthesis task has another opportunity" }
            if (idea != null) require(same(synthesis, idea.getJSONObject(HOST).getJSONObject(SYNTHESIS))) { "Synthesis does not belong to this combination" }
            result.put(SYNTHESIS, ref(synthesis))
        }
        if (phase == "combine") require(result.has(SYNTHESIS)) { "Combination work needs a preserved synthesis with answered peer challenges" }
        spec.optJSONObject(EVALUATION)?.let { source ->
            val evaluation = exact(source, setOf(EVALUATION))
            CollaborationInnovationValidation.checkRecord(evaluation, exact)
            require(idea != null && same(idea, evaluation.getJSONObject(HOST).getJSONObject("innovation"))) { "Team evaluation task targets another idea" }
            result.put(EVALUATION, ref(evaluation))
        }
        return result
    }

    fun retention(value: JSONObject, idea: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        if (!idea.getJSONObject(HOST).has(SYNTHESIS)) return null
        val evaluation = exact(value.getJSONObject(EVALUATION), setOf(EVALUATION))
        CollaborationInnovationValidation.checkRecord(evaluation, exact)
        require(evaluation.getJSONObject(HOST).getString("state") == "eligible_for_scoped_team_reuse" &&
            same(idea, evaluation.getJSONObject(HOST).getJSONObject("innovation"))) { "Team method requires its current independent comparative evaluation" }
        return ref(evaluation)
    }

    private fun ref(record: JSONObject) = CollaborationResearchCandidates.reference(record)
    private fun same(a: JSONObject, b: JSONObject) = CollaborationResearchCandidates.same(a, b)
}
