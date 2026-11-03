package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationProcedureTest {
    internal class Fixture {
        val experiment = CollaborationEvolutionTest.Fixture(CollaborationEvolutionTest())
        val workspace = experiment.workspace
        init { experiment.trial(); experiment.publishResult() }
        val lesson = experiment.lesson().getJSONArray("revisions").getJSONObject(0)
        fun access(person: String = "lead", round: Long = 8) = CollaborationWorkspaceAccess("group", "run", "turn", round, person, person)
        fun raw(id: String, kind: String, value: JSONObject, refs: JSONArray = JSONArray()) = JSONObject()
            .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Procedural memory fixture")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                .put("id", id).put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Original procedure fixture").put(kind, value))
                .put("observations", refs)))
        fun spec() = JSONObject().put("lesson", lesson).put("name", "Indexed retrieval").put("keywords", JSONArray().put("retrieval"))
            .put("limitations", "Synthetic fixture only").put("inputs", JSONArray().put(JSONObject().put("name", "corpus")
                .put("description", "Authorized test corpus").put("required", true)))
        fun skill(change: (JSONObject) -> Unit = {}): JSONObject {
            val receipt = workspace.publish(access("publisher", 6), raw("skill", CollaborationProceduralMemory.SKILL, spec().apply(change)).toString(), 500)
            return if (receipt.getString("status") == "recorded") receipt.getJSONArray("revisions").getJSONObject(0) else receipt
        }
        fun record(): AgentTeamExecutionRecord {
            val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
                AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), "Improve evidence comparison").map {
                it.copy(context = it.context + mapOf("collaboration_group_id" to "group", CollaborationLiveGraph.ENABLED to "1"))
            }
            return AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", members, primaryInstanceId = "lead"),
                AgentRunRequest("group", "turn", "task", runId = "run", goal = "Improve evidence comparison",
                    context = mapOf(CollaborationGoalLoop.ROUND to "7")))
        }
        fun work(skill: JSONObject) = JSONObject().put("id", "reuse").put("member", "peer").put("stage", "EXECUTE")
            .put("assignment", "Use the indexed method on the new corpus and verify the output").put("procedure_use", JSONObject()
                .put("procedure", skill).put("domain", "retrieval").put("inputs", JSONObject().put("corpus", "fixture-b"))
                .put("applicability", JSONObject().put("why", "Same authorized format").put("conditions_checked", JSONArray().put("Fixture schema matches"))
                    .put("remaining_uncertainty", "New input not yet verified")).put("failures", JSONArray()))
        fun report(work: List<JSONObject>) = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Reuse a tested method")
            .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "quality")
                .put("requirement", "Improve evidence comparison").put("status", "open").put("evidence", JSONArray())))
            .put("work", JSONArray(work)).put("blockers", JSONArray())
        fun finish(record: AgentTeamExecutionRecord, child: String, output: String, terminal: Boolean = false): AgentTeamExecutionRecord {
            val seq = record.events.size + 1L
            val result = AgentSubagentChildResult("run", child, "run", 1, AgentSubagentStatus.SUCCEEDED, output, startedAtMillis = 100, completedAtMillis = 300)
            return record.copy(events = record.events + AgentSubagentEvent(seq, "run", child, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = AgentSubagentStatus.SUCCEEDED, result = result) + if (terminal) listOf(AgentSubagentEvent(seq + 1, "run",
                kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)) else emptyList())
        }
    }

    @Test fun retainedProcedureIsDurableAcrossTasksWithoutPackageInstallation() {
        val f = Fixture(); val ref = f.skill()
        assertEquals("available_scoped_procedure", ref.getJSONObject("host_evolution").getString("state"))
        assertFalse(ref.getJSONObject("host_evolution").getBoolean("automatically_installed"))
        val later = f.access().copy(runId = "future-run", turnId = "future-turn", round = 0)
        val saved = CollaborationProceduralMemory.current(f.experiment.workspace(), later, ref)
        assertEquals(ref.getString("sha256"), saved.getString("sha256"))
        val plan = CollaborationProcedureWork.plan(f.record(), listOf(f.work(ref)), { f.workspace }, later)
        val binding = JSONObject(CollaborationProcedureWork.context(plan.work.single()).getValue(CollaborationProcedureWork.TASK))
        assertEquals("Use the saved indexed method", binding.getString("method"))
        assertEquals("fixture-b", binding.getJSONObject("inputs").getString("corpus"))
        assertFalse(binding.getBoolean("grants_permissions"))
    }

    @Test fun untestedProcedureReplacementAndRejectedLessonCannotBecomeSkill() {
        val f = Fixture()
        assertTrue(f.skill { it.put("procedure", "New untested method") }.getString("reason").contains("new experiment"))
        val g = Fixture()
        val rejected = g.experiment.lesson(person = "other-reviewer", decision = "reject").getJSONArray("revisions").getJSONObject(0)
        assertTrue(g.skill { it.put("lesson", rejected) }.getString("reason").contains("independently retained"))
    }

    @Test fun strictInputSchemaAndHostBindingCannotBeForged() {
        val f = Fixture(); val skill = f.skill()
        val invalid = listOf<(JSONObject) -> Unit>(
            { it.getJSONObject("procedure_use").getJSONObject("inputs").remove("corpus") },
            { it.getJSONObject("procedure_use").getJSONObject("inputs").put("extra", "not declared") },
            { it.getJSONObject("procedure_use").getJSONObject("inputs").put("corpus", JSONObject.NULL) },
            { it.put("host_procedure", JSONObject()) },
            { it.getJSONObject("procedure_use").getJSONObject("procedure").put("revision", "1") },
            { it.getJSONObject("procedure_use").getJSONObject("applicability").put("conditions_checked", JSONArray()) })
        invalid.forEach { change -> reject { CollaborationProcedureWork.plan(f.record(), listOf(f.work(JSONObject(skill.toString())).apply(change)), { f.workspace }, f.access()) } }
    }

    @Test fun scopeIsolationAndChangedTargetsRejectReuseButPreserveHistory() {
        val f = Fixture(); val skill = f.skill()
        reject { CollaborationProceduralMemory.current(f.workspace, f.access().copy(groupId = "other"), skill) }
        reject { CollaborationProceduralMemory.current(f.workspace, f.access("peer", 6), skill) }
        val old = f.workspace.read(f.access(), f.experiment.innovation.getString("object_id"), 1)!!
        val update = f.raw("ignored", "innovation", old.getJSONObject("body").getJSONObject("innovation"))
        update.getJSONArray("workspace").getJSONObject(0).put("object_id", old.getString("object_id")).put("base_revision", 1)
        assertEquals("recorded", f.workspace.publish(f.access("inventor", 9).copy(nodeId = "inventor-revision"), update.toString(), 900).getString("status"))
        reject { CollaborationProceduralMemory.current(f.workspace, f.access(round = 10), skill) }
        assertEquals("historical_requires_revalidation", f.workspace.browseEvolution(f.access(round = 10)).revisions
            .single { it.getString("object_id") == skill.getString("object_id") }.getString("evolution_applicability"))
        assertNotNull(f.workspace.read(f.access(round = 10), skill.getString("object_id"), 1))
    }

    @Test fun claimsAreStableAcrossRecoveryButNewTasksCanReuseSameSkill() {
        val f = Fixture(); val skill = f.skill(); val work = f.work(skill)
        val first = CollaborationProcedureWork.plan(f.record(), listOf(work), { f.workspace }, f.access())
        val restored = f.record().copy(request = f.record().request.copy(context = f.record().request.context + (CollaborationProcedureWork.CLAIMS to first.claims)))
        assertEquals(first.claims, CollaborationProcedureWork.plan(restored, listOf(JSONObject(work.toString())), { f.workspace }, f.access()).claims)
        val altered = JSONObject(work.toString()).apply { getJSONObject("procedure_use").getJSONObject("inputs").put("corpus", "new-data") }
        reject { CollaborationProcedureWork.plan(restored, listOf(altered), { f.workspace }, f.access()) }
        reject { CollaborationProcedureWork.plan(restored, listOf(JSONObject(work.toString()).put("assignment", "Different objective")), { f.workspace }, f.access()) }
        reject { CollaborationProcedureWork.plan(restored, listOf(JSONObject(work.toString()).apply { remove("procedure_use") }), { f.workspace }, f.access()) }
        assertEquals(1, CollaborationProcedureWork.plan(restored, listOf(altered.put("id", "new-work")), { f.workspace }, f.access()).work.size)
    }

    @Test fun missingWorkspaceAndMixedInvalidBatchNeverMutateTheRequest() {
        val f = Fixture(); val item = f.work(f.skill()); val before = item.toString()
        reject { CollaborationProcedureWork.plan(f.record(), listOf(item), null, f.access()) }
        reject { CollaborationProcedureWork.plan(f.record(), listOf(item, JSONObject(item.toString()).put("host_procedure", JSONObject())), { f.workspace }, f.access()) }
        assertEquals(before, item.toString())
        val ordinary = JSONObject().put("id", "normal")
        assertSame(ordinary, CollaborationProcedureWork.plan(f.record(), listOf(ordinary), { error("No workspace lookup for ordinary tasks") }, f.access()).work.single())
    }

    @Test fun failedReuseIsCapturedOnceWithoutClaimingKnowledgeGain() {
        val f = Fixture(); val selected = CollaborationProcedureWork.plan(f.record(), listOf(f.work(f.skill())), { f.workspace }, f.access()).work.single()
        val member = f.record().definition.members.last().copy(instanceId = "reuse-node", context = CollaborationProcedureWork.context(selected))
        val record = f.record().copy(definition = f.record().definition.copy(members = listOf(member)))
        val result = AgentSubagentChildResult("run", member.memberId, "run", 1, AgentSubagentStatus.FAILED, "failure", startedAtMillis = 20, completedAtMillis = 120)
        val raw = CollaborationProcedureWork.capture(record, listOf(result))
        val saved = JSONObject(raw).getJSONObject(member.memberId)
        assertEquals(100, saved.getInt("elapsed_ms")); assertEquals("failed", saved.getString("status"))
        assertFalse(saved.getBoolean("capability_verified")); assertTrue(saved.isNull("learning_gain"))
        assertEquals(raw, CollaborationProcedureWork.capture(record.copy(request = record.request.copy(context = mapOf(CollaborationProcedureWork.OUTCOMES to raw))), listOf(result)))
        assertEquals("{}", CollaborationProcedureWork.capture(record, listOf(result.copy(supervisorId = "other-run"))))
    }

    @Test fun nextRoundBindsTheOriginalMethodAndRejectsMixedBadWorkAtomically() {
        val f = Fixture(); val item = f.work(f.skill())
        val record = f.finish(f.record(), "lead", f.report(listOf(item)).toString(), true)
        val next = CollaborationGoalLoop.advance(record, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val member = next.definition.members.single { CollaborationProcedureWork.TASK in it.context }
        assertEquals("Use the saved indexed method", JSONObject(member.context.getValue(CollaborationProcedureWork.TASK)).getString("method"))
        assertEquals("fixture-b", JSONObject(member.context.getValue(CollaborationProcedureWork.TASK)).getJSONObject("inputs").getString("corpus"))
        val bad = JSONObject(item.toString()).put("id", "bad").apply { getJSONObject("procedure_use").getJSONObject("inputs").remove("corpus") }
        val rejected = CollaborationGoalLoop.advance(f.finish(f.record(), "lead", f.report(listOf(item, bad)).toString(), true), "lead", 1000, true,
            candidateWorkspace = { f.workspace })!!
        assertTrue(rejected.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE })
        assertEquals("{}", rejected.request.context[CollaborationProcedureWork.CLAIMS])
    }

    @Test fun originalFailuresRequireReadCoverageAndRemainProposedRemedies() {
        val f = Fixture(); val reader = f.access()
        val observation = f.experiment.ledger.record(f.access("executor", 7), "failed", "fixture.tool", "{}", """{"error":"offline"}""", 600, 601,
            CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL)
        val spec = JSONObject("""{"observed_issue":"Tool unavailable","interpretation":"Possibly network","uncertainty":"Cause unverified",
            "applies_when":"Same symptom","avoid_repetition":"Check connectivity before repeating","reconsider_when":"Network recovers",
            "recovery_options":["Inspect connectivity","Use an authorized alternative"]}""")
        val raw = f.raw("failure", CollaborationProceduralMemory.FAILURE, spec, JSONArray().put(observation))
        assertEquals("rejected", f.workspace.publish(reader, raw.toString(), 700).getString("status"))
        val covered = reader.copy(nodeId = "covered-failure")
        var offset: Int? = 0
        while (offset != null) offset = f.experiment.ledger.readPage(covered, observation.getString("evidence_id"), observation.getString("sha256"), offset)!!.next
        assertEquals("rejected", f.workspace.publish(reader.copy(nodeId = "uncovered-failure"), raw.toString(), 701).getString("status"))
        val accepted = f.workspace.publish(covered, f.raw("failure-read", CollaborationProceduralMemory.FAILURE, spec, JSONArray().put(observation)).toString(), 702)
        assertEquals(accepted.toString(), "recorded", accepted.getString("status"))
        val ref = accepted.getJSONArray("revisions").getJSONObject(0)
        assertFalse(ref.getJSONObject("host_evolution").getBoolean("cause_verified"))
        assertFalse(ref.getJSONObject("host_evolution").getBoolean("permanent_prohibition"))
        val item = f.work(f.skill()).apply { getJSONObject("procedure_use").getJSONArray("failures").put(ref) }
        reject { CollaborationProcedureWork.plan(f.record(), listOf(item), { f.workspace }, reader) }
        val binding = JSONObject(CollaborationProcedureWork.context(CollaborationProcedureWork.plan(f.record(), listOf(item), { f.workspace }, reader.copy(round = 9)).work.single())
            .getValue(CollaborationProcedureWork.TASK))
        assertEquals("Network recovers", binding.getJSONArray("failure_experiences").getJSONObject(0).getJSONObject("experience").getString("reconsider_when"))
    }

    @Test fun liveWorkAdmissionPreservesExistingTasksAndReplaysWithoutDuplicate() {
        val f = Fixture(); val item = f.work(f.skill()); val base = f.record()
        val people = base.definition.members.map { it.copy(deliveryMode = AgentDeliveryMode.IGNORE) }
        val slow = people.last().copy(instanceId = "slow", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.last().context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "slow-work", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        val planner = people.first().copy(instanceId = "planner-node", deliveryMode = AgentDeliveryMode.OBSERVE,
            context = people.first().context + mapOf(CollaborationLiveGraph.PLANNER to "1", CollaborationGoalLoop.ROSTER to "false"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"), dependsOnAgentIds = setOf("slow", planner.memberId))
        val live = base.copy(definition = base.definition.copy(members = people + slow + planner + final, primaryInstanceId = "final"),
            request = base.request.copy(context = base.request.context + (CollaborationGoalLoop.ROUND to "8")))
        val returned = f.finish(live, planner.memberId, JSONObject().put("format", CollaborationLiveGraph.FORMAT)
            .put("summary", "Reuse while independent work continues").put("work", JSONArray().put(item)).toString())
        val next = CollaborationLiveGraph.update(returned, setOf(planner.memberId), 1000, { f.workspace })
        assertEquals(1, next.definition.members.count { CollaborationProcedureWork.TASK in it.context })
        assertEquals(slow, next.definition.members.single { it.memberId == "slow" })
        assertEquals(next.definition, CollaborationLiveGraph.update(next, setOf(planner.memberId), 2000, { f.workspace }).definition)
    }

    @Test fun failureClassificationDoesNotLearnFromFalseOrEmptyErrors() {
        for (raw in listOf("{}", "{\"error\":false}", "{\"error\":null}", "{\"error\":0}", "{\"error\":{}}", "{\"error\":[]}",
            "{\"error\":\"\"}", "{\"success\":true}")) assertEquals(raw, "returned", CollaborationEvidenceOutcome.status(raw))
        for (raw in listOf("{\"error\":true}", "{\"error\":\"offline\"}", "{\"error\":{\"code\":\"denied\"}}", "{\"success\":false}",
            "{\"ok\":false}", "{\"isError\":true}", "{\"status\":\"failed\",\"error\":false}")) assertEquals(raw, "failed", CollaborationEvidenceOutcome.status(raw))
        assertEquals("unstructured", CollaborationEvidenceOutcome.status("No machine-readable outcome"))
        val f = Fixture()
        val good = f.experiment.ledger.record(f.access(), "good", "fixture", "{}", "{\"error\":false}", 600, 601)
        assertEquals("returned", good.getString("status"))
        val bad = f.experiment.ledger.record(f.access(), "bad", "fixture", "{}", "{\"success\":false}", 600, 601)
        assertEquals("failed", bad.getString("status"))
        assertEquals(1, f.experiment.ledger.problems(f.access()).first.size)
    }

    @Test fun historicalMisclassifiedEmptyErrorCannotBecomeFailureExperience() {
        val value = JSONObject("""{"observed_issue":"Claimed failure","interpretation":"Unknown","uncertainty":"Unverified",
            "applies_when":"Fixture","avoid_repetition":"Inspect","reconsider_when":"After evidence","recovery_options":["Inspect original"]}""")
        val source = JSONObject().put("status", "failed").put("output_json", "{\"error\":false}")
            .put("observation_kind", "tool_output_recorded").put("tool", "fixture")
        reject { CollaborationProceduralMemory.failure(value, JSONObject().put("host_observations", JSONArray().put(JSONObject())), { source }, {}) }
    }

    @Test fun reorderedJsonInputsKeepTheSameRecoveredBinding() {
        val f = Fixture(); val work = f.work(f.skill())
        work.getJSONObject("procedure_use").getJSONObject("inputs").put("corpus", JSONObject().put("b", 2).put("a", 1))
        val first = CollaborationProcedureWork.plan(f.record(), listOf(work), { f.workspace }, f.access())
        val restored = f.record().copy(request = f.record().request.copy(context = mapOf(CollaborationProcedureWork.CLAIMS to first.claims)))
        work.getJSONObject("procedure_use").getJSONObject("inputs").put("corpus", JSONObject().put("a", 1).put("b", 2))
        assertEquals(first.claims, CollaborationProcedureWork.plan(restored, listOf(work), { f.workspace }, f.access()).claims)
    }

    private fun reject(block: () -> Unit) = assertNotNull("Expected precise rejection", runCatching(block).exceptionOrNull())
}
