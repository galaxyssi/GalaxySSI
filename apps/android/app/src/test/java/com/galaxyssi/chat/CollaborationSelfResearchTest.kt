package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationSelfResearchTest {
    private fun fixture(): CollaborationSelfResearchFixture {
        val rows = CollaborationEvolutionTest.Rows()
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage,
            evidenceOriginal = { a, r -> ledger.read(a, r.getString("evidence_id"), r.getString("sha256")) })
        return CollaborationSelfResearchFixture(CollaborationRetentionFixture(workspace, ledger))
    }
    private fun rejected(block: () -> Unit) = assertTrue(runCatching(block).isFailure)

    @Test fun observedBottleneckThroughControlledExperimentToProtectedAdoption() {
        val s = fixture(); val f = s.f
        val retained = s.retain(s.study()); val channel = f.accepted(f.select(retained))
        val review = f.accepted(s.review(s.adoption(retained, channel), retained.study.observations))
        assertEquals("reviewed_adopt", review.getJSONObject(HOST).getString("state"))
        assertTrue(review.getJSONObject(HOST).getBoolean("improvement_verified"))
        assertFalse(review.getJSONObject(HOST).getBoolean("goal_verified"))
        assertFalse(review.getJSONObject(HOST).getBoolean("automatically_installed"))
        val next = s.next(review)
        assertEquals(review.getString("sha256"), next.getJSONObject(HOST).getJSONObject("previous_review").getString("sha256"))
    }

    @Test fun adoptionCannotBeTextOnlyOrUseUnprotectedSelection() {
        val s = fixture(); val f = s.f
        assertEquals("rejected", s.review(s.reviewSpec(decision = "adopt")).getString("status"))
        val retained = s.retain(s.study()); val channel = f.accepted(f.select(retained))
        val spec = s.adoption(retained, channel).put("channels", JSONArray())
        assertEquals("rejected", s.review(spec, retained.study.observations).getString("status"))
    }

    @Test fun independentReviewMustReadEveryOriginal() {
        val s = fixture(); val f = s.f
        val retained = s.retain(s.study()); val channel = f.accepted(f.select(retained)); val spec = s.adoption(retained, channel)
        assertEquals("rejected", s.review(spec).getString("status"))
        for (person in listOf("curator", "author", "planner", "executor"))
            assertEquals("rejected", s.review(spec, retained.study.observations, person).getString("status"))
    }

    @Test fun regressionsAreRejectedAndInformNextCycleWithoutErasingEvidence() {
        val s = fixture(); val f = s.f
        val study = s.study(editReport = { report -> val samples = report.getJSONArray("measurements"); repeat(samples.length()) { i ->
            val sample = samples.getJSONObject(i)
            if (sample.getString("case_id") == "legacy" && sample.getString("variant") == "candidate") sample.put("value", 0)
        } })
        assertEquals("regressed", study.result.getJSONObject(HOST).getString("state"))
        assertEquals("rejected", f.lesson(study).getString("status"))
        val lesson = f.accepted(f.lesson(study, decision = "reject"))
        val review = f.accepted(s.review(s.reviewSpec(decision = "reject").put("evaluations", JSONArray().put(JSONObject()
            .put("result", f.ref(study.result)).put("lesson", f.ref(lesson)))), study.observations))
        val next = s.next(review)
        assertEquals("reject", next.getJSONObject(HOST).getString("previous_decision"))
        assertNotNull(f.workspace.read(f.access(), study.result.getString("object_id"), 1))
    }

    @Test fun borrowedCycleEvidenceAndDuplicateResultsAreRejected() {
        val s = fixture(); val f = s.f
        val retained = s.retain(s.study()); val channel = f.accepted(f.select(retained))
        val prior = f.accepted(s.review(s.reviewSpec()))
        val next = s.next(prior)
        assertEquals("rejected", s.review(s.adoption(retained, channel).put("cycle", f.ref(next)), retained.study.observations).getString("status"))
        val spec = s.adoption(retained, channel)
        spec.getJSONArray("evaluations").put(spec.getJSONArray("evaluations").getJSONObject(0))
        assertEquals("rejected", s.review(spec, retained.study.observations).getString("status"))
    }

    @Test fun waitNeedsObservedBlockerAndDoesNotPauseTheUserGoal() {
        val s = fixture(); val f = s.f
        val spec = s.reviewSpec(decision = "wait").put("blocker", JSONObject().put("reason", "Unavailable test fixture")
            .put("resume_when", "Authorized fixture available").put("checked_alternatives", "Local alternative insufficient"))
        assertEquals("rejected", s.review(spec).getString("status"))
        val review = f.accepted(s.review(spec, s.symptoms))
        assertFalse(review.getJSONObject(HOST).getBoolean("goal_verified"))
        assertEquals("wait", s.next(review).getJSONObject(HOST).getString("previous_decision"))
    }

    @Test fun deferredLearningWrongGapAndWrongGoalCannotEnterResearch() {
        val s = fixture(); val f = s.f
        val deferred = JSONObject(s.agenda.getJSONObject("body").getJSONObject(CollaborationLearningAgenda.KIND).toString())
        deferred.getJSONArray("options").getJSONObject(0).put("decision", "defer")
        val saved = f.accepted(f.publish(CollaborationLearningAgenda.KIND, deferred))
        assertEquals("rejected", f.publish(CollaborationSelfResearch.CYCLE, s.cycleSpec().put("agenda", f.ref(saved))).getString("status"))
        rejected { CollaborationSelfResearchWork.plan(s.record().copy(request = s.record().request.copy(goal = "Another goal")),
            listOf(s.work()), { f.workspace }, f.access()) }
        rejected { CollaborationSelfResearchWork.plan(s.record(), listOf(s.work()), { f.workspace }, f.access().copy(groupId = "other")) }
    }

    @Test fun recoveryPinsActionIdentityAndRejectsRenamedDuplicates() {
        val s = fixture(); val f = s.f; val work = s.work(); val record = s.record()
        val plan = CollaborationSelfResearchWork.plan(record, listOf(work), { f.workspace }, f.access())
        val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationSelfResearchWork.CLAIMS to plan.claims)))
        assertEquals(plan.claims, CollaborationSelfResearchWork.plan(restored, listOf(work), { f.workspace }, f.access()).claims)
        rejected { CollaborationSelfResearchWork.plan(restored, listOf(JSONObject(work.toString()).put("id", "renamed")), { f.workspace }, f.access()) }
        rejected { CollaborationSelfResearchWork.plan(restored, listOf(JSONObject(work.toString()).put("assignment", "Changed")), { f.workspace }, f.access()) }
        rejected { CollaborationSelfResearchWork.plan(restored, listOf(JSONObject(work.toString()).apply { remove(CollaborationSelfResearchWork.FIELD) }), { f.workspace }, f.access()) }
    }

    @Test fun ordinaryWorkHasNoWorkspaceIoAndMixedInvalidBatchDispatchesNothing() {
        val s = fixture(); val f = s.f
        val ordinary = JSONObject().put("id", "ordinary")
        assertSame(ordinary, CollaborationSelfResearchWork.plan(s.record(), listOf(ordinary), { error("Unexpected I/O") }, f.access()).work.single())
        val bad = s.work(id = "bad").apply { getJSONObject(CollaborationSelfResearchWork.FIELD).getJSONObject("cycle").put("sha256", "wrong") }
        val finished = s.completed(s.record(), "lead", s.report(listOf(s.work(), bad)), true)
        val next = CollaborationGoalLoop.advance(finished, "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        assertTrue(next.definition.members.none { CollaborationSelfResearchWork.TASK in it.context })
        assertEquals("{}", next.request.context[CollaborationSelfResearchWork.CLAIMS])
    }

    @Test fun goalLoopDispatchesAndCapturesRealTaskIdentityWithoutCertifyingImprovement() {
        val s = fixture(); val f = s.f
        val next = CollaborationGoalLoop.advance(s.completed(s.record(), "lead", s.report(listOf(s.work())), true),
            "lead", 1000, true, candidateWorkspace = { f.workspace })!!
        val worker = next.definition.members.single { CollaborationSelfResearchWork.TASK in it.context }
        assertTrue(isPersistedAgentTeamContextKey(CollaborationSelfResearchWork.TASK))
        val finished = s.completed(next, worker.memberId, "Saved hypothesis")
        val output = CollaborationSelfResearchWork.capture(finished, finished.events.mapNotNull { it.result })
        assertFalse(JSONObject(output).getJSONObject(worker.memberId).getBoolean("improvement_verified"))
        val restored = finished.copy(request = finished.request.copy(context = finished.request.context + (CollaborationSelfResearchWork.OUTCOMES to output)))
        assertEquals(output, CollaborationSelfResearchWork.capture(restored, finished.events.mapNotNull { it.result }))
    }

    @Test fun incrementalPlannerAddsResearchWhileUnrelatedTaskRemainsActive() {
        val s = fixture(); val f = s.f; val record = s.record()
        val source = record.definition.members.last().copy(instanceId = "source", context = record.definition.members.last().context +
            mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "source-work"))
        val waiting = source.copy(instanceId = "unrelated", context = source.context + (CollaborationGoalLoop.WORK_ID to "unrelated-work"))
        val initial = record.copy(definition = record.definition.copy(members = record.definition.members + source + waiting))
        val completed = s.completed(initial, "source", "New gap found")
        val planning = CollaborationLiveGraph.update(completed, setOf("source"), 1000, { f.workspace })
        val planner = planning.definition.members.single(CollaborationLiveGraph::planner)
        val expansion = JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Research now").put("work", JSONArray().put(s.work()))
        val next = CollaborationLiveGraph.update(s.completed(planning, planner.memberId, expansion.toString()), setOf("source", planner.memberId), 1100, { f.workspace })
        assertEquals(next.request.context[CollaborationLiveGraph.FEEDBACK].toString(), 1,
            next.definition.members.count { CollaborationSelfResearchWork.TASK in it.context })
        assertTrue(next.definition.members.any { it.memberId == "unrelated" })
    }

    @Test fun typedProtocolIncludesRecoveryAndNoFixedStageTermination() {
        assertTrue(CollaborationEvolutionContract.KINDS.containsAll(setOf(CollaborationSelfResearch.CYCLE, CollaborationSelfResearch.REVIEW)))
        assertTrue(CollaborationSelfResearchProtocol.instructions().contains("not a fixed stage/round/retry count"))
        assertTrue(CollaborationSelfResearchProtocol.rules().contains("New cycles may branch"))
    }

    @Test fun parallelCandidatesCanBothBeAdoptedButNoneCanBeSilentlyOmitted() {
        val s = fixture(); val f = s.f
        val first = s.retain(s.study()); val second = s.retain(s.study())
        val one = f.accepted(f.select(first)); val two = f.accepted(f.select(second))
        val spec = s.adoption(first, one)
        spec.getJSONArray("evaluations").put(JSONObject().put("result", f.ref(second.study.result)).put("lesson", f.ref(second.lesson)))
        val refs = JSONArray(first.study.observations.toString()).put(second.study.observations.getJSONObject(0))
        assertEquals("rejected", s.review(spec, refs).getString("status"))
        spec.getJSONArray("channels").put(f.ref(two))
        assertEquals(2, f.accepted(s.review(spec, refs)).getJSONObject(HOST).getJSONArray("channels").length())
    }

    @Test fun changedBottleneckBlocksNewWorkButCannotRewritePinnedCheckpoint() {
        val s = fixture(); val f = s.f; val record = s.record(); val work = s.work()
        val admitted = CollaborationSelfResearchWork.plan(record, listOf(work), { f.workspace }, f.access())
        val changed = JSONObject(s.gap.getJSONObject("body").getJSONObject("capability_gap").toString()).put("symptom", "New observed condition")
        f.accepted(f.publish("capability_gap", changed, previous = s.gap))
        rejected { CollaborationSelfResearchWork.plan(record, listOf(work), { f.workspace }, f.access()) }
        val pinned = record.copy(request = record.request.copy(context = record.request.context + (CollaborationSelfResearchWork.CLAIMS to admitted.claims)))
        assertEquals(admitted.claims, CollaborationSelfResearchWork.plan(pinned, listOf(work), { f.workspace }, f.access()).claims)
    }

    @Test fun cycleLineageCannotBeDiscardedOrMalformedIntoOrdinaryWork() {
        val s = fixture(); val f = s.f; val study = s.study()
        val value = JSONObject(study.idea.getJSONObject("body").getJSONObject("innovation").toString()).apply { remove(CollaborationSelfResearch.CYCLE) }
        assertEquals("rejected", f.publish("innovation", value, "author", previous = study.idea,
            parents = JSONArray().put(f.ref(s.opportunity))).getString("status"))
        rejected { CollaborationSelfResearchWork.plan(s.record(), listOf(s.work().put(CollaborationSelfResearchWork.FIELD, "invalid")), { f.workspace }, f.access()) }
    }
}
