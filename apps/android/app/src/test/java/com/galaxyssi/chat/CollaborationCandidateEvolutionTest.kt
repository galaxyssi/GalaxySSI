package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateEvolutionTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { check(!fail); this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private class Fixture {
        val rows = Rows()
        val evidenceRows = Rows()
        val ledger = CollaborationEvidenceLedger(evidenceRows)
        val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage)
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 20, "lead", "lead")
        val people = setOf("lead", "author", "editor", "reviewer")
        val criterion = JSONObject().put("id", "accuracy").put("requirement", "Documented accuracy").put("verification", "documentary")
            .put("status", "open").put("evidence_kind", "observed").put("evidence", JSONArray())
            .put("required_observations", JSONArray().put(JSONObject().put("origin", "android_cloud_tool").put("tool", "original_check")))
        val source = ledger.record(access.copy(nodeId = "source", personId = "author", round = 0), "invocation", "original_check", "{}", "{\"output\":17}", 1, 2)
        val target = publish(access.copy(nodeId = "seed", personId = "author", round = 0), candidate("a"))
        private var executionRound = 1L
        fun candidate(id: String) = JSONObject().put("id", id).put("kind", "candidate").put("title", id)
            .put("body", JSONObject().put("content", "Full original $id").put("candidate", JSONObject().put("operation", "propose")
                .put("rationale", "Alternative worth checking").put("criteria", JSONArray().put(criterion.getString("requirement")))))
        fun request(ref: JSONObject = target) = JSONObject().put("target", ref).put("criterion_id", "accuracy")
            .put("editor", "editor").put("reviewer", "reviewer")
        fun retry(plan: CollaborationCandidateEvolution.Plan, reviewer: String = "lead") = request().put("reviewer", reviewer)
            .put("retry_review", JSONObject().put("node_id", node(plan)).put("reason", "Read the original and publish the missing exact review"))
        fun plan(state: String = "[]", requests: JSONArray = JSONArray().put(request()), successes: Set<String> = emptySet(),
                 members: Set<String> = people) = CollaborationCandidateEvolution.plan(workspace, access, members,
            JSONArray().put(criterion), requests, state, successes) { "dispatch:$it" }
        fun task(plan: CollaborationCandidateEvolution.Plan) = JSONObject(CollaborationCandidateEvolution.taskContext(plan.work.single()).getValue(CollaborationCandidateEvolution.TASK))
        fun node(plan: CollaborationCandidateEvolution.Plan) = CollaborationCandidateVerificationState.read(plan.state).getJSONObject(0).getString("node_id")
        fun review(task: JSONObject, outcome: String = "supported", receipt: JSONObject = source) = JSONObject()
            .put("id", "review-${task.getJSONObject("target").getInt("revision")}").put("kind", "candidate_event").put("title", "Exact documentary review")
            .put("observations", JSONArray().put(receipt)).put("body", JSONObject().put("candidate_event", JSONObject().put("operation", "review")
                .put("targets", JSONArray().put(task.getJSONObject("target"))).put("criterion", "Documented accuracy")
                .put("check", "Compare the saved original output and exact candidate").put("rationale", "Documentary finding, not empirical truth")
                .put("outcome", outcome).put("unresolved", JSONArray().apply { if (outcome != "supported") put("Candidate still needs work") })))
        fun repair(task: JSONObject) = candidate("ignored").put("object_id", task.getJSONObject("target").getString("object_id"))
            .put("base_revision", task.getJSONObject("target").getInt("revision")).put("parents", JSONArray().put(task.getJSONObject("target")))
            .put("observations", JSONArray().put(source)).apply {
                getJSONObject("body").put("content", "Repaired original")
                getJSONObject("body").getJSONObject("candidate").put("operation", "revise").put("basis", task.getJSONObject("basis"))
            }
        fun execute(plan: CollaborationCandidateEvolution.Plan, outcome: String = "supported"): JSONObject {
            val task = task(plan)
            val item = if (task.getString("operation") == "review") review(task, outcome) else repair(task)
            return publish(access.copy(nodeId = node(plan), personId = task.getString("member"), round = ++executionRound), item, task)
        }
        fun publish(who: CollaborationWorkspaceAccess, item: JSONObject, task: JSONObject? = null): JSONObject {
            if (item.optString("kind") == "candidate_event" &&
                item.getJSONObject("body").getJSONObject("candidate_event").optString("operation") == "review")
                assertNull(ledger.readPage(who, source.getString("evidence_id"), source.getString("sha256"))!!.next)
            val result = workspace.publish(who, raw(item), candidateTask = task)
            assertEquals(result.toString(), "recorded", result.getString("status"))
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        fun assessment(requests: JSONArray = JSONArray()) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
            .put("summary", "Continue the exact candidate checks").put("decision", "continue").put("criteria", JSONArray().put(criterion))
            .put("work", JSONArray()).put("blockers", JSONArray()).put(CollaborationCandidateEvolution.REQUESTS, requests)
        fun blockedAssessment(kind: String = "resource") = assessment().put("decision", "blocked").put("blockers", JSONArray().put(
            JSONObject().put("id", "unrelated-lab").put("kind", kind).put("reason", "An unrelated physical experiment needs a lab")
                .put("resume_when", "Authorized lab becomes available").put("alternatives", JSONArray().put(JSONObject()
                    .put("option", "Available documentary sources").put("status", "not_applicable")
                    .put("result", "Sources cannot replace the physical experiment").put("evidence", JSONArray().put("saved-resource-check"))))))
        fun resolvedBlocker(record: AgentTeamExecutionRecord, assessment: JSONObject) = record.copy(
            request = record.request.copy(context = record.request.context + (CollaborationGoalLoop.FINISHED_WORK to
                JSONArray().put(CollaborationResourceRecovery.workId(assessment.getJSONArray("blockers").getJSONObject(0))).toString())))
        fun record(): AgentTeamExecutionRecord {
            val members = people.map { AgentTeamMember("provider", instanceId = it,
                deliveryMode = if (it == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                context = mapOf("collaboration_group_id" to "group")) }
            val definition = AgentTeamDefinition("team", "provider", CollaborationGoalLoop.initial(members, "Goal"), primaryInstanceId = "lead")
            val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = "Goal", context = mapOf(
                CollaborationGoalLoop.CRITERIA to JSONArray().put(criterion).toString(), CollaborationGoalLoop.ROUND to "2", CollaborationGoalLoop.HOST_ACCEPTANCE to "1"))
            return complete(AgentTeamExecutionRecord(definition, request), assessment(JSONArray().put(request())))
        }
        fun complete(record: AgentTeamExecutionRecord, assessment: JSONObject = assessment(), child: String? = null): AgentTeamExecutionRecord {
            val ids = listOfNotNull(child, record.definition.primaryMemberId)
            val events = ids.mapIndexed { index, id -> AgentSubagentEvent((index + 1).toLong(), "run", id,
                AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
                result = AgentSubagentChildResult("run", id, "run", 1, AgentSubagentStatus.SUCCEEDED,
                    if (id == record.definition.primaryMemberId) assessment.toString() else "Host publication recorded",
                    provenance = AgentSubagentProvenance("agent-team", record.definition.teamId, "run",
                        mapOf("instance_id" to id, "agent_id" to record.definition.members.single { it.memberId == id }.agentId)))) }
            return record.copy(events = events + AgentSubagentEvent((events.size + 1).toLong(), "run",
                kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED))
        }
    }

    @Test fun actualGoalLoopSchedulesReviewRepairAndFreshReviewThenStopsAutomaticWork() {
        val f = Fixture()
        val alternative = f.publish(f.access.copy(nodeId = "alternative", personId = "editor", round = 0), f.candidate("alternative"))
        var record = f.record()
        val versions = mutableListOf<Int>()
        listOf("review", "revise", "review").forEachIndexed { index, operation ->
            record = requireNotNull(CollaborationGoalLoop.advance(record, record.definition.primaryMemberId, 100_000L + index, true,
                candidateWorkspace = { f.workspace }))
            val member = record.definition.members.single { it.context[CollaborationCandidateEvolution.TASK] != null }
            val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
            assertEquals(operation, task.getString("operation"))
            versions += task.getJSONObject("target").getInt("revision")
            val item = if (operation == "review") f.review(task, if (index == 0) "refuted" else "supported") else f.repair(task)
            f.publish(f.access.copy(nodeId = member.memberId, personId = task.getString("member"),
                round = record.request.context.getValue(CollaborationGoalLoop.ROUND).toString().toLong()), item, task)
            assertEquals(1, record.definition.members.count { it.deliveryMode == AgentDeliveryMode.OBSERVE })
            record = f.complete(record, child = member.memberId)
        }
        assertEquals(listOf(1, 1, 2), versions)
        val settled = requireNotNull(CollaborationGoalLoop.advance(record, record.definition.primaryMemberId, 200_000, true, candidateWorkspace = { f.workspace }))
        assertFalse(CollaborationCandidateEvolution.pending(settled.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()))
        assertTrue(settled.definition.members.none { it.context[CollaborationCandidateEvolution.TASK] != null })
        assertTrue(f.workspace.isCurrent(f.access, alternative.getString("object_id"), 1))
        assertEquals("member_reported_not_verified", f.workspace.read(f.access, f.target.getString("object_id"), 2)!!.getString("evidence_state"))
    }

    @Test fun supportedReviewStopsAtOneMemberAssessmentWithoutCertification() {
        val f = Fixture()
        val first = f.plan()
        f.execute(first)
        val next = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(next.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(next.state))
        assertTrue(next.feedback.contains("not host verified"))
        assertEquals("requires_independent_review", f.workspace.read(f.access, f.target.getString("object_id"), 1)!!.getJSONObject("host_candidate").getString("verification_state"))
    }

    @Test fun pendingRepairAndRecheckAdvanceAutomaticallyWithoutErasingActualBlockers() {
        listOf("resource", "permission").forEach { kind ->
            val f = Fixture()
            val blocked = f.blockedAssessment(kind)
            var record = f.resolvedBlocker(f.record(), blocked)
            val originalCriteria = record.request.context.getValue(CollaborationGoalLoop.CRITERIA).toString()
            listOf("review", "revise", "review").forEachIndexed { index, operation ->
                record = requireNotNull(CollaborationGoalLoop.advance(record, record.definition.primaryMemberId,
                    100_000L + index, false, candidateWorkspace = { f.workspace }))
                if (index > 0) assertEquals(blocked.toString(), record.request.context[CollaborationGoalLoop.PREVIOUS])
                val member = record.definition.members.single { it.context[CollaborationCandidateEvolution.TASK] != null }
                val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
                assertEquals(operation, task.getString("operation"))
                val item = if (operation == "review") f.review(task, if (index == 0) "refuted" else "supported") else f.repair(task)
                f.publish(f.access.copy(nodeId = member.memberId, personId = task.getString("member"),
                    round = record.request.context.getValue(CollaborationGoalLoop.ROUND).toString().toLong()), item, task)
                record = f.complete(record, blocked, member.memberId)
                val finished = CollaborationGoalLoop.finishedWork(record)
                assertEquals("blocked", CollaborationGoalLoop.disposition(blocked.toString(), originalCriteria, finished))
                assertEquals("continue", CollaborationGoalLoop.disposition(blocked.toString(), originalCriteria, finished,
                    candidateState = record.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()))
            }
            val settled = requireNotNull(CollaborationGoalLoop.advance(record, record.definition.primaryMemberId,
                200_000, false, candidateWorkspace = { f.workspace }))
            val state = settled.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()
            assertFalse(CollaborationCandidateEvolution.pending(state))
            assertTrue(settled.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE })
            assertEquals(originalCriteria, settled.request.context[CollaborationGoalLoop.CRITERIA])
            assertEquals(blocked.toString(), settled.request.context[CollaborationGoalLoop.PREVIOUS])
            assertEquals("blocked", CollaborationGoalLoop.disposition(blocked.toString(), originalCriteria,
                CollaborationGoalLoop.finishedWork(settled), candidateState = state))
            assertNull(CollaborationGoalLoop.advance(f.complete(settled, blocked), settled.definition.primaryMemberId,
                300_000, false, candidateWorkspace = { error("Settled blockers must not restart candidate work") }))
        }
    }

    @Test fun pendingCycleWithoutSuccessfulPublicationSettlesWithoutBypassingBlocker() {
        val f = Fixture()
        val blocked = f.blockedAssessment()
        val scheduled = requireNotNull(CollaborationGoalLoop.advance(f.resolvedBlocker(f.record(), blocked), "lead",
            100_000, false, candidateWorkspace = { f.workspace }))
        val member = scheduled.definition.members.single { it.context[CollaborationCandidateEvolution.TASK] != null }
        val settled = requireNotNull(CollaborationGoalLoop.advance(f.complete(scheduled, blocked, member.memberId),
            scheduled.definition.primaryMemberId, 200_000, false, candidateWorkspace = { f.workspace }))
        assertFalse(CollaborationCandidateEvolution.pending(settled.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()))
        assertTrue(settled.definition.members.none { it.context[CollaborationCandidateEvolution.TASK] != null })
        assertEquals(blocked.toString(), settled.request.context[CollaborationGoalLoop.PREVIOUS])
        assertTrue(settled.request.context[CollaborationCandidateEvolution.FEEDBACK].toString().contains("Completed review has no committed publication"))
        assertNull(CollaborationGoalLoop.advance(f.complete(settled, blocked), settled.definition.primaryMemberId, 300_000, false,
            candidateWorkspace = { error("No feasible cycle remains") }))
    }

    @Test fun malformedPreservedCriteriaRetainExactContractAndDispatchNothing() {
        val f = Fixture()
        val corrupt = listOf("not-json", "[7]", JSONArray().put(f.criterion).put(f.criterion).toString(),
            JSONArray().put(JSONObject(f.criterion.toString()).put("requirement", "")).toString(),
            JSONArray().put(JSONObject(f.criterion.toString()).put("verification", "invented")).toString(),
            JSONArray().put(JSONObject(f.criterion.toString()).put("required_observations", JSONObject.NULL)).toString())
        val pendingState = f.plan().state
        corrupt.forEach { prior -> listOf(false, true).forEach { pending ->
            val state = if (pending) pendingState else "[]"
            val report = f.blockedAssessment().put(CollaborationCandidateEvolution.REQUESTS,
                if (pending) JSONArray() else JSONArray().put(f.request()))
                .put("work", JSONArray().put(JSONObject().put("id", "ordinary-work").put("member", "editor")
                    .put("stage", "EXPLORE").put("assignment", "Ordinary work must also wait for contract recovery")))
                .put("recruit", JSONArray().put(JSONObject().put("id", "new-person")))
            val record = f.record().let { it.copy(request = it.request.copy(context = it.request.context + mapOf(
                CollaborationGoalLoop.CRITERIA to prior, CollaborationCandidateEvolution.STATE to state))) }
            val before = f.rows.values.toMap()
            val completed = f.complete(record, report)
            assertNull(CollaborationGoalLoop.advance(completed, "lead", 100_000, false,
                recruitmentNames = { error("Corrupt contracts cannot trigger recruitment") },
                candidateWorkspace = { error("Corrupt contracts cannot reach candidate planning") }))
            assertEquals(prior, completed.request.context[CollaborationGoalLoop.CRITERIA])
            assertEquals(state, completed.request.context[CollaborationCandidateEvolution.STATE])
            assertEquals(before, f.rows.values)
            assertNull(CollaborationGoalLoop.advance(f.complete(completed), completed.definition.primaryMemberId,
                200_000, false, candidateWorkspace = { error("A fresh model assessment cannot replace corrupt preserved criteria") }))
        } }
    }

    @Test fun corruptCriteriaCannotYieldAchievedOrHistoricalCompletionEvenWithMatchingReceiptFlag() {
        val f = Fixture()
        val report = f.assessment().put("decision", "achieved")
        report.getJSONArray("criteria").getJSONObject(0).put("status", "met").put("evidence", JSONArray().put("recorded"))
        listOf("not-json", "[7]", JSONArray().put(f.criterion).put(f.criterion).toString()).forEach { prior ->
            assertEquals("blocked", CollaborationGoalLoop.disposition(report.toString(), prior,
                acceptanceVerified = true, allowUnverifiedHistory = true))
        }
    }

    @Test fun validEmptyInitialContractCanStillEstablishCriteria() {
        val f = Fixture()
        val record = f.record().let { it.copy(request = it.request.copy(context = it.request.context + (CollaborationGoalLoop.CRITERIA to "[]"))) }
        val next = requireNotNull(CollaborationGoalLoop.advance(f.complete(record), "lead", 100_000, false))
        assertEquals(JSONArray().put(f.criterion).toString(), next.request.context[CollaborationGoalLoop.CRITERIA])
        assertTrue(next.request.context[CollaborationGoalLoop.ACCEPTANCE_FEEDBACK].toString().contains("goal-coverage-source.v1"))
    }

    @Test fun terminalIntakeSurvivesUnavailableWorkspaceWithoutLosingRequestedTargets() {
        val f = Fixture()
        val next = requireNotNull(CollaborationGoalLoop.advance(f.record(), "lead", 100_000, true,
            candidateWorkspace = { error("Storage is temporarily unavailable") }))
        val state = next.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()
        assertEquals(f.target.getString("object_id"), CollaborationCandidateVerificationState.checkpoint(state)
            .pendingRequests.getJSONObject(0).getJSONObject("target").getString("object_id"))
        assertTrue(next.definition.members.none { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
        val resumed = requireNotNull(CollaborationGoalLoop.advance(f.complete(next), next.definition.primaryMemberId,
            200_000, true, candidateWorkspace = { f.workspace }))
        assertEquals(1, resumed.definition.members.count { it.context.containsKey(CollaborationCandidateEvolution.TASK) })
    }

    @Test fun repeatedApplicableRefutationsKeepImprovingWithoutARepairCountLimit() {
        val f = Fixture()
        var plan = f.plan()
        val dispatched = hashSetOf<String>()
        repeat(9) {
            assertTrue(dispatched.add(f.node(plan)))
            f.execute(plan, "refuted")
            plan = f.plan(plan.state, JSONArray(), setOf(f.node(plan)))
            assertEquals(1, plan.work.size)
            assertTrue(CollaborationCandidateEvolution.pending(plan.state))
            assertFalse(plan.feedback.contains("supported"))
        }
        assertEquals("revise", f.task(plan).getString("operation"))
        assertTrue(f.node(plan) !in dispatched)
    }

    @Test fun absentOrFailedPublicationStopsWithoutAutomaticRetry() {
        val f = Fixture()
        val first = f.plan()
        val done = f.plan(first.state, JSONArray())
        assertFalse(done.error)
        assertTrue(done.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(done.state))
        assertTrue(f.plan(done.state).work.isEmpty())
    }

    @Test fun notTestedDoesNotTriggerAutomaticExperimentOrRepair() {
        val f = Fixture()
        val first = f.plan(); f.execute(first, "not_tested")
        val done = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(done.work.isEmpty())
        assertTrue(done.feedback.contains("not_tested"))
    }

    @Test fun physicalSimulationAndUnqualifiedSourceContractsAreNotAutomaticallyValidated() {
        listOf("physical", "computational").forEach { type ->
            val f = Fixture(); f.criterion.put("verification", type).put("evidence_kind", "simulation")
            val plan = f.plan()
            assertFalse(plan.error)
            assertTrue(plan.work.isEmpty())
            assertEquals(1, CollaborationCandidateVerificationState.checkpoint(plan.state).pendingRequests.length())
        }
        val f = Fixture(); f.criterion.remove("required_observations")
        assertTrue(f.plan().work.isEmpty())
    }

    @Test fun selfReviewEditorReviewAndUnknownMemberAreRejectedBeforeDispatch() {
        listOf("author", "editor", "stranger").forEach { reviewer ->
            val f = Fixture()
            val plan = f.plan(requests = JSONArray().put(f.request().put("reviewer", reviewer)))
            assertTrue(plan.work.isEmpty())
            assertEquals(1, CollaborationCandidateVerificationState.checkpoint(plan.state).pendingRequests.length())
        }
    }

    @Test fun moreThanTwoDistinctCandidatesArePlannedWithoutAnArbitraryLimit() {
        val f = Fixture()
        val requests = JSONArray().put(f.request())
        repeat(4) { index ->
            val target = f.publish(f.access.copy(nodeId = "seed-$index", personId = "author", round = 0), f.candidate("extra-$index"))
            requests.put(f.request(target))
        }
        val plan = f.plan(requests = requests)
        assertFalse(plan.error)
        assertEquals(5, plan.work.size)
        assertEquals(5, CollaborationCandidateVerificationState.read(plan.state).length())
    }

    @Test fun failedEnrollmentRemainsPendingWithoutBlockingAnotherRoute() {
        val f = Fixture()
        val other = f.publish(f.access.copy(nodeId = "other", personId = "author", round = 0), f.candidate("other"))
        val plan = f.plan(requests = JSONArray().put(f.request().put("reviewer", "author")).put(f.request(other)))
        assertFalse(plan.error)
        assertEquals(1, plan.work.size)
        assertEquals(1, CollaborationCandidateVerificationState.checkpoint(plan.state).pendingRequests.length())
        assertTrue(CollaborationCandidateEvolution.pending(plan.state))
    }

    @Test fun explicitNewRevisionCanReopenAPreviouslySettledRoute() {
        val f = Fixture(); val first = f.plan(); f.execute(first, "supported")
        val settled = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        val update = f.candidate("ignored").put("object_id", f.target.getString("object_id")).put("base_revision", 1)
            .put("parents", JSONArray().put(f.target)).put("observations", JSONArray().put(f.source))
        update.getJSONObject("body").getJSONObject("candidate").put("operation", "revise")
        val revised = f.publish(f.access.copy(nodeId = "manual-improvement", personId = "editor", round = 3), update)
        val reopened = f.plan(settled.state, JSONArray().put(f.request(revised)))
        assertEquals(1, reopened.work.size)
        assertNotEquals(f.node(first), f.node(reopened))
        assertEquals(2, f.task(reopened).getJSONObject("target").getInt("revision"))
        assertEquals(1, CollaborationCandidateVerificationState.read(reopened.state).getJSONObject(0).getJSONArray("prior_settlements").length())
    }

    @Test fun twoAlternativesReceiveIndependentBoundedJobsWithoutRetirement() {
        val f = Fixture()
        val b = f.publish(f.access.copy(nodeId = "second", personId = "editor", round = 0), f.candidate("b"))
        val plan = f.plan(requests = JSONArray().put(f.request()).put(f.request(b)))
        assertFalse(plan.feedback, plan.error)
        assertEquals(2, plan.work.size)
        assertEquals(2, plan.work.map { it.getString("id") }.toSet().size)
        assertTrue(f.workspace.isCurrent(f.access, b.getString("object_id"), 1))
    }

    @Test fun wrongToolOrFailedReceiptCannotPublishAnAssignedReview() {
        val f = Fixture()
        val first = f.plan()
        val task = f.task(first)
        val wrong = f.ledger.record(f.access.copy(nodeId = "wrong-source", round = 0), "wrong", "peer_document", "{}", "{}", 1, 2)
        val who = f.access.copy(nodeId = f.node(first), personId = "reviewer")
        val result = f.workspace.publish(who, raw(f.review(task, receipt = wrong)), candidateTask = task)
        assertEquals("rejected", result.getString("status"))
        assertTrue(f.workspace.publicationRevisions(f.access, who.nodeId).isEmpty())
        val done = f.plan(first.state, JSONArray(), setOf(who.nodeId))
        assertFalse(CollaborationCandidateEvolution.pending(done.state))
    }

    @Test fun assignedTaskCannotMutateAlternativesAndRejectionIsAtomic() {
        val f = Fixture()
        val plan = f.plan(); val task = f.task(plan)
        val who = f.access.copy(nodeId = f.node(plan), personId = "reviewer")
        val result = f.workspace.publish(who, raw(f.review(task), f.candidate("unassigned")), candidateTask = task)
        assertEquals("rejected", result.getString("status"))
        assertEquals(1, f.workspace.browse(f.access).revisions.size)
        assertNotNull(f.workspace.replayCandidateTask(who, task))
    }

    @Test fun exactReplayAfterPublishedRepairDoesNotReexecuteOrRequireOldHead() {
        val f = Fixture()
        val first = f.plan(); f.execute(first, "refuted")
        val repair = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        val task = f.task(repair); val revision = f.execute(repair)
        val who = f.access.copy(nodeId = f.node(repair), personId = "editor")
        val before = f.rows.values.toMap()
        val restored = requireNotNull(f.workspace.replayCandidateTask(who, task))
        assertEquals(revision.getString("sha256"), restored.getJSONObject("workspace_receipt").getJSONArray("revisions").getJSONObject(0).getString("sha256"))
        assertEquals(before, f.rows.values)
        val changed = JSONObject(task.toString()).put("member", "lead")
        assertTrue(runCatching { f.workspace.replayCandidateTask(who.copy(personId = "lead"), changed) }.isFailure)
    }

    @Test fun staleTargetsFailBeforeDispatchAndAgainAtPublication() {
        val f = Fixture()
        val first = f.plan(); val task = f.task(first)
        val update = f.candidate("ignored").put("object_id", f.target.getString("object_id")).put("base_revision", 1)
            .put("parents", JSONArray().put(f.target)).put("observations", JSONArray().put(f.source))
        update.getJSONObject("body").getJSONObject("candidate").put("operation", "revise")
        f.publish(f.access.copy(nodeId = "concurrent-editor", personId = "editor", round = 1), update)
        val who = f.access.copy(nodeId = f.node(first), personId = "reviewer")
        assertTrue(runCatching { CollaborationCandidateEvolution.checkTask(f.workspace, who, task) }.isFailure)
        assertEquals("rejected", f.workspace.publish(who, raw(f.review(task)), candidateTask = task).getString("status"))
        assertTrue(f.plan(first.state, JSONArray()).work.isEmpty())
    }

    @Test fun missingEvidenceAfterReviewCannotTriggerRepair() {
        val f = Fixture()
        val first = f.plan(); f.execute(first, "refuted")
        f.evidenceRows.values.clear()
        val done = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(done.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(done.state))
    }

    @Test fun malformedPlanDoesNotConsumeCycleStateOrDispatchPartialWork() {
        val f = Fixture()
        val record = f.record()
        val assessment = f.assessment(JSONArray().put(f.request())).put("work", JSONArray().put(JSONObject()
            .put("id", "bad").put("member", "editor").put("stage", "REVISE").put("assignment", "Bad dependency")
            .put("depends_on", JSONArray().put("missing"))))
        val next = requireNotNull(CollaborationGoalLoop.advance(f.complete(record, assessment), "lead", 100_000, true, candidateWorkspace = { f.workspace }))
        assertEquals("[]", next.request.context[CollaborationCandidateEvolution.STATE])
        assertTrue(next.definition.members.none { it.context[CollaborationCandidateEvolution.TASK] != null })
        assertTrue(next.request.context[CollaborationWorkGraph.FEEDBACK].toString().isNotBlank())
    }

    @Test fun reservedTaskFieldsAndWorkIdsCannotBeSuppliedByCoordinator() {
        listOf("id", "candidate_task").forEach { field ->
            val f = Fixture(); val record = f.record()
            val work = JSONObject().put("id", "work").put("member", "editor").put("stage", "REVISE").put("assignment", "A request")
            if (field == "id") work.put("id", "candidate-cycle:forged") else work.put(field, JSONObject())
            val next = requireNotNull(CollaborationGoalLoop.advance(f.complete(record, f.assessment().put("work", JSONArray().put(work))),
                "lead", 100_000, true, candidateWorkspace = { f.workspace }))
            assertTrue(next.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE })
        }
    }

    @Test fun ancestrySurvivesCopiesAndPreviousVersionsThatDropParents() {
        val f = Fixture()
        val delivery = JSONObject().put("id", "delivery").put("kind", "artifact").put("title", "Delivery")
            .put("body", JSONObject().put("content", "Derived from candidate")).put("parents", JSONArray().put(f.target))
        val first = f.publish(f.access.copy(nodeId = "delivery", personId = "editor", round = 1), delivery)
        val update = JSONObject(delivery.toString()).put("object_id", first.getString("object_id")).put("base_revision", 1).put("parents", JSONArray())
        val second = f.publish(f.access.copy(nodeId = "copy-editor", personId = "lead", round = 2), update)
        assertEquals(setOf("author", "editor", "lead"), f.workspace.contributorIds(f.access, second))
        val key = f.rows.values.keys.single { it.contains(":revision:${f.target.getString("object_id")}:1") }
        f.rows.values.remove(key)
        assertTrue(runCatching { f.workspace.contributorIds(f.access, second) }.isFailure)
    }

    @Test fun goalAcceptanceRejectsCandidateAncestorReviewingCopiedDelivery() {
        val f = Fixture()
        val mappingBody = JSONObject().put("format", CollaborationSemanticGoalCoverage.FORMAT)
            .put("goal_sha256", CollaborationSemanticGoalCoverage.source("Goal").getString("goal_sha256"))
            .put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(f.criterion)))
            .put("segments", JSONArray().put(JSONObject().put("id", "source-1").put("criterion_ids", JSONArray().put("accuracy"))
                .put("rationale", "Preserves the requested documentary goal")))
        val mapping = f.publish(f.access.copy(nodeId = "mapping", personId = "editor", round = 1), JSONObject()
            .put("id", "mapping").put("kind", "artifact").put("title", "Goal coverage")
            .put("body", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, mappingBody)))
        val coverageReview = f.publish(f.access.copy(nodeId = "coverage-review", personId = "reviewer", round = 2), JSONObject()
            .put("id", "coverage-review").put("kind", "acceptance_review").put("title", "Coverage review")
            .put("parents", JSONArray().put(mapping)).put("body", JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW,
                JSONObject().put("target", mapping).put("verdict", "supported").put("rationale", "Independent source coverage")
                    .put("unresolved", JSONArray()).put("segments", JSONArray().put(JSONObject().put("id", "source-1")
                        .put("criterion_ids", JSONArray().put("accuracy")).put("verdict", "supported")
                        .put("rationale", "The original outcome remains intact").put("unresolved", JSONArray()))))))
        val delivery = f.publish(f.access.copy(nodeId = "delivery", personId = "editor", round = 1), JSONObject()
            .put("id", "delivery").put("kind", "artifact").put("title", "Delivery").put("body", JSONObject().put("content", "Document"))
            .put("parents", JSONArray().put(f.target)).put("observations", JSONArray().put(f.source)))
        fun assessment(reviewer: String, id: String): JSONObject {
            val reader = f.access.copy(nodeId = id, personId = reviewer, round = 2)
            var offset: Int? = 0
            while (offset != null) offset = requireNotNull(f.ledger.readPage(reader, f.source.getString("evidence_id"),
                f.source.getString("sha256"), offset)).next
            val review = f.publish(reader, JSONObject().put("id", id)
                .put("kind", "acceptance_review").put("title", "Review").put("parents", JSONArray().put(delivery))
                .put("observations", JSONArray().put(f.source)).put("body", JSONObject().put("acceptance_review", JSONObject()
                    .put("criterion_id", "accuracy").put("requirement", "Documented accuracy").put("target", delivery)
                    .put("verdict", "supported").put("rationale", "Exact document assessed").put("unresolved", JSONArray()))))
            return f.assessment().put("decision", "achieved").put("criteria", JSONArray().put(JSONObject(f.criterion.toString())
                .put("status", "met").put("evidence", JSONArray().put("Original output")).put("delivery", delivery).put("review", review)))
                .put(CollaborationSemanticGoalCoverage.FIELD, JSONObject().put("mapping", mapping).put("review", coverageReview))
        }
        val acceptance = CollaborationGoalAcceptance(f.workspace, f.ledger)
        val bad = acceptance.evaluate(f.access, assessment("author", "ancestor-review").toString(), JSONArray().put(f.criterion).toString(), "Goal")
        assertFalse(bad.accepted)
        assertTrue(bad.feedback.contains("ancestor"))
        assertTrue(acceptance.evaluate(f.access, assessment("reviewer", "independent-review").toString(), JSONArray().put(f.criterion).toString(), "Goal").accepted)
    }

    @Test fun cancellationAndBackoffStillPreventAutomaticDispatch() {
        val f = Fixture()
        val record = f.record()
        val cancelled = record.copy(events = record.events + AgentSubagentEvent(99, "run", kind = "cancelled", runStatus = AgentSubagentRunStatus.CANCELLED))
        assertNull(CollaborationGoalLoop.advance(cancelled, "lead", 100_000, true, candidateWorkspace = { f.workspace }))
        assertNull(CollaborationGoalLoop.advance(record.copy(request = record.request.copy(context = record.request.context +
            (CollaborationGoalLoop.RETRY_AT to "200000"))), "lead", 100_000, false, candidateWorkspace = { f.workspace }))
    }

    @Test fun pendingCycleUnderBlockerCannotBypassCancellationOrBackoff() {
        val f = Fixture()
        val blocked = f.blockedAssessment()
        val record = f.resolvedBlocker(f.complete(f.record(), blocked), blocked).let {
            it.copy(request = it.request.copy(context = it.request.context + (CollaborationCandidateEvolution.STATE to f.plan().state)))
        }
        val cancelled = record.copy(events = record.events + AgentSubagentEvent(99, "run", kind = "cancelled", runStatus = AgentSubagentRunStatus.CANCELLED))
        assertNull(CollaborationGoalLoop.advance(cancelled, "lead", 100_000, true,
            candidateWorkspace = { error("Cancelled runs must not plan pending work") }))
        val backoff = record.copy(request = record.request.copy(context = record.request.context + (CollaborationGoalLoop.RETRY_AT to "200000")))
        assertNull(CollaborationGoalLoop.advance(backoff, "lead", 100_000, false,
            candidateWorkspace = { error("Pending work must respect backoff") }))
    }

    @Test fun schemaAndControllerPromptsExposeBoundedCycleWithoutCertification() {
        assertTrue(CollaborationGoalLoop.instructions().contains("candidate_cycles"))
        assertTrue(CollaborationResearchArtifact.instructions(CollaborationResearchStage.REVISE).contains("body.candidate.basis"))
        assertTrue(CollaborationResearchArtifact.instructions(CollaborationResearchStage.REVISE).contains("NOT into resolves"))
        assertTrue(CollaborationCandidateEvolution.instructions().contains("simulation never satisfies physical"))
        val f = Fixture()
        assertTrue(f.plan().work.single().getString("assignment").contains("Use resolves=[]"))
        val claimed = f.assessment(JSONArray().put(f.request())).put("decision", "achieved")
        assertEquals("continue", CollaborationGoalLoop.disposition(claimed.toString(), acceptanceVerified = true))
    }

    @Test fun pendingCyclesPreventAnOtherwiseMatchingHostReceiptFromEndingTheGoal() {
        val f = Fixture()
        val record = f.record()
        val result = record.events.first().result!!
        val receipt = CollaborationAcceptanceReceipt(AgentNativeJsonCodec.sha256(result.output),
            AgentNativeJsonCodec.sha256(record.request.context.getValue(CollaborationGoalLoop.CRITERIA).toString()),
            AgentNativeJsonCodec.sha256("Goal"), "run", "turn", "lead", true, "Fixture host receipt", 1)
        val accepted = result.copy(collaborationAcceptance = receipt)
        assertTrue(record.acceptanceVerified(accepted))
        val pending = record.copy(request = record.request.copy(context = record.request.context +
            (CollaborationCandidateEvolution.STATE to f.plan().state)))
        assertFalse(pending.acceptanceVerified(accepted))
        val corrupt = record.copy(request = record.request.copy(context = record.request.context +
            (CollaborationCandidateEvolution.STATE to "[{\"phase\":\"done\"}]")))
        assertFalse(corrupt.acceptanceVerified(accepted))
    }

    @Test fun taskScopeAndMemberCannotBeBorrowedAcrossRunsOrPeople() {
        val f = Fixture(); val plan = f.plan(); val task = f.task(plan)
        val who = f.access.copy(nodeId = f.node(plan), personId = "reviewer")
        listOf(who.copy(groupId = "other"), who.copy(runId = "other"), who.copy(turnId = "other"), who.copy(personId = "editor")).forEach {
            assertTrue(runCatching { CollaborationCandidateEvolution.checkTask(f.workspace, it, task) }.isFailure)
        }
        val altered = JSONObject(task.toString())
        altered.getJSONObject("target").put("sha256", "0".repeat(64))
        assertTrue(runCatching { CollaborationCandidateEvolution.checkTask(f.workspace, who, altered) }.isFailure)
    }

    @Test fun memberRemovalStopsPendingCycleWithoutSubstitutionOrRepair() {
        val f = Fixture(); val first = f.plan(); f.execute(first, "refuted")
        val stopped = f.plan(first.state, JSONArray(), setOf(f.node(first)), f.people - "reviewer")
        assertTrue(stopped.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(stopped.state))
        assertTrue(stopped.feedback.contains("unavailable"))
    }

    @Test fun strengthenedSourceContractInvalidatesTheAutomaticCycle() {
        val f = Fixture(); val first = f.plan(); f.execute(first)
        f.criterion.getJSONArray("required_observations").put(JSONObject().put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution"))
        val stopped = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(stopped.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(stopped.state))
        assertTrue(stopped.feedback.contains("contract changed"))
    }

    @Test fun succeededMemberTextWithoutHostPublicationCannotAdvanceToRepair() {
        val f = Fixture(); val first = f.plan()
        val stopped = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(stopped.work.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(stopped.state))
        assertTrue(stopped.feedback.contains("Completed review has no committed publication"))
    }

    @Test fun completedUnpublishedReviewCanBeExplicitlyReassignedWithoutChangingItsTarget() {
        val f = Fixture(); val first = f.plan()
        val settled = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        assertTrue(JSONObject(CollaborationCandidateEvolution.summary(settled.state)).getJSONArray("recent_cycles")
            .getJSONObject(0).getBoolean("retryable_review"))
        assertTrue(f.plan(settled.state).work.isEmpty())
        val retry = f.retry(first)
        val next = f.plan(settled.state, JSONArray().put(retry))
        assertFalse(next.feedback, next.error)
        assertEquals("lead", f.task(next).getString("member"))
        assertEquals(f.task(first).getJSONObject("target").toString(), f.task(next).getJSONObject("target").toString())
        assertNotEquals(f.node(first), f.node(next))
        val saved = CollaborationCandidateVerificationState.read(next.state).getJSONObject(0)
        assertEquals(f.node(first), saved.getJSONArray("prior_settlements").getJSONObject(0).getString("node_id"))
        assertEquals(retry.getJSONObject("retry_review").toString(), f.task(next).getJSONObject("review_reassignment").toString())
        f.execute(next)
        val done = f.plan(next.state, JSONArray(), setOf(f.node(next)))
        assertFalse(CollaborationCandidateEvolution.pending(done.state))
        assertTrue(done.feedback.contains("not host verified"))
        assertTrue(f.workspace.isCurrent(f.access, f.target.getString("object_id"), 1))
    }

    @Test fun sameVersionReassignmentsKeepUniqueAttemptsAndConsumedRequestsDoNotLoop() {
        val f = Fixture(); var active = f.plan()
        val ids = linkedSetOf(f.node(active))
        val requests = mutableListOf<JSONObject>()
        repeat(12) { index ->
            val settled = f.plan(active.state, JSONArray(), setOf(f.node(active)))
            val retry = f.retry(active)
            requests += retry
            active = f.plan(settled.state, JSONArray().put(retry))
            assertTrue(ids.add(f.node(active)))
            val replay = f.plan(active.state, JSONArray(requests), setOf(f.node(active)))
            assertTrue(replay.work.isEmpty())
            assertFalse(CollaborationCandidateEvolution.pending(replay.state))
            assertEquals(index + 1, CollaborationCandidateVerificationState.read(active.state).getJSONObject(0)
                .getJSONArray("prior_settlements").length())
        }
        assertEquals(13, ids.size)
    }

    @Test fun retryRequiresTheExactCompletedAttemptAndAnIndependentAuthorizedMember() {
        val invalid = listOf<(JSONObject) -> Unit>(
            { it.getJSONObject("retry_review").put("node_id", "other") },
            { it.getJSONObject("retry_review").put("reason", " ") },
            { it.getJSONObject("retry_review").put("extra", true) },
            { it.put("reviewer", "unknown") }, { it.put("reviewer", "author") },
            { it.put("reviewer", "editor") }, { it.put("criterion_id", "invented") },
            { it.getJSONObject("target").put("sha256", "0".repeat(64)) })
        invalid.forEach { change ->
            val f = Fixture(); val first = f.plan()
            val settled = f.plan(first.state, JSONArray(), setOf(f.node(first)))
            val retry = JSONObject(f.retry(first).toString()).also(change)
            val next = f.plan(settled.state, JSONArray().put(retry))
            assertTrue(next.feedback, next.work.isEmpty())
            assertEquals(1, CollaborationCandidateVerificationState.checkpoint(next.state).pendingRequests.length())
            assertEquals(f.node(first), f.node(next))
        }
    }

    @Test fun uncertainOrFailedWorkAndCompletedPublicationsCannotBecomeRetryable() {
        val f = Fixture(); val first = f.plan()
        val failed = f.plan(first.state, JSONArray())
        assertFalse(CollaborationCandidateVerificationState.read(failed.state).getJSONObject(0).getBoolean("retryable_review"))
        assertTrue(f.plan(failed.state, JSONArray().put(f.retry(first))).work.isEmpty())
        listOf("supported", "refuted", "not_tested").forEach { outcome ->
            val published = Fixture(); val review = published.plan(); published.execute(review, outcome)
            val settled = published.plan(review.state, JSONArray(), setOf(published.node(review)))
            val retried = published.plan(settled.state, JSONArray().put(published.retry(review)))
            assertTrue(retried.work.isEmpty())
        }
    }

    @Test fun repairCompletionWithoutPublicationCannotBeReassignedAsAReview() {
        val f = Fixture(); val first = f.plan(); f.execute(first, "refuted")
        val repair = f.plan(first.state, JSONArray(), setOf(f.node(first)))
        val stopped = f.plan(repair.state, JSONArray(), setOf(f.node(repair)))
        val state = CollaborationCandidateVerificationState.read(stopped.state).getJSONObject(0)
        assertEquals("repair", state.getString("settled_phase"))
        assertFalse(state.getBoolean("retryable_review"))
        assertTrue(f.plan(stopped.state, JSONArray().put(f.retry(repair))).work.isEmpty())
        state.put("retryable_review", true)
        assertTrue(f.plan(JSONArray().put(state).toString(), JSONArray()).error)
    }

    @Test fun lateOriginalPublicationPreventsReassignmentAndAlreadyAdmittedDuplicatePublication() {
        listOf(false, true).forEach { alreadyAdmitted ->
            val f = Fixture(); val first = f.plan()
            val stopped = f.plan(first.state, JSONArray(), setOf(f.node(first)))
            val next = if (alreadyAdmitted) f.plan(stopped.state, JSONArray().put(f.retry(first))) else null
            f.execute(first)
            if (next == null) {
                val held = f.plan(stopped.state, JSONArray().put(f.retry(first)))
                assertTrue(held.work.isEmpty())
                assertTrue(held.feedback.contains("committed publication"))
            } else {
                val task = f.task(next)
                val who = f.access.copy(nodeId = f.node(next), personId = "lead")
                assertTrue(runCatching { CollaborationCandidateEvolution.checkTask(f.workspace, who, task) }.isFailure)
                assertEquals("rejected", f.workspace.publish(who, raw(f.review(task)), candidateTask = task).getString("status"))
                assertTrue(f.workspace.publicationRevisions(f.access, f.node(next)).isEmpty())
            }
        }
    }

    @Test fun actualGoalLoopReassignsOnlyAfterHostCompletionWithoutAnAcceptedPublication() {
        val f = Fixture()
        val first = requireNotNull(CollaborationGoalLoop.advance(f.record(), "lead", 100_000, true, candidateWorkspace = { f.workspace }))
        val old = first.definition.members.single { it.context.containsKey(CollaborationCandidateEvolution.TASK) }
        val settled = requireNotNull(CollaborationGoalLoop.advance(f.complete(first, child = old.memberId),
            first.definition.primaryMemberId, 200_000, true, candidateWorkspace = { f.workspace }))
        val originalState = settled.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()
        assertTrue(CollaborationCandidateVerificationState.read(originalState).getJSONObject(0).getBoolean("retryable_review"))
        val retry = f.request().put("reviewer", "lead").put("retry_review", JSONObject()
            .put("node_id", old.memberId).put("reason", "Return the original-source review, not a status message"))
        val next = requireNotNull(CollaborationGoalLoop.advance(f.complete(settled, f.assessment(JSONArray().put(retry))),
            settled.definition.primaryMemberId, 300_000, true, candidateWorkspace = { f.workspace }))
        val replacement = next.definition.members.single { it.context.containsKey(CollaborationCandidateEvolution.TASK) }
        assertNotEquals(old.memberId, replacement.memberId)
        assertEquals("lead", JSONObject(replacement.context.getValue(CollaborationCandidateEvolution.TASK)).getString("member"))
        assertEquals(first.request.context[CollaborationGoalLoop.CRITERIA], next.request.context[CollaborationGoalLoop.CRITERIA])
        assertEquals(old.memberId, CollaborationCandidateVerificationState.read(next.request.context.getValue(
            CollaborationCandidateEvolution.STATE).toString()).getJSONObject(0).getJSONArray("prior_settlements")
            .getJSONObject(0).getString("node_id"))
    }

    @Test fun incompleteDoneCheckpointCannotClearPendingVerification() {
        val broken = "[{\"object_id\":\"candidate\",\"phase\":\"done\"}]"
        assertTrue(CollaborationCandidateEvolution.pending(broken))
        val plan = Fixture().plan(broken, JSONArray())
        assertTrue(plan.error)
        assertEquals(broken, plan.state)
        assertTrue(plan.work.isEmpty())
    }

    @Test fun savedCycleIdentityCannotBeBorrowedFromAnotherGoal() {
        val f = Fixture(); val first = f.plan()
        val borrowed = JSONArray(first.state).apply { getJSONObject(0).put("id", "f".repeat(64)) }.toString()
        val plan = f.plan(borrowed, JSONArray())
        assertTrue(plan.error)
        assertEquals(borrowed, plan.state)
        assertTrue(plan.work.isEmpty())
        assertTrue(plan.feedback.contains("goal scope"))
    }

    @Test fun corruptedCheckpointCannotRecoverCompletedDispatchOrYieldValidSummary() {
        val f = Fixture(); val first = f.plan()
        val state = JSONArray(first.state)
        val id = state.getJSONObject(0).getString("id")
        val finished = setOf("candidate-cycle:$id:validate")
        assertEquals(setOf(f.node(first)), CollaborationCandidateEvolution.completedNodes(first.state, finished))
        state.getJSONObject(0).getJSONObject("target").put("revision", "1")
        assertTrue(CollaborationCandidateEvolution.completedNodes(state.toString(), finished).isEmpty())
        assertTrue(CollaborationCandidateEvolution.summary(state.toString()).contains("malformed"))
    }

    @Test fun redundantStaleEnrollmentCannotStrandAnExistingRefutation() {
        val f = Fixture(); val first = f.plan(); f.execute(first, "refuted")
        val stale = JSONObject(f.target.toString()).put("revision", 99)
        val next = f.plan(first.state, JSONArray().put(f.request(stale)), setOf(f.node(first)))
        assertFalse(next.feedback, next.error)
        assertEquals("revise", f.task(next).getString("operation"))
    }

    @Test fun oneStaleAlternativeDoesNotStopAnotherFeasibleRepair() {
        val f = Fixture()
        val other = f.publish(f.access.copy(nodeId = "other-seed", personId = "author", round = 0), f.candidate("b"))
        val first = f.plan(requests = JSONArray().put(f.request()).put(f.request(other)))
        val state = JSONArray(first.state)
        val secondCycle = state.getJSONObject(1)
        val otherTask = JSONObject(CollaborationCandidateEvolution.taskContext(first.work[1]).getValue(CollaborationCandidateEvolution.TASK))
        val node = secondCycle.getString("node_id")
        f.publish(f.access.copy(nodeId = node, personId = "reviewer", round = 2), f.review(otherTask, "refuted"), otherTask)
        val changed = f.candidate("ignored").put("object_id", f.target.getString("object_id")).put("base_revision", 1)
            .put("parents", JSONArray().put(f.target)).put("observations", JSONArray().put(f.source))
        changed.getJSONObject("body").getJSONObject("candidate").put("operation", "revise")
        f.publish(f.access.copy(nodeId = "concurrent-editor", personId = "editor", round = 2), changed)
        val next = f.plan(first.state, JSONArray(), setOf(node))
        assertFalse(next.error)
        assertEquals("done", JSONArray(next.state).getJSONObject(0).getString("phase"))
        assertEquals("revise", f.task(next).getString("operation"))
        assertEquals(other.getString("object_id"), f.task(next).getJSONObject("target").getString("object_id"))
    }

    @Test fun malformedCheckpointFailsClosedWithoutScheduling() {
        val f = Fixture()
        val broken = "[{\"object_id\":\"candidate\",\"phase\":\"invented\"}]"
        val plan = f.plan(broken, JSONArray())
        assertTrue(plan.error)
        assertEquals(broken, plan.state)
        assertTrue(plan.work.isEmpty())
        assertTrue(CollaborationCandidateEvolution.pending("not JSON"))
    }

    @Test fun candidateTaskStorageFailureHasNoPartialReceiptAndRetriesExactPublication() {
        val f = Fixture(); val first = f.plan(); val task = f.task(first)
        val who = f.access.copy(nodeId = f.node(first), personId = "reviewer")
        val input = raw(f.review(task))
        assertNull(f.ledger.readPage(who, f.source.getString("evidence_id"), f.source.getString("sha256"))!!.next)
        val before = f.rows.values.toMap()
        f.rows.fail = true
        assertTrue(runCatching { f.workspace.publish(who, input, candidateTask = task) }.isFailure)
        assertEquals(before, f.rows.values)
        assertNull(f.workspace.replayCandidateTask(who, task))
        f.rows.fail = false
        assertEquals("recorded", f.workspace.publish(who, input, candidateTask = task).getString("status"))
        assertNotNull(f.workspace.replayCandidateTask(who, task))
    }

    @Test fun controllerCannotCompleteWhileRequestingAnAutomaticCycle() {
        val f = Fixture()
        val raw = f.assessment(JSONArray().put(f.request())).put("decision", "achieved").toString()
        val result = CollaborationGoalAcceptance(f.workspace, f.ledger).evaluate(f.access, raw, JSONArray().put(f.criterion).toString(), "Goal")
        assertFalse(result.accepted)
        assertTrue(result.feedback.contains("Candidate cycle"))
    }

    @Test fun graphRepairCanConsumeAnArchivedSuccessfulCandidateWithoutRepeatingIt() {
        val f = Fixture(); val initial = f.record()
        val scheduled = requireNotNull(CollaborationGoalLoop.advance(initial, "lead", 100_000, true, candidateWorkspace = { f.workspace }))
        val member = scheduled.definition.members.single { it.context[CollaborationCandidateEvolution.TASK] != null }
        val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
        f.publish(f.access.copy(nodeId = member.memberId, personId = "reviewer", round = 3), f.review(task), task)
        val invalid = f.assessment().put("work", JSONArray().put(JSONObject().put("id", "unrelated")
            .put("member", "editor").put("stage", "EXPLORE").put("assignment", "Invalid dependency")
            .put("depends_on", JSONArray().put("missing"))))
        val deferred = requireNotNull(CollaborationGoalLoop.advance(f.complete(scheduled, invalid, member.memberId),
            scheduled.definition.primaryMemberId, 200_000, true, candidateWorkspace = { f.workspace }))
        assertTrue(CollaborationCandidateEvolution.pending(deferred.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()))
        val settled = requireNotNull(CollaborationGoalLoop.advance(f.complete(deferred), deferred.definition.primaryMemberId,
            300_000, true, candidateWorkspace = { f.workspace }))
        assertFalse(CollaborationCandidateEvolution.pending(settled.request.context.getValue(CollaborationCandidateEvolution.STATE).toString()))
        assertTrue(settled.request.context[CollaborationCandidateEvolution.FEEDBACK].toString().contains("supported"))
        assertTrue(settled.definition.members.none { it.context[CollaborationCandidateEvolution.TASK] != null })
    }

    companion object {
        private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Substantive contribution").put("candidates", JSONArray()).put("findings", JSONArray())
            .put("workspace", JSONArray(items.toList())).toString()
    }
}
