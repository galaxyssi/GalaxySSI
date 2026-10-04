package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

/** Shared JVM/device fixture. Publishes through real contracts; never calls a provider or native tool. */
internal class CollaborationRetentionFixture(val workspace: CollaborationResearchWorkspace, val ledger: CollaborationEvidenceLedger,
                                           val group: String = "retention-fixture") {
    var sequence = 0L
    fun access(person: String = "curator", node: String = person) =
        CollaborationWorkspaceAccess(group, "fixture-run", "fixture-turn", sequence + 1, node, person)
    fun raw(id: String, kind: String, value: JSONObject, refs: JSONArray = JSONArray(), previous: JSONObject? = null, parents: JSONArray = JSONArray()) = JSONObject()
        .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic retention test")
        .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
            .put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Local fixture only").put(kind, value))
            .put("observations", refs).put("parents", parents).apply { previous?.let { put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) } }))
    fun publish(kind: String, value: JSONObject, person: String = "curator", refs: JSONArray = JSONArray(), previous: JSONObject? = null, parents: JSONArray = JSONArray()): JSONObject {
        val id = "fixture-${++sequence}"
        val a = access(person, id).copy(round = sequence)
        repeat(refs.length()) { i -> val ref = refs.getJSONObject(i); var offset: Int? = 0
            while (offset != null) offset = requireNotNull(ledger.readPage(a, ref.getString("evidence_id"), ref.getString("sha256"), offset)).next
        }
        return workspace.publish(a, raw(id, kind, value, refs, previous, parents).toString(), sequence * 10)
    }
    fun accepted(receipt: JSONObject): JSONObject {
        check(receipt.optString("status") == "recorded") { receipt.toString() }
        val ref = receipt.getJSONArray("revisions").getJSONObject(0)
        return requireNotNull(workspace.read(access(), ref.getString("object_id"), ref.getInt("revision")))
    }
    fun ref(record: JSONObject) = CollaborationResearchCandidates.reference(record)
    val dataset = accepted(publish("artifact", JSONObject().put("values", JSONArray("[2,3,5,7]"))))
    fun method(label: String) = accepted(publish(CollaborationWorkflowMethod.KIND, JSONObject()
        .put("purpose", "Parse local data $label").put("domain", "fixture").put("bottleneck", "Repeated parsing")
        .put("change_rationale", "Share immutable parse").put("applies_when", "Same input").put("avoid_when", "Mutable input")
        .put("risks", "Stale index").put("expected_gain", "Less duplicate work").put("falsifier", "Wrong answers")
        .put("dimensions", JSONArray().put("retrieval")).put("roles", JSONArray().put("worker")).put("inputs", JSONArray().put("data"))
        .put("steps", JSONArray().put(JSONObject().put("id", "parse").put("role", "worker").put("stage", "EXECUTE")
            .put("assignment", "Parse local data $label").put("depends_on", JSONArray()))), "author"))
    fun idea(method: JSONObject) = accepted(publish("innovation", JSONObject().put("origin", "limitation")
        .put("hypothesis", "Less work at equal quality").put("mechanism", "Immutable cache").put("difference", "Reuse parsed values")
        .put("prior_art", "Fixture only").put("novelty_scope", "not_checked").put("falsifier", "Output mismatch")
        .put("domain", "fixture").put("applies_when", "Identical input").put("risks", "Mutation")
        .put("alternatives", JSONArray().put("Batching")).put("predictions", JSONArray().put(JSONObject().put("id", "p")
            .put("statement", "Measurable gain").put("test", "Paired comparison"))).put(CollaborationWorkflowMethod.KIND, ref(method)), "author"))
    val baselineMethod = method("baseline")
    val baseline = idea(baselineMethod)
    data class Study(val method: JSONObject, val idea: JSONObject, val plan: JSONObject, val result: JSONObject,
                     val observations: JSONArray, val previousSuite: JSONObject?)
    data class Retained(val study: Study, val lesson: JSONObject, val skill: JSONObject, val suite: JSONObject)
    fun case(id: String, purpose: String) = JSONObject().put("id", id).put("purpose", purpose).put("prediction", "Preserve measured behavior")
        .put("metric", "score").put("direction", "maximize").put("minimum_gain", 1).put("tolerance", 0).put("repetitions", 2).put("dataset", ref(dataset))
    fun spec(idea: JSONObject, previous: Retained?): JSONObject {
        val cases = previous?.suite?.getJSONObject(HOST)?.getJSONArray("anchors")?.let { anchors -> JSONArray().apply {
            repeat(anchors.length()) { i -> val anchor = anchors.getJSONObject(i); put(case(anchor.getString("id"), "regression")
                .put("tolerance", anchor.get("tolerance")).put("direction", anchor.getString("direction"))) }
        } } ?: JSONArray().put(case("legacy", "regression"))
        cases.put(case("gain-$sequence", "target"))
        return JSONObject().put("innovation", ref(idea)).put("baseline", ref(previous?.study?.idea ?: baseline)).put("prediction_id", "p")
            .put("method", "Controlled local fixture").put("environment", "retention-local-v1").put("budget_unit", "operations").put("budget_limit", 100)
            .put("source", JSONObject().put("origin", "android_native_tool").put("tool", "fixture.retention")).put("report_pointer", "").put("cases", cases)
            .put(CollaborationWorkflowMethod.COMPARISON, JSONObject().put("dataset", ref(dataset)).put("controlled_conditions", "Same input")
                .put("quality_oracle", "Exact expected values").put("cost_accounting", "Deterministic counts").put("selection_bias", "Synthetic only"))
            .apply { previous?.let { put(CollaborationCapabilityRetention.FIELD, ref(it.suite)) } }
    }
    fun study(previous: Retained? = null, editPlan: (JSONObject) -> Unit = {}, editReport: (JSONObject) -> Unit = {},
              createIdea: (JSONObject) -> JSONObject = { idea(it) }): Study {
        val method = method("candidate-$sequence"); val idea = createIdea(method)
        val spec = spec(idea, previous).apply(editPlan)
        val plan = accepted(publish("experiment_plan", spec, "planner"))
        val samples = JSONArray()
        CollaborationEvolutionContract.objects(spec, "cases").forEach { case -> repeat(case.getInt("repetitions")) { repetition ->
            for (variant in listOf("baseline", "candidate")) samples.put(JSONObject().put("case_id", case.getString("id"))
                .put("variant", variant).put("variant_sha256", (if (variant == "candidate") idea else previous?.study?.idea ?: baseline).getString("sha256"))
                .put("metric", case.getString("metric")).put("dataset_sha256", dataset.getString("sha256"))
                .put("workflow_sha256", (if (variant == "candidate") method else previous?.study?.method ?: baselineMethod).getString("sha256"))
                .put("repetition", repetition + 1).put("value", if (case.getString("purpose") == "target" && variant == "baseline") 8 else 10).put("budget_used", 1))
        } }
        val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
            .put("environment", spec.getString("environment")).put("budget_unit", spec.getString("budget_unit")).put("measurements", samples).apply(editReport)
        val time = ++sequence * 10
        val refs = JSONArray().put(ledger.record(access("executor").copy(round = sequence), "trial-$sequence", "fixture.retention", "{}", report.toString(),
            time, time + 1, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL))
        val result = accepted(publish("experiment_result", JSONObject().put("plan", ref(plan)).put("interpretation", "Synthetic comparison")
            .put("limitations", "Does not establish real model improvement"), "analyst", refs))
        return Study(method, idea, plan, result, refs, previous?.suite)
    }
    fun lesson(study: Study, assessment: JSONObject? = null, decision: String = "retain") = publish("capability_lesson", JSONObject().put("result", ref(study.result)).put("decision", decision)
        .put("rationale", "Original fixture measurements checked").put("applies_when", "Same authorized fixture")
        .put("avoid_when", "Other domains").put("procedure", "Reuse immutable parse and check answers")
        .put("transfer_test", "Independent new-scope comparison").put("rollback", study.plan.getJSONObject("body").getJSONObject("experiment_plan").getJSONObject("baseline"))
        .apply { assessment?.let { put(CollaborationInnovationValidation.ASSESSMENT, ref(it)) } },
        "reviewer", study.observations)
    fun retain(study: Study, assessment: JSONObject? = null): Retained {
        val lesson = accepted(lesson(study, assessment))
        val skill = accepted(publish(CollaborationProceduralMemory.SKILL, JSONObject().put("lesson", ref(lesson)).put("name", "Fixture reuse")
            .put("keywords", JSONArray().put("fixture")).put("limitations", "Fixture only").put("inputs", JSONArray())))
        val suite = accepted(publish(CollaborationCapabilityRetention.SUITE, JSONObject().put("lesson", ref(lesson))
            .put("scope", "Local fixture").put("limitations", "Not production coverage").apply { study.previousSuite?.let { put("previous_suite", ref(it)) } }))
        return Retained(study, lesson, skill, suite)
    }
    fun select(retained: Retained, previous: JSONObject? = null, workflow: Boolean = false) = publish(CollaborationCapabilityChannel.KIND,
        JSONObject().put("operation", if (previous == null) "initialize" else "promote").put("reason", "Scoped measured comparison")
            .put("implementation", ref(if (workflow) retained.study.method else retained.skill)).put("lesson", ref(retained.lesson)).put("suite", ref(retained.suite)), previous = previous)
    fun rollback(current: JSONObject, target: JSONObject) = publish(CollaborationCapabilityChannel.KIND,
        JSONObject().put("operation", "rollback").put("reason", "Observed production concern; preserve candidate for diagnosis")
            .put("target_revision", ref(target)), previous = current)
    fun record(): AgentTeamExecutionRecord {
        val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
            AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), "Improve local fixture")
        return AgentTeamExecutionRecord(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "lead"),
            AgentRunRequest(group, "future-turn", "task", runId = "future-run", goal = "Improve local fixture"))
    }
    fun work(retained: Retained, channel: JSONObject, id: String = "reuse") = JSONObject().put("id", id).put("member", "peer")
        .put("stage", "EXECUTE").put("assignment", "Use the retained procedure on local fixture").put("procedure_use", JSONObject()
            .put("procedure", ref(retained.skill)).put("domain", "fixture").put("inputs", JSONObject()).put("failures", JSONArray())
            .put(CollaborationCapabilityChannel.FIELD, ref(channel)).put("applicability", JSONObject().put("why", "Same input")
                .put("conditions_checked", JSONArray().put("Local schema")).put("remaining_uncertainty", "No real provider tests")))
    fun workflowWork(retained: Retained, channel: JSONObject, id: String = "workflow") = JSONObject()
        .put("id", id).put("member", "peer").put("stage", "EXECUTE")
        .put("assignment", retained.study.method.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND).getJSONArray("steps").getJSONObject(0).getString("assignment"))
        .put(CollaborationWorkflowWork.FIELD, JSONObject().put("execution_id", id).put("method", ref(retained.study.method)).put("step_id", "parse")
            .put("inputs", JSONObject().put("data", ref(dataset))).put(CollaborationCapabilityChannel.FIELD, ref(channel)))
}
