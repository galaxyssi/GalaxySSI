package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSemanticGoalLoopTest {
    @Test fun rejectedInitialDraftGetsTargetedFeedbackAndCorrectedPlanCanDispatch() {
        val initial = criterion().put("required_observations", JSONArray().put(
            JSONObject().put("origin", "desktop").put("tool", "exec_command")))
        val report = assessment(initial).put("work", JSONArray().put(job("measure")))
        val rejected = advance(initial, report, "[]")
        assertRepairOnly(rejected, "[]")
        assertEquals(report.toString(), rejected.request.context[CollaborationGoalLoop.PREVIOUS])
        val feedback = rejected.request.context.getValue(CollaborationGoalLoop.ACCEPTANCE_FEEDBACK).toString()
        assertTrue(feedback.contains("initial_criteria_pending"))
        assertTrue(feedback.contains("$.criteria[0].required_observations[0].origin"))
        assertTrue(feedback.contains("desktop_codex_tool"))
        val instruction = rejected.definition.members.single { it.deliveryMode == AgentDeliveryMode.RESPOND }.objective
        assertTrue(instruction.contains("empty array is not corruption"))
        val corrected = JSONObject(report.toString())
        corrected.getJSONArray("criteria").getJSONObject(0).getJSONArray("required_observations").getJSONObject(0)
            .put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution")
        val next = requireNotNull(CollaborationGoalLoop.advance(complete(rejected, corrected),
            rejected.definition.primaryMemberId, 100_000, false))
        assertEquals(1, next.definition.members.count { it.deliveryMode == AgentDeliveryMode.OBSERVE })
        assertEquals("measure", next.definition.members.single { it.deliveryMode == AgentDeliveryMode.OBSERVE }.context[CollaborationGoalLoop.WORK_ID])
        assertEquals("desktop_codex_tool", JSONArray(next.request.context[CollaborationGoalLoop.CRITERIA].toString())
            .getJSONObject(0).getJSONArray("required_observations").getJSONObject(0).getString("origin"))
    }

    @Test fun rejectedEstablishedDraftKeepsExactPriorAndDoesNotRequestContractRecovery() {
        val original = criterion().put("required_observations", JSONArray().put(
            JSONObject().put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution")))
        val proposed = JSONObject(original.toString())
        proposed.getJSONArray("required_observations").getJSONObject(0).put("origin", "desktop")
        val next = advance(original, assessment(proposed))
        assertRepairOnly(next, JSONArray().put(original).toString())
        val instruction = next.definition.members.single { it.deliveryMode == AgentDeliveryMode.RESPOND }.objective
        assertTrue(instruction.contains("preserving every established"))
        assertFalse(instruction.contains("requiring recovery"))
        assertTrue(next.request.context[CollaborationGoalLoop.ACCEPTANCE_FEEDBACK].toString().contains("\"contract_state\":\"established\""))
    }

    @Test fun preDispatchOverflowPreservesCheckpointWithoutInventingJsonRepairRounds() {
        val error = CollaborationPromptBudget.Overflow(listOf(
            CollaborationPromptBudget.Section("Assignment", "large assignment")), 100, 10).message.orEmpty()
        val base = record(criterion(), assessment(criterion()))
        val failed = base.copy(events = base.events.map { event ->
            if (event.result != null) event.copy(kind = AgentSubagentEventKinds.CHILD_FAILED,
                childStatus = AgentSubagentStatus.FAILED, result = event.result.copy(status = AgentSubagentStatus.FAILED,
                    output = "", errorMessage = error))
            else event.copy(kind = AgentSubagentEventKinds.SUPERVISOR_FAILED, runStatus = AgentSubagentRunStatus.FAILED)
        })
        repeat(20) { assertNull(CollaborationGoalLoop.advance(failed, "lead", 1000000L + it, false)) }
        val store = InMemoryAgentTeamExecutionStore()
        store.create(failed.definition, failed.request)
        kotlinx.coroutines.runBlocking { failed.events.forEach { store.append(it) } }
        val snapshot = requireNotNull(store.snapshot("run"))
        assertEquals("blocked", snapshot.goalDisposition)
        assertEquals(error, snapshot.finalOutput)
        val resumed = requireNotNull(CollaborationGoalLoop.advance(failed, "lead", 1000000, true))
        assertEquals(failed.request.context[CollaborationGoalLoop.CRITERIA], resumed.request.context[CollaborationGoalLoop.CRITERIA])
        val retry = resumed.definition.members.single { it.deliveryMode == AgentDeliveryMode.RESPOND }
        assertEquals(failed.definition.members.single { it.memberId == "lead" }.objective, retry.objective)
        assertFalse(resumed.request.context[CollaborationGoalLoop.ACCEPTANCE_FEEDBACK].toString().contains("Invalid assessment"))
        assertNotEquals("lead", retry.memberId)
        assertTrue(resumed.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE })
    }

    private val goal = "Compute the exact integer sum: 2 + 3."
    private fun criterion() = JSONObject().put("id", "sum").put("requirement", goal).put("verification", "computational")
        .put("status", "open").put("evidence_kind", "observed").put("evidence", JSONArray())
        .put("validator", JSONObject().put("id", "exact_integer_sum.v1").put("operands", JSONArray().put("2").put("3")))
    private fun assessment(item: JSONObject, decision: String = "continue") = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "Preserve and verify the fixture").put("decision", decision).put("criteria", JSONArray().put(item))
        .put("work", JSONArray()).put("blockers", JSONArray())

    private fun advance(prior: JSONObject, report: JSONObject, priorRaw: String = JSONArray().put(prior).toString(),
                        recruitmentNames: () -> List<String> = { emptyList() }): AgentTeamExecutionRecord =
        requireNotNull(CollaborationGoalLoop.advance(record(prior, report, priorRaw), "lead", 1_000, false, recruitmentNames))

    private fun record(prior: JSONObject, report: JSONObject, priorRaw: String = JSONArray().put(prior).toString()): AgentTeamExecutionRecord {
        val people = CollaborationGoalLoop.initial(listOf(
            AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead",
                context = mapOf("collaboration_group_id" to "group")),
            AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer",
                context = mapOf("collaboration_group_id" to "group"))), goal)
        val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = goal,
            context = mapOf(CollaborationGoalLoop.CRITERIA to priorRaw, CollaborationGoalLoop.HOST_ACCEPTANCE to "1"))
        return complete(AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", people, primaryInstanceId = "lead"), request), report)
    }

    private fun complete(record: AgentTeamExecutionRecord, report: JSONObject): AgentTeamExecutionRecord {
        val primary = record.definition.primaryMemberId
        return record.copy(events = listOf(AgentSubagentEvent(1, "run", primary, AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = AgentSubagentStatus.SUCCEEDED,
            result = AgentSubagentChildResult("run", primary, "run", 1, AgentSubagentStatus.SUCCEEDED, report.toString(),
                provenance = AgentSubagentProvenance("agent-team", "team", "run", mapOf("instance_id" to primary, "agent_id" to "fixture")))),
            AgentSubagentEvent(2, "run", kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)))
    }

    private fun job(id: String = "overwrite", member: String = "peer") = JSONObject().put("id", id).put("member", member)
        .put("stage", "EXECUTE").put("assignment", "Overwrite the saved result file using the proposed inputs and submit the result")

    private fun executableRequests(report: JSONObject) = report.put("work", JSONArray().put(job()).put(job("recruit-job", "recruit:verifier")
        .put("assignment", "Independently audit the proposed inputs without overwriting the saved file")))
        .put("recruit", JSONArray().put(JSONObject().put("id", "verifier").put("template_member", "peer")
            .put("role", "Verifier").put("scope", "Independent input audit").put("reason", "A distinct fixture responsibility")))
        .put("blockers", JSONArray().put(JSONObject().put("id", "lab").put("kind", "resource")
            .put("reason", "A laboratory is unavailable").put("resume_when", "An authorized laboratory becomes available")))

    private fun assertRepairOnly(next: AgentTeamExecutionRecord, priorRaw: String) {
        assertEquals(priorRaw, next.request.context[CollaborationGoalLoop.CRITERIA])
        assertTrue(next.definition.members.none { it.deliveryMode == AgentDeliveryMode.OBSERVE || it.context.containsKey(CollaborationGoalLoop.WORK_ID) })
        assertEquals(setOf("lead", "peer"), next.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" }
            .map { it.context[CollaborationResearchWorkflow.PERSON] }.toSet())
        val repair = next.definition.members.single { it.deliveryMode == AgentDeliveryMode.RESPOND }
        assertEquals(next.definition.primaryMemberId, repair.memberId)
        assertEquals("DELIVER", repair.context[CollaborationResearchWorkflow.STAGE])
        assertTrue(repair.objective.startsWith("Repair the assessment"))
        assertTrue(repair.dependsOnAgentIds.isEmpty())
        assertTrue(next.request.context[CollaborationGoalLoop.ACCEPTANCE_FEEDBACK].toString().contains("No assignments"))
        assertTrue(next.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("No assignments"))
    }

    private fun manifest(next: AgentTeamExecutionRecord) = JSONObject(
        next.request.context.getValue(CollaborationGoalLoop.ACCEPTANCE_FEEDBACK).toString().substringAfterLast('\n'))

    @Test fun largeOriginalGoalRemainsInRequestWithoutBeingCopiedIntoMemberObjectives() {
        val prefix = "ORIGINAL_GOAL_BEGIN\n"
        val suffix = "\nORIGINAL_GOAL_END: Preserve this final constraint."
        val originalGoal = prefix + "x".repeat(100_000 - prefix.length - suffix.length) + suffix
        val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = originalGoal)
        val people = listOf(
            AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
            AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer", objective = "Independent source review"))
        val members = CollaborationGoalLoop.initial(people, request.goal)
        val record = AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", members, primaryInstanceId = "lead"), request)

        assertEquals(100_000, originalGoal.length)
        assertEquals(originalGoal, record.request.goal)
        assertSame(request, record.request)
        assertEquals(CollaborationGoalLoop.initial(people, "Short goal"), record.definition.members)
        val coordinator = members.single { it.deliveryMode == AgentDeliveryMode.RESPOND }
        assertTrue(coordinator.objective.contains("original goal contract"))
        assertFalse(coordinator.objective.contains("ORIGINAL_GOAL_BEGIN"))
        assertFalse(coordinator.objective.contains("ORIGINAL_GOAL_END"))
        assertEquals("Independent source review", members.single { it.memberId == "peer" }.objective)
    }

    @Test fun continuationCannotReplaceRemoveOrIntroduceValidatorBinding() {
        val prior = criterion()
        val mutations = listOf(
            criterion().apply { getJSONObject("validator").put("operands", JSONArray().put("1").put("4")) },
            criterion().apply { remove("validator") },
            criterion().put("validator", JSONObject.NULL),
            criterion().apply { getJSONObject("validator").put("id", "unqualified") })
        mutations.forEach { changed ->
            val next = advance(prior, assessment(changed))
            val saved = JSONArray(next.request.context.getValue(CollaborationGoalLoop.CRITERIA).toString()).getJSONObject(0)
            assertEquals(CollaborationQualifiedValidation.binding(prior), CollaborationQualifiedValidation.binding(saved))
        }
        val absent = criterion().apply { remove("validator") }
        val next = advance(absent, assessment(criterion()))
        assertFalse(JSONArray(next.request.context.getValue(CollaborationGoalLoop.CRITERIA).toString()).getJSONObject(0).has("validator"))
    }

    @Test fun malformedSpecificationFailsDecodeAndCannotBeClaimedAchieved() {
        listOf(JSONObject.NULL, "exact_integer_sum.v1", JSONObject().put("id", "unknown")).forEach { spec ->
            val raw = assessment(criterion().put("validator", spec), "achieved").toString()
            assertNull(CollaborationGoalLoop.decode(raw))
            assertEquals("continue", CollaborationGoalLoop.disposition(raw, acceptanceVerified = true))
        }
        val before = criterion()
        val changed = criterion().put("status", "met").put("evidence", JSONArray().put("saved-result"))
        changed.getJSONObject("validator").put("operands", JSONArray().put("1").put("4"))
        assertEquals("continue", CollaborationGoalLoop.disposition(assessment(changed, "achieved").toString(),
            JSONArray().put(before).toString(), acceptanceVerified = true))
    }

    @Test fun corruptPreservedCriteriaAreNotSilentlyReplacedWithAnEmptyContract() {
        listOf("not-json", "[7]", "[] trailing", JSONArray().put(criterion()).put(criterion()).toString()).forEach { priorRaw ->
            val saved = record(criterion(), assessment(criterion()), priorRaw)
            assertNull(CollaborationGoalLoop.advance(saved, "lead", 1_000, false))
            assertEquals(priorRaw, saved.request.context[CollaborationGoalLoop.CRITERIA])
            assertEquals("blocked", CollaborationGoalLoop.disposition("", priorRaw))
            assertEquals(CollaborationGoalLoop.CONTRACT_RECOVERY_REQUIRED, CollaborationGoalLoop.preservedCriteriaError(priorRaw))
        }
    }

    @Test fun everyContinuationSuppliesHostSourceAndBindingWithoutPollutingAssignments() {
        val prior = criterion()
        val report = assessment(criterion()).put("work", JSONArray()
            .put(JSONObject().put("id", "map").put("member", "lead").put("stage", "EXECUTE").put("assignment", "Author the mapping"))
            .put(JSONObject().put("id", "review").put("member", "peer").put("stage", "VERIFY").put("assignment", "Review the mapping")
                .put("depends_on", JSONArray().put("map")).put("independent_review", true)))
        val next = advance(prior, report)
        val feedback = next.request.context.getValue(CollaborationGoalLoop.ACCEPTANCE_FEEDBACK).toString()
        val manifest = JSONObject(feedback.substringAfter('\n'))
        assertEquals(CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"), manifest.getString("goal_sha256"))
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(prior)), manifest.getString("criteria_sha256"))
        assertEquals(goal, manifest.getJSONArray("segments").getJSONObject(0).getString("text"))
        val jobs = next.definition.members.filter { it.context[CollaborationGoalLoop.WORK_ID] in setOf("map", "review") }
        assertEquals(2, jobs.size)
        assertEquals(setOf("lead", "peer"), jobs.map { it.context[CollaborationResearchWorkflow.PERSON] }.toSet())
        assertEquals(setOf("Author the mapping", "Review the mapping"), jobs.map { it.objective }.toSet())
        assertTrue(jobs.single { it.context[CollaborationGoalLoop.WORK_ID] == "review" }.dependsOnAgentIds.contains(
            jobs.single { it.context[CollaborationGoalLoop.WORK_ID] == "map" }.memberId))
    }

    @Test fun unchangedBindingCanAdvanceStatusAndInstructionsRequireTwoPersonIndependentWork() {
        val prior = criterion()
        val next = advance(prior, assessment(criterion().put("status", "met")))
        assertEquals("met", JSONArray(next.request.context.getValue(CollaborationGoalLoop.CRITERIA).toString()).getJSONObject(0).getString("status"))
        val instructions = CollaborationGoalLoop.instructions()
        assertTrue(instructions.contains("goal_sha256"))
        assertTrue(instructions.contains("two-person"))
        assertTrue(instructions.contains("not general computational/scientific completion"))
        assertTrue(instructions.contains("Do not count offsets"))
    }

    @Test fun rejectedValidatorInputsDispatchNeitherSideEffectAssignmentsNorRecruitmentOrResourceJobs() {
        val cases = listOf(
            criterion() to criterion().apply { getJSONObject("validator").put("operands", JSONArray().put("1").put("4")) },
            criterion() to criterion().apply { remove("validator") },
            criterion().apply { remove("validator") } to criterion(),
            criterion() to criterion().put("validator", JSONObject.NULL),
            criterion() to criterion().put("validator", "exact_integer_sum.v1"),
            criterion() to criterion().apply { getJSONObject("validator").put("id", "unqualified") })
        cases.forEach { (prior, proposed) ->
            val priorRaw = "[ \n${prior}\n ]"
            val report = executableRequests(assessment(proposed.put("status", "met")))
            val next = advance(prior, report, priorRaw) { error("Rejected contracts must not request recruitment names") }
            assertRepairOnly(next, priorRaw)
            assertEquals(report.toString(), next.request.context[CollaborationGoalLoop.PREVIOUS])
            assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(priorRaw)), manifest(next).getString("criteria_sha256"))
            assertEquals(CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"), manifest(next).getString("goal_sha256"))
        }
    }

    @Test fun malformedPriorCannotDispatchOrBeReplacedByAValidNewAssessment() {
        val corrupt = listOf("not-json", "[7]", JSONArray().put(criterion()).put(criterion()).toString(),
            JSONArray().put(criterion().put("id", 7)).toString(), JSONArray().put(criterion().put("requirement", " ")).toString(),
            JSONArray().put(criterion().apply { remove("requirement") }).toString(),
            JSONArray().put(criterion().put("verification", "invented")).toString(),
            JSONArray().put(criterion().put("required_observations", JSONObject.NULL)).toString(),
            JSONArray().put(criterion().put("validator", JSONObject().put("id", "unknown"))).toString())
        corrupt.forEach { priorRaw ->
            val report = executableRequests(assessment(criterion()))
            val saved = record(criterion(), report, priorRaw)
            for (wake in listOf(false, true)) {
                assertNull(CollaborationGoalLoop.advance(saved, "lead", 100_000, wake) {
                    error("Corrupt contracts must not request recruitment names")
                })
            }
            assertEquals(priorRaw, saved.request.context[CollaborationGoalLoop.CRITERIA])
            assertEquals("blocked", CollaborationGoalLoop.disposition(report.toString(), priorRaw, acceptanceVerified = true))
            val store = InMemoryAgentTeamExecutionStore()
            store.create(saved.definition, saved.request)
            kotlinx.coroutines.runBlocking { saved.events.forEach { store.append(it) } }
            val snapshot = requireNotNull(store.snapshot("run"))
            assertEquals("blocked", snapshot.goalDisposition)
            assertEquals(CollaborationGoalLoop.CONTRACT_RECOVERY_REQUIRED, snapshot.finalOutput)
        }
    }

    @Test fun rejectedRequirementVerificationOrSourceChangeRejectsTheWholeExecutablePlan() {
        val prior = criterion().put("required_observations", JSONArray().put(JSONObject()
            .put("origin", "android_cloud_tool").put("tool", "original_check")))
        val changed = listOf(
            JSONObject(prior.toString()).put("requirement", "An easier requirement"),
            JSONObject(prior.toString()).put("verification", "documentary"),
            JSONObject(prior.toString()).put("required_observations", JSONArray()),
            JSONObject(prior.toString()).put("id", "replacement"))
        changed.forEach { item ->
            val next = advance(prior, executableRequests(assessment(item))) { error("No recruitment under rejected inputs") }
            assertRepairOnly(next, JSONArray().put(prior).toString())
        }
    }

    @Test fun validRepairCanResumeIndependentWorkWithoutALifetimeRoundLimit() {
        val prior = criterion()
        val changed = criterion().apply { getJSONObject("validator").put("operands", JSONArray().put("1").put("4")) }
        val rejected = advance(prior, executableRequests(assessment(changed))) { error("No recruitment under rejected inputs") }
        val report = assessment(criterion()).put("work", JSONArray().put(job()))
        val recovered = complete(rejected, report).let { it.copy(request = it.request.copy(context = it.request.context +
            (CollaborationGoalLoop.ROUND to "1000000"))) }
        val next = requireNotNull(CollaborationGoalLoop.advance(recovered, recovered.definition.primaryMemberId, 100_000, false))
        assertEquals("1000001", next.request.context[CollaborationGoalLoop.ROUND])
        assertEquals("overwrite", next.definition.members.single { it.deliveryMode == AgentDeliveryMode.OBSERVE }.context[CollaborationGoalLoop.WORK_ID])
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(prior)), manifest(next).getString("criteria_sha256"))
    }

    @Test fun validEmptyAndLegacyUntypedContractsStillAllowWorkAndStrongerSources() {
        val documentary = criterion().apply { remove("validator"); put("verification", "documentary") }
        val legacy = JSONObject(documentary.toString()).apply { remove("verification") }
        listOf("[]", JSONArray().put(legacy).toString()).forEach { priorRaw ->
            val next = advance(legacy, assessment(documentary).put("work", JSONArray().put(job())), priorRaw)
            assertEquals(1, next.definition.members.count { it.deliveryMode == AgentDeliveryMode.OBSERVE })
            assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(documentary)), manifest(next).getString("criteria_sha256"))
        }
        val stronger = JSONObject(documentary.toString()).put("required_observations", JSONArray().put(JSONObject()
            .put("origin", "android_cloud_tool").put("tool", "original_check")))
        val extra = JSONObject(documentary.toString()).put("id", "additional").put("requirement", "Document limitations")
        val report = assessment(stronger).put("criteria", JSONArray().put(stronger).put(extra)).put("work", JSONArray().put(job()))
        val next = advance(documentary, report)
        assertEquals(1, next.definition.members.count { it.deliveryMode == AgentDeliveryMode.OBSERVE })
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(report.getJSONArray("criteria")), manifest(next).getString("criteria_sha256"))
    }

    @Test fun validContractStillAllowsRecruitmentAndResourceResolution() {
        var nameRequests = 0
        val prior = criterion()
        val next = advance(prior, executableRequests(assessment(criterion()))) {
            nameRequests++
            listOf("Curie", "Hopper")
        }
        assertEquals(1, nameRequests)
        assertEquals(3, next.definition.members.count { it.context[CollaborationGoalLoop.ROSTER] == "true" })
        val jobs = next.definition.members.filter { it.deliveryMode == AgentDeliveryMode.OBSERVE }
        assertEquals(3, jobs.size)
        assertTrue(jobs.any { CollaborationResourceRecovery.isReservedWorkId(it.context.getValue(CollaborationGoalLoop.WORK_ID)) })
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(prior)), manifest(next).getString("criteria_sha256"))
    }

    @Test fun contractRepairDoesNotBypassCancellationBackoffOrReplayHistoricalCompletion() {
        val rejected = record(criterion(), executableRequests(assessment(criterion())), "not-json")
        val cancelled = rejected.copy(events = rejected.events + AgentSubagentEvent(3, "run", kind = "cancelled", runStatus = AgentSubagentRunStatus.CANCELLED))
        assertNull(CollaborationGoalLoop.advance(cancelled, "lead", 1_000, true))
        val backoff = rejected.copy(request = rejected.request.copy(context = rejected.request.context + (CollaborationGoalLoop.RETRY_AT to "2000")))
        assertNull(CollaborationGoalLoop.advance(backoff, "lead", 1_000, false))
        val done = assessment(criterion().put("status", "met").put("evidence", JSONArray().put("historical evidence")), "achieved")
        val historical = record(criterion(), done).let { it.copy(request = it.request.copy(context = it.request.context - CollaborationGoalLoop.HOST_ACCEPTANCE)) }
        assertNull(CollaborationGoalLoop.advance(historical, "lead", 1_000, false))
        assertEquals("unverified_history", CollaborationGoalLoop.disposition(done.toString(), JSONArray().put(criterion()).toString(), allowUnverifiedHistory = true))
    }
}
