package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationWorkflowMethod.KIND
import com.galaxyssi.chat.CollaborationWorkflowMethod.COMPARISON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationWorkflowTest {
    @Test fun persistedContextRetainsExactInternalBindingsButNotArbitraryKeys() {
        assertTrue(isPersistedAgentTeamContextKey(CollaborationWorkflowWork.TASK))
        assertTrue(isPersistedAgentTeamContextKey(CollaborationPredictionWork.TASK))
        assertFalse(isPersistedAgentTeamContextKey("collaboration_workflow_permissions"))
        assertFalse(isPersistedAgentTeamContextKey("collaboration_prediction_execute_anything"))
    }

    internal class Fixture {
        val f = CollaborationInnovationTest.Fixture()
        fun step(id: String, role: String, dependencies: List<String> = emptyList(), review: Boolean = false) = JSONObject()
            .put("id", id).put("role", role).put("stage", if (review) "VERIFY" else "EXECUTE").put("assignment", "Execute $id on the provided fixture")
            .put("depends_on", JSONArray(dependencies)).put("independent_review", review)
        val spec = JSONObject().put("purpose", "Avoid repeated parsing").put("domain", "fixture").put("bottleneck", "Repeated scans")
            .put("change_rationale", "Reuse immutable index").put("applies_when", "Same dataset").put("avoid_when", "Mutable source")
            .put("risks", "Stale cache").put("expected_gain", "Fewer parses at equal quality").put("falsifier", "Missing fields")
            .put("dimensions", JSONArray().put("retrieval").put("verification")).put("roles", JSONArray().put("worker").put("reviewer"))
            .put("inputs", JSONArray().put("dataset")).put("steps", JSONArray().put(step("parse", "worker")).put(step("check", "reviewer", listOf("parse"), true)))
        val method = f.ref(f.publish("workflow", KIND, spec, round = 5))
        fun work(execution: String = "fixture-run") = CollaborationEvolutionContract.objects(spec, "steps").map { step ->
            JSONObject(step.toString()).apply { remove("role") }.put("id", "$execution:${step.getString("id")}")
                .put("member", if (step.getString("role") == "worker") "peer" else "lead")
                .put("depends_on", JSONArray(CollaborationWorkGraph.dependencies(step).map { "$execution:$it" }))
                .put(CollaborationWorkflowWork.FIELD, JSONObject().put("execution_id", execution).put("method", method)
                    .put("step_id", step.getString("id")).put("inputs", JSONObject().put("dataset", f.baseline)))
        }
        fun admitted(record: AgentTeamExecutionRecord = f.record(), work: List<JSONObject> = work()) =
            CollaborationWorkflowWork.plan(record, work, { f.workspace }, f.access())
        fun withClaims(plan: CollaborationWorkflowWork.Plan) = f.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationWorkflowWork.CLAIMS to plan.claims))) }
    }

    @Test fun methodIsImmutableAndDoesNotClaimImprovementOrGrantAuthority() {
        val t = Fixture(); assertFalse(t.method.getJSONObject(HOST).getBoolean("quality_improved"))
        assertFalse(t.method.getJSONObject(HOST).getBoolean("grants_permissions"))
        val raw = JSONObject(t.f.raw("changed", KIND, t.spec))
        raw.getJSONArray("workspace").getJSONObject(0).put("object_id", t.method.getString("object_id")).put("base_revision", 1)
        assertEquals("rejected", t.f.workspace.publish(t.f.access(), raw.toString()).getString("status"))
    }

    @Test fun definitionRejectsCyclesMissingRolesAndPermissionFields() {
        for (change in listOf("cycle", "role", "tool", "self-review", "missing", "dimension", "boolean")) {
            val t = Fixture(); val spec = JSONObject(t.spec.toString()); val first = spec.getJSONArray("steps").getJSONObject(0)
            when (change) {
                "cycle" -> first.put("depends_on", JSONArray().put("check"))
                "role" -> first.put("role", "outsider")
                "tool" -> first.put("permissions", "all")
                "self-review" -> spec.getJSONArray("steps").getJSONObject(1).put("role", "worker")
                "missing" -> first.put("depends_on", JSONArray().put("absent"))
                "dimension" -> spec.put("dimensions", JSONArray().put("disable-validation"))
                else -> first.put("independent_review", "false")
            }
            assertEquals(change, "rejected", t.f.publish("bad-$change", KIND, spec, round = 6).getString("status"))
        }
    }

    @Test fun changedMethodsPreserveFeedbackAndPriorVersion() {
        val t = Fixture(); val revised = JSONObject(t.spec.toString()).put("previous_method", t.method)
        assertEquals("rejected", t.f.publish("no-feedback", KIND, revised, round = 6).getString("status"))
        revised.put("feedback", JSONArray().put(t.f.baseline))
        val saved = t.f.ref(t.f.publish("improved-method", KIND, revised, round = 6))
        assertEquals(t.method.getString("sha256"), saved.getJSONObject(HOST).getJSONObject("previous_method").getString("sha256"))
        assertFalse(saved.getJSONObject(HOST).getBoolean("quality_improved"))
        assertEquals("rejected", t.f.publish("other-domain", KIND, revised.put("domain", "medicine"), round = 6).getString("status"))
    }

    @Test fun aThousandPlannedStepsAreNotAGoalStopLimit() {
        val t = Fixture(); val spec = JSONObject(t.spec.toString()).put("roles", JSONArray().put("worker"))
        spec.put("steps", JSONArray((0 until 1000).map { t.step("s$it", "worker", if (it == 0) emptyList() else listOf("s${it - 1}")) }))
        assertEquals("unverified_workflow_candidate", CollaborationWorkflowMethod.definition(spec) { _, _ -> error("No I/O") }.getString("state"))
    }

    @Test fun completeGraphBindsRolesInputsAndIndependentReview() {
        val t = Fixture(); val plan = t.admitted()
        assertEquals(2, plan.work.size)
        val binding = JSONObject(CollaborationWorkflowWork.context(plan.work.first()).getValue(CollaborationWorkflowWork.TASK))
        assertEquals(t.method.getString("sha256"), binding.getJSONObject("method").getString("sha256"))
        assertEquals("peer", binding.getString("member")); assertFalse(binding.getBoolean("quality_improved"))
        assertEquals(setOf("fixture-run:parse"), CollaborationWorkGraph.dependencies(plan.work.last()))
    }

    @Test fun rejectsPartialGraphDuplicatesAndChangedAssignmentOrDependencies() {
        val t = Fixture()
        reject { t.admitted(work = t.work().take(1)) }
        reject { t.admitted(work = t.work() + t.work().first()) }
        for (field in listOf("assignment", "stage", "member", "depends_on", "independent_review", "dependency_policy")) {
            val work = t.work(); val item = work.last()
            when (field) {
                "member" -> item.put(field, "peer")
                "depends_on" -> item.put(field, JSONArray())
                "independent_review" -> item.put(field, false)
                else -> item.put(field, "changed")
            }
            reject { t.admitted(work = work) }
        }
    }

    @Test fun inputVersionScopeAndHostBindingTamperingAreRejected() {
        val t = Fixture()
        for (change in listOf("inputs", "digest", "revision", "host", "unknown", "member")) {
            val work = t.work(); val item = work.first(); val use = item.getJSONObject(CollaborationWorkflowWork.FIELD)
            when (change) {
                "inputs" -> use.put("inputs", JSONObject())
                "digest" -> use.put("method", JSONObject(t.method.toString()).put("sha256", "wrong"))
                "revision" -> use.put("method", JSONObject(t.method.toString()).put("revision", 1.5))
                "host" -> item.put("host_workflow", JSONObject())
                "member" -> item.put("member", "unauthorized")
                else -> use.put("permissions", "all")
            }
            reject { t.admitted(work = work) }
        }
        reject { CollaborationWorkflowWork.plan(t.f.record(), t.work(), { t.f.workspace }, t.f.access().copy(groupId = "other")) }
    }

    @Test fun replayPreservesClaimsAndCannotRewriteOrDetachWork() {
        val t = Fixture(); val first = t.admitted(); val restored = t.withClaims(first)
        assertEquals(first.claims, CollaborationWorkflowWork.plan(restored, t.work().reversed(), { t.f.reopen() }, t.f.access()).claims)
        reject { t.admitted(restored, t.work().map { JSONObject(it.toString()).apply { remove(CollaborationWorkflowWork.FIELD) } }) }
        val changed = t.work(); changed.forEach { it.getJSONObject(CollaborationWorkflowWork.FIELD).getJSONObject("inputs").put("dataset", "changed") }
        reject { t.admitted(restored, changed) }
        reject { t.admitted(restored, t.work().map { it.apply { getJSONObject(CollaborationWorkflowWork.FIELD).put("execution_id", "different") } }) }
        assertEquals(2, t.admitted(restored, t.work("next-experiment")).work.size)
    }

    @Test fun ordinaryWorkAvoidsIoAndInvalidBatchDoesNotMutateInput() {
        val t = Fixture(); val raw = JSONObject().put("id", "ordinary")
        assertSame(raw, CollaborationWorkflowWork.plan(t.f.record(), listOf(raw), { error("No I/O") }, t.f.access()).work.single())
        val work = t.work().take(1); val before = work.toString()
        reject { t.admitted(work = work) }; assertEquals(before, work.toString())
    }

    @Test fun nextRoundDispatchesExactGraphAndPersistsOutcomeWithoutQualityClaim() {
        val t = Fixture(); val record = t.f.record()
        val completed = t.f.completed(record, "lead", t.f.report(t.work()).toString(), true)
        val next = CollaborationGoalLoop.advance(completed, "lead", 1000, false, candidateWorkspace = { t.f.workspace })!!
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(2, nodes.size)
        assertEquals(setOf(nodes.first().memberId), nodes.last().dependsOnAgentIds)
        var done = t.f.completed(next, nodes.first().memberId, "Local parsed result")
        done = t.f.completed(done, nodes.last().memberId, "Local verified result")
        done = t.f.completed(done, next.definition.primaryMemberId, t.f.report(emptyList()).toString(), true)
        val resumed = CollaborationGoalLoop.advance(done, next.definition.primaryMemberId, 2000, false, candidateWorkspace = { t.f.reopen() })!!
        val outcomes = JSONObject(resumed.request.context.getValue(CollaborationWorkflowWork.OUTCOMES).toString())
        assertEquals(2, outcomes.length()); assertEquals(200, outcomes.getJSONObject(nodes.first().memberId).getInt("elapsed_ms"))
        assertFalse(outcomes.getJSONObject(nodes.first().memberId).getBoolean("quality_improved"))
    }

    @Test fun partialCompletionReplayDoesNotRerunCompletedStep() {
        val t = Fixture(); val first = t.admitted(); val base = t.withClaims(first)
        val record = base.copy(request = base.request.copy(context = base.request.context + mapOf(
            CollaborationGoalLoop.FINISHED_WORK to "[\"fixture-run:parse\"]", CollaborationGoalLoop.FINISHED_AUTHORS to "{\"fixture-run:parse\":\"peer\"}")))
        val next = CollaborationGoalLoop.advance(t.f.completed(record, "lead", t.f.report(t.work()).toString(), true), "lead", 1000, false,
            candidateWorkspace = { t.f.workspace })!!
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(1, nodes.size); assertEquals("fixture-run:check", nodes.single().context[CollaborationGoalLoop.WORK_ID])
    }

    @Test fun livePlannerAddsWorkflowWithoutWaitingForUnrelatedWorkAndRejectsPartialReplay() {
        val t = Fixture(); val base = t.f.record(); val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "unrelated"))
        val planner = people.first().copy(instanceId = "planner", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        val record = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"))
        fun answer(work: List<JSONObject>) = JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Test workflow").put("work", JSONArray(work)).toString()
        val next = CollaborationLiveGraph.update(t.f.completed(record, "planner", answer(t.work())), setOf("planner"), 1000, { t.f.workspace })
        val nodes = next.definition.members.filter { CollaborationWorkflowWork.TASK in it.context }
        assertEquals(2, nodes.size); assertTrue(nodes.none { "slow" in it.dependsOnAgentIds })
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf("planner"), 2000, { t.f.workspace }).definition)
        val captured = CollaborationLiveGraph.update(t.f.completed(next, nodes.first().memberId, "Local output"), setOf("planner", nodes.first().memberId), 3000, { t.f.workspace })
        assertTrue(JSONObject(captured.request.context.getValue(CollaborationWorkflowWork.OUTCOMES).toString()).has(nodes.first().memberId))
        val bad = CollaborationLiveGraph.update(t.f.completed(record, "planner", answer(t.work().take(1))), setOf("planner"), 1000, { t.f.workspace })
        assertTrue(bad.definition.members.none { CollaborationWorkflowWork.TASK in it.context })
        assertTrue(bad.request.context.getValue(CollaborationLiveGraph.FEEDBACK).toString().contains("complete workflow"))
    }

    @Test fun workflowComparisonRequiresDatasetAndQualityRegression() {
        val t = Fixture()
        val before = t.f.ref(t.f.publish("old-idea", "innovation", JSONObject(t.f.ideaSpec.toString()).put(KIND, t.method), round = 6, parents = JSONArray().put(t.f.opportunity)))
        val changed = t.f.ref(t.f.publish("new-method", KIND, JSONObject(t.spec.toString()).put("previous_method", t.method).put("feedback", JSONArray().put(t.f.baseline)), round = 6))
        val after = t.f.ref(t.f.publish("new-idea", "innovation", JSONObject(t.f.ideaSpec.toString()).put(KIND, changed), round = 7, parents = JSONArray().put(t.f.opportunity)))
        val spec = JSONObject(t.f.spec.toString()).put("baseline", before).put("innovation", after)
        assertEquals("rejected", t.f.publish("no-binding", "experiment_plan", spec, round = 8).getString("status"))
        spec.put(COMPARISON, JSONObject().put("dataset", t.f.baseline).put("controlled_conditions", "Same input")
            .put("quality_oracle", "Exact field equality").put("cost_accounting", "All parse calls").put("selection_bias", "Synthetic only"))
        val plan = t.f.ref(t.f.publish("paired", "experiment_plan", spec, round = 8))
        val binding = plan.getJSONObject(HOST).getJSONObject(COMPARISON)
        val sample = JSONObject().put("workflow_sha256", changed.getString("sha256")).put("dataset_sha256", t.f.baseline.getString("sha256"))
        CollaborationWorkflowMethod.sample(binding, sample, "candidate")
        reject { CollaborationWorkflowMethod.sample(binding, sample, "baseline") }
        reject { CollaborationWorkflowMethod.sample(binding, sample.put("dataset_sha256", "other"), "candidate") }
        spec.getJSONArray("cases").remove(2)
        assertEquals("rejected", t.f.publish("speed-only", "experiment_plan", spec, round = 8).getString("status"))
    }

    @Test fun originalComparisonMeasuresLocalImprovementAndPreservesRegression() {
        for (regress in listOf(false, true)) {
            val t = Fixture()
            val before = t.f.ref(t.f.publish("old-idea", "innovation", JSONObject(t.f.ideaSpec.toString()).put(KIND, t.method), round = 6, parents = JSONArray().put(t.f.opportunity)))
            val changed = t.f.ref(t.f.publish("new-method", KIND, JSONObject(t.spec.toString()).put("previous_method", t.method).put("feedback", JSONArray().put(t.f.baseline)), round = 6))
            val after = t.f.ref(t.f.publish("new-idea", "innovation", JSONObject(t.f.ideaSpec.toString()).put(KIND, changed), round = 7, parents = JSONArray().put(t.f.opportunity)))
            assertTrue(after.getJSONObject(HOST).getJSONArray("contributors").toString().contains("new-method"))
            val spec = JSONObject(t.f.spec.toString()).put("baseline", before).put("innovation", after)
                .put("cases", JSONArray().put(t.f.case("calls", "target").put("direction", "minimize").put("metric", "parse_calls"))
                    .put(t.f.case("correct", "regression").put("metric", "matches")))
                .put(COMPARISON, JSONObject().put("dataset", t.f.baseline).put("controlled_conditions", "Same input")
                    .put("quality_oracle", "Exact field equality").put("cost_accounting", "All parses").put("selection_bias", "Local fixture"))
            val plan = t.f.ref(t.f.publish("paired", "experiment_plan", spec, round = 8, now = 150))
            var oldCalls = 0; var newCalls = 0
            val baseline = List(4) { JSONObject("{\"value\":7}").also { oldCalls++ }.getInt("value") }
            val parsed = JSONObject("{\"value\":7}").also { newCalls++ }
            val candidate = List(4) { if (regress) 0 else parsed.getInt("value") }
            val samples = JSONArray()
            for (variant in listOf("baseline", "candidate")) for (case in listOf("calls", "correct")) {
                val old = variant == "baseline"
                samples.put(JSONObject().put("case_id", case).put("variant", variant).put("variant_sha256", (if (old) before else after).getString("sha256"))
                    .put("workflow_sha256", (if (old) t.method else changed).getString("sha256")).put("dataset_sha256", t.f.baseline.getString("sha256"))
                    .put("metric", if (case == "calls") "parse_calls" else "matches").put("repetition", 1).put("budget_used", if (old) oldCalls else newCalls)
                    .put("value", if (case == "calls") { if (old) oldCalls else newCalls } else { (if (old) baseline else candidate).count { it == 7 } }))
            }
            val report = JSONObject().put("format", CollaborationEvolutionExperiment.FORMAT).put("plan_sha256", plan.getString("sha256"))
                .put("environment", "fixture").put("budget_unit", "operations").put("measurements", samples)
            val observation = t.f.ledger.record(t.f.access("executor", 9), "workflow-trial", "fixture.compare", "{}", report.toString(), 200, 201, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            val refs = JSONArray().put(observation); t.f.read(t.f.access("analyst", 10, "measured"), refs)
            val measured = t.f.ref(t.f.publish("measured", "experiment_result", JSONObject().put("plan", plan).put("interpretation", "Local computation")
                .put("limitations", "No model calls"), "analyst", 10, 300, refs))
            assertEquals(if (regress) "regressed" else "measured_improvement", measured.getJSONObject(HOST).getString("state"))
            assertEquals(!regress, measured.getJSONObject(HOST).getBoolean("eligible_for_retention"))
        }
    }

    @Test fun pastOrdinaryWorkCannotBeRelabeledAsNewMethodEvidence() {
        val t = Fixture(); val record = t.f.record()
        val completed = record.copy(request = record.request.copy(context = record.request.context +
            (CollaborationGoalLoop.FINISHED_WORK to "[\"fixture-run:parse\"]")))
        reject { t.admitted(completed) }
    }

    @Test fun missingTimingAndForeignResultsCannotBecomePerfectPerformance() {
        val t = Fixture(); val p = t.admitted(); val base = t.withClaims(p)
        val member = base.definition.members.last().copy(context = base.definition.members.last().context + CollaborationWorkflowWork.context(p.work.first()))
        val record = base.copy(definition = base.definition.copy(members = base.definition.members.dropLast(1) + member))
        val result = AgentSubagentChildResult("run", member.memberId, "run", 1, AgentSubagentStatus.FAILED, "", startedAtMillis = 0, completedAtMillis = 10)
        assertEquals("{}", CollaborationWorkflowWork.capture(record, listOf(result.copy(supervisorId = "other"))))
        val captured = CollaborationWorkflowWork.capture(record, listOf(result))
        assertTrue(JSONObject(captured).getJSONObject(member.memberId).isNull("elapsed_ms"))
        val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationWorkflowWork.OUTCOMES to captured)))
        assertEquals(captured, CollaborationWorkflowWork.capture(restored, listOf(result.copy(completedAtMillis = 999))))
    }

    private fun reject(block: () -> Unit) = assertNotNull("Expected rejection", runCatching(block).exceptionOrNull())
}
