package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic records only: no model, network, phone actions or original research task. */
@RunWith(AndroidJUnit4::class)
class CollaborationTeamInventionDeviceTest {
    @Test fun peerExchangesSynthesisAndBoundWorkReopenWithOriginalIdentities() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "team-invention-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val people = listOf("lead", "alpha", "beta", "critic")
        groups.update(group) { it.copy(members = people.map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "lead") }
        try {
            val workspace = CollaborationResearchWorkspace(context)
            val goal = "Combine local normalization and deduplication"
            fun access(person: String, round: Long, node: String = person) = CollaborationWorkspaceAccess(group, "run", "turn", round, node, person)
            fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long, parents: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic peer fixture")
                    .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
                        .put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Synthetic local material").put(kind, value))
                        .put("parents", parents))).toString()
                val receipt = workspace.publish(access(person, round, id), raw, round * 10)
                assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
                return receipt.getJSONArray("revisions").getJSONObject(0)
            }
            val baseline = publish("control", "artifact", JSONObject(), "lead", 1)
            val opportunity = publish("opportunity", "innovation_opportunity", JSONObject()
                .put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"))
                .put("criterion_id", "quality").put("requirement", goal).put("question", "Can the methods work together?")
                .put("unmet_need", "Duplicate mixed case inputs").put("expected_benefit", "Correct canonical tokens")
                .put("constraints", "Local fixture only").put("null_hypothesis", "No interaction benefit")
                .put("discriminating_test", "Compare individual methods").put("uncertainty", "Not a real model finding")
                .put("alternative_routes", JSONArray().put("Keep original method")).put("drivers", JSONArray().put(JSONObject()
                    .put("id", "input").put("kind", "limitation").put("sources", JSONArray().put(baseline))
                    .put("why", "Repeated representations").put("what_would_change", "Other data"))), "lead", 2)
            val ideaSpec = JSONObject("""{"origin":"limitation","hypothesis":"Canonical tokens improve lookup","mechanism":"Normalize tokens",
                "difference":"Changes input representation","prior_art":"Not searched","novelty_scope":"not_checked","falsifier":"No improvement",
                "domain":"local-fixture","applies_when":"Same corpus","risks":"Lost distinctions","alternatives":["Keep originals"],
                "predictions":[{"id":"p1","statement":"Improved lookup","test":"Compare outputs"}]}""").put("innovation_opportunity", opportunity)
            val a = publish("normalize", "innovation", ideaSpec, "alpha", 3, JSONArray().put(opportunity))
            val b = publish("deduplicate", "innovation", JSONObject(ideaSpec.toString()).put("mechanism", "Deduplicate tokens"), "beta", 3, JSONArray().put(opportunity))
            val contributions = JSONArray()
            var betaChallenge: JSONObject? = null
            for ((id, idea) in listOf("alpha" to a, "beta" to b)) {
                val challengeSpec = JSONObject().put("operation", "challenge").put("innovation", idea).put("issue", "Mixed case duplicates")
                    .put("reasoning", "One mechanism misses the other edge case").put("discriminating_test", "A a B b")
                    .put("uncertainty", "Local only").put("suggested_change", "Compose methods")
                val challenge = publish("challenge-$id", "team_exchange", challengeSpec, "critic", 4)
                if (id == "beta") betaChallenge = challenge
                val response = publish("response-$id", "team_exchange", JSONObject(challengeSpec.toString()).put("operation", "response")
                    .put("challenge", challenge).put("decision", "test_needed").put("change_or_reason", "Compare composition")
                    .put("remaining_question", "Benefit not measured yet"), id, 5)
                contributions.put(JSONObject().put("innovation", idea).put("challenge", challenge).put("response", response)
                    .put("retained", "Useful component").put("changed", "Compose in order").put("response_effect", "Added a discriminating comparison"))
            }
            val synthesis = publish("synthesis", "team_synthesis", JSONObject().put("opportunity", opportunity)
                .put("mechanism", "Normalize then deduplicate").put("interaction_hypothesis", "Equalized tokens deduplicate")
                .put("why_not_concatenation", "Output of one transforms input of another").put("discriminating_test", "Compare both parents")
                .put("limitations", "Needs actual measurements").put("contributions", contributions), "lead", 6)
            val combined = publish("combined", "innovation", JSONObject(ideaSpec.toString()).put("origin", "combination")
                .put("transfer_conditions", "Same corpus").put("team_synthesis", synthesis), "lead", 7,
                JSONArray().put(a).put(b).put(synthesis).put(opportunity))
            val criteria = JSONArray().put(JSONObject().put("id", "quality").put("requirement", goal).put("status", "open").put("evidence", JSONArray()))
            val members = CollaborationGoalLoop.initial(people.map { AgentTeamMember("fixture",
                if (it == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE, instanceId = it) }, goal)
            val record = AgentTeamExecutionRecord(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest(group, "turn", "fixture", runId = "run", goal = goal, context = mapOf(CollaborationGoalLoop.ROUND to "10", CollaborationGoalLoop.CRITERIA to criteria.toString())))
            val work = JSONObject().put("id", "respond-beta").put("member", "beta").put("stage", "REVISE").put("assignment", "Address the preserved peer question")
                .put("innovation_work", JSONObject().put("opportunity", opportunity).put("innovation", b).put("exchange", betaChallenge)
                    .put("phase", "respond").put("expected_output", "A scoped answer").put("why_now", "Resolve a mechanism uncertainty"))
            val admitted = CollaborationInnovationWork.plan(record, listOf(work), { workspace }, access("lead", 10))
            val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationInnovationWork.CLAIMS to admitted.claims)))
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(admitted.claims, CollaborationInnovationWork.plan(restored, listOf(work), { reopened }, access("lead", 10)).claims)
            val binding = JSONObject(CollaborationInnovationWork.context(admitted.work.single()).getValue(CollaborationInnovationWork.TASK))
            assertEquals(betaChallenge!!.getString("sha256"), binding.getJSONObject("work").getJSONObject("exchange").getString("sha256"))
            assertFalse(binding.getBoolean("grants_permissions"))
            val saved = reopened.read(access("lead", 0).copy(runId = "future", turnId = "future"), combined.getString("object_id"), 1)!!
            assertEquals("hypothesis_unverified", saved.getJSONObject("host_evolution").getString("state"))
            assertTrue(saved.getJSONObject("host_evolution").getJSONArray("contributors").toString().contains("critic"))
        } finally { groups.remove(group) }
    }
}
