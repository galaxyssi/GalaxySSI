package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

/** Synthetic evidence only. All publications, review gates and work admission use production contracts. */
internal class CollaborationSelfResearchFixture(val f: CollaborationRetentionFixture) {
    val goal = "Improve local fixture"
    val criteria = JSONArray().put(JSONObject().put("id", "quality").put("requirement", goal)
        .put("verification", "documentary").put("status", "open").put("evidence", JSONArray()))
    val gap = f.accepted(f.publish("capability_gap", JSONObject("""{"category":"method","symptom":"Repeated parsing",
        "needed_capability":"Reuse immutable input","chosen_option":"reuse","rationale":"Test duplication",
        "learning_options":[{"id":"reuse","action":"Compare immutable reuse","expected_gain":"Less work","cost":"Unknown",
        "goal_relevance":"Same output faster","verification":"Paired experiment"}]}""")))
    val symptoms = JSONArray().put(f.ledger.record(f.access("executor"), "symptom", "fixture.diagnose", "{}", "{\"parses\":8}",
        ++f.sequence * 10, f.sequence * 10 + 1, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
    val diagnosis = f.accepted(f.publish(CollaborationCapabilityDiagnosis.DIAGNOSIS, JSONObject("""{
        "selected_option":"reuse","uncertainty":"Synthetic only","action":"Compare caching","authorization_boundary":"Local fixture",
        "hypotheses":[{"id":"h","category":"method","explanation":"Duplicate parse","discriminating_test":"Count parses","would_refute":"No duplication"}],
        "selected_hypothesis":"h","expected_observations":[{"id":"parse-count","source":{"origin":"android_native_tool","tool":"fixture.diagnose"},
        "pointer":"/parses","expected":4,"meaning":"Less duplication"}]}""").put("gap", f.ref(gap)), "curator", symptoms))
    val agenda = f.accepted(f.publish(CollaborationLearningAgenda.KIND, JSONObject("""{
        "goal_alignment":"Improve local fixture","resource_reasoning":"Local only","selection_reason":"Observable bottleneck","reconsider_when":"New evidence",
        "options":[{"id":"study","gap_option":"reuse","priority":1,"decision":"select","member":"peer","stage":"EXECUTE",
        "assignment":"Compare local parsing","current_goal_value":"Less work","future_transfer_value":"Possible reuse","information_gain":"Test mechanism",
        "uncertainty":"Synthetic only","tradeoff":"Compute cost","verification":"Paired data","reconsider_when":"Regression",
        "resource_estimates":[{"unit":"tool_calls","status":"unknown","basis":"Not measured"}]}]}""").apply {
        getJSONArray("options").getJSONObject(0).put("gap", f.ref(gap))
    }))
    val opportunity = f.accepted(f.publish(CollaborationInnovationValidation.OPPORTUNITY, JSONObject()
        .put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256")).put("criterion_id", "quality")
        .put("requirement", goal).put("question", "Can reuse improve parsing?").put("unmet_need", "Duplicate work")
        .put("expected_benefit", "Lower operation count").put("constraints", "Same input").put("null_hypothesis", "No gain")
        .put("discriminating_test", "Paired counts").put("uncertainty", "Synthetic only").put("alternative_routes", JSONArray().put("Batching"))
        .put("drivers", JSONArray().put(JSONObject().put("id", "gap").put("kind", "knowledge_gap").put("why", "Measured duplication")
            .put("what_would_change", "Different input").put("sources", JSONArray().put(f.ref(diagnosis)))))))
    fun cycleSpec(previous: JSONObject? = null) = JSONObject().put("diagnosis", f.ref(diagnosis)).put("agenda", f.ref(agenda))
        .put("option_id", "study").put("opportunity", f.ref(opportunity)).put("question", "How to avoid reparsing?")
        .put("component", "retrieval").put("scope", "Local fixture").put("success_test", "Gain with no regression")
        .put("new_information", "New controlled data and prior decision").put("goal_tradeoff", "No external calls")
        .apply { previous?.let { put("previous_review", f.ref(it)) } }
    val cycle = f.accepted(f.publish(CollaborationSelfResearch.CYCLE, cycleSpec()))
    fun next(previous: JSONObject) = f.accepted(f.publish(CollaborationSelfResearch.CYCLE, cycleSpec(previous)))
    fun study(cycle: JSONObject = this.cycle, editReport: (JSONObject) -> Unit = {}) = f.study(editPlan = { plan ->
        plan.getJSONArray("cases").getJSONObject(1).put("dimension", "value")
        plan.getJSONArray("cases").put(f.case("possible", "feasibility").put("threshold", 10))
    }, editReport = editReport, createIdea = { method ->
        val value = JSONObject(f.baseline.getJSONObject("body").getJSONObject("innovation").toString())
            .put(CollaborationWorkflowMethod.KIND, f.ref(method)).put(CollaborationSelfResearch.CYCLE, f.ref(cycle))
            .put(CollaborationInnovationValidation.OPPORTUNITY, f.ref(opportunity))
        f.accepted(f.publish("innovation", value, "author", parents = JSONArray().put(f.ref(opportunity))))
    })
    fun retain(study: CollaborationRetentionFixture.Study): CollaborationRetentionFixture.Retained {
        val prior = f.ledger.record(f.access("searcher"), "prior-${f.sequence}", "fixture.prior", "{}", "{\"method\":\"Repeated parsing\"}",
            ++f.sequence * 10, f.sequence * 10 + 1, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        val refs = JSONArray(study.observations.toString()).put(prior)
        val assessment = f.accepted(f.publish(CollaborationInnovationValidation.ASSESSMENT, JSONObject()
            .put("innovation", f.ref(study.idea)).put("decision", "retain").put("rationale", "Paired original observations")
            .put("novelty", JSONObject().put("outcome", "distinguished_in_searched_scope").put("search_scope", "Synthetic fixture")
                .put("coverage_gaps", "Real world").put("rationale", "Different mechanism").put("closest_work", JSONArray().put(JSONObject()
                    .put("observation", prior).put("overlap", "Parsing").put("difference", "Immutable reuse").put("significance", "Less work"))))
            .put("results", JSONArray().put(f.ref(study.result))).put("feasibility_scope", "Local input").put("value_scope", "Operation count")
            .put("limitations", "No model evaluation").put("unresolved", JSONArray()).put("next_action", "Realistic data later"), "reviewer", refs))
        return f.retain(study, assessment)
    }
    fun reviewSpec(cycle: JSONObject = this.cycle, decision: String = "revise") = JSONObject().put("cycle", f.ref(cycle))
        .put("decision", decision).put("reason", "Check original evidence").put("limitations", "Synthetic only")
        .put("next_question", "Does this transfer?").put("information_gained", "Observed local behavior")
        .put("alternatives", JSONArray().put("Batching")).put("evaluations", JSONArray()).put("channels", JSONArray())
    fun review(value: JSONObject, refs: JSONArray = JSONArray(), person: String = "reviewer") =
        f.publish(CollaborationSelfResearch.REVIEW, value, person, refs)
    fun adoption(retained: CollaborationRetentionFixture.Retained, channel: JSONObject) = reviewSpec(decision = "adopt")
        .put("evaluations", JSONArray().put(JSONObject().put("result", f.ref(retained.study.result)).put("lesson", f.ref(retained.lesson))))
        .put("channels", JSONArray().put(f.ref(channel)))
    fun work(cycle: JSONObject = this.cycle, id: String = "research") = JSONObject().put("id", id).put("member", "peer")
        .put("stage", "EXECUTE").put("assignment", "Explore local parsing evidence").put("innovation_work", JSONObject()
            .put("opportunity", f.ref(opportunity)).put("phase", "explore").put("expected_output", "Registered alternatives").put("why_now", "Observed gap"))
        .put(CollaborationSelfResearchWork.FIELD, JSONObject().put("cycle", f.ref(cycle)).put("action_id", "explore").put("why_now", "New evidence"))
    fun record(): AgentTeamExecutionRecord = f.record().let { record -> record.copy(
        definition = record.definition.copy(members = record.definition.members.map { it.copy(context = it.context +
            mapOf("collaboration_group_id" to f.group, CollaborationLiveGraph.ENABLED to "1")) }),
        request = record.request.copy(context = record.request.context + mapOf(CollaborationGoalLoop.CRITERIA to criteria.toString(), CollaborationGoalLoop.ROUND to "1000"))) }
    fun report(work: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Research local improvement")
        .put("decision", "continue").put("criteria", criteria).put("work", JSONArray(work)).put("blockers", JSONArray()).toString()
    fun completed(record: AgentTeamExecutionRecord, child: String, output: String, terminal: Boolean = false): AgentTeamExecutionRecord {
        val seq = record.events.size + 1L
        return record.copy(events = record.events + AgentSubagentEvent(seq, record.request.runId, child, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(record.request.runId, child, record.request.runId, 1,
                AgentSubagentStatus.SUCCEEDED, output, startedAtMillis = 100, completedAtMillis = 300)) + if (terminal) listOf(AgentSubagentEvent(
            seq + 1, record.request.runId, kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)) else emptyList())
    }
}
