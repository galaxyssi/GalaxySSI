package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTeamOrganizationIntegrationTest {
    private fun people() = CollaborationGoalLoop.initial(listOf("lead", "author", "reviewer", "backup").map { id ->
        AgentTeamMember("fixture", if (id == "lead") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            requiredCapabilities = setOf(AgentCapability.RESEARCH), instanceId = id,
            role = if (id == "lead") "User-appointed coordinator" else "User-appointed tester",
            context = mapOf("collaboration_group_id" to "group", "collaboration_name" to id,
                "collaboration_model_id" to "authorized-model", "history_reference" to "saved:$id"))
    }, "Produce the artifact and an independent review")
    private fun work(id: String, member: String = "author", stage: String = "EXECUTE", assignment: String = "Implement bounded integer parser") =
        JSONObject().put("id", id).put("member", member).put("stage", stage).put("assignment", assignment)
    private fun assessment(vararg work: JSONObject) = JSONObject().put("format", CollaborationGoalLoop.FORMAT)
        .put("summary", "Fixture checkpoint").put("decision", "continue")
        .put("criteria", JSONArray().put(JSONObject().put("id", "artifact").put("requirement", "Artifact and independent review")
            .put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray(work.toList())).put("blockers", JSONArray())
    private fun initial(plan: JSONObject): AgentTeamExecutionRecord = settle(AgentTeamExecutionRecord(
        AgentTeamDefinition("team", "fixture", people(), primaryInstanceId = "lead"),
        AgentRunRequest("group", "turn", "task", runId = "run", goal = "Produce the artifact and an independent review")), plan)
    private fun settle(record: AgentTeamExecutionRecord, assessment: JSONObject,
                       statuses: Map<String, AgentSubagentStatus> = emptyMap()): AgentTeamExecutionRecord {
        val events = record.definition.members.filter { it.deliveryMode != AgentDeliveryMode.IGNORE }.mapIndexed { index, member ->
            val status = statuses[member.context[CollaborationGoalLoop.WORK_ID]] ?: AgentSubagentStatus.SUCCEEDED
            val result = AgentSubagentChildResult("run", member.memberId, "run", 1, status,
                output = if (member.deliveryMode == AgentDeliveryMode.RESPOND) assessment.toString()
                    else "{\"quality\":1,\"cost_usd_micros\":0,\"outcome\":\"SUCCEEDED\"}",
                startedAtMillis = 100L, completedAtMillis = 150L,
                provenance = AgentSubagentProvenance("agent-team", "team", "run",
                    mapOf("instance_id" to member.memberId, "agent_id" to member.agentId)))
            AgentSubagentEvent(index + 1L, "run", member.memberId, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = status, result = result)
        }
        return record.copy(events = events + AgentSubagentEvent(events.size + 1L, "run",
            kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED))
    }
    private fun advance(record: AgentTeamExecutionRecord) = requireNotNull(CollaborationGoalLoop.advance(
        record, record.definition.primaryMemberId, Long.MAX_VALUE, false, recruitmentNames = { listOf("Reserved") }))
    private fun workers(record: AgentTeamExecutionRecord) = record.definition.members.filter { it.deliveryMode == AgentDeliveryMode.OBSERVE }
    private fun roster(record: AgentTeamExecutionRecord) = record.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" }
    private fun history(record: AgentTeamExecutionRecord) = CollaborationTeamOrganizationHistory.decode(
        record.request.context[CollaborationTeamOrganizationHistory.HISTORY]?.toString(), "run", "group")

    @Test fun checkpointPersistsHostObservationsAndPreservesUserRolesAcrossReactivation() {
        val first = advance(initial(assessment(work("build"), work("review", "reviewer", "VERIFY", "Review parser boundary behavior")
            .put("depends_on", JSONArray().put("build")).put("independent_review", true))))
        assertEquals(2, workers(first).size)
        assertTrue(history(first).isEmpty())
        val completed = settle(first, assessment(work("source-check", "backup", "EXPLORE", "Check the grammar against its primary specification")))
        val second = advance(completed)
        assertTrue(second.events.isEmpty())
        assertEquals(2, history(second).size)
        assertTrue(history(second).all { it.outcome == CollaborationTeamOrganization.Outcome.SUCCEEDED &&
            it.elapsedMillis == 50L && it.costUsdMicros == null && it.provenanceSource == "agent-team" })
        assertEquals(setOf("author", "reviewer"), roster(second).filter {
            it.context[CollaborationTeamOrganization.STATE] == "standby"
        }.map { CollaborationTeamOrganization.person(it) }.toSet())
        assertEquals(first.definition, completed.definition)
        assertFalse(completed.events.isEmpty())
        val json = JSONObject(second.request.context)
        val restored = second.copy(request = second.request.copy(context = JSONObject(json.toString()).let { restored ->
            restored.keys().asSequence().associateWith { restored.get(it) }
        }))
        val third = advance(settle(restored, assessment(work("repair", "author", "REVISE", "Add grammar coverage for hexadecimal input"))))
        assertEquals(3, history(third).size)
        assertEquals("active", roster(third).first { it.memberId == "author" }.context[CollaborationTeamOrganization.STATE])
        roster(third).forEach { member ->
            val original = people().first { it.memberId == member.memberId }
            assertEquals(original.role, member.role)
            assertEquals(original.agentId, member.agentId)
            assertEquals(original.requiredCapabilities, member.requiredCapabilities)
            assertEquals(original.context["history_reference"], member.context["history_reference"])
            assertEquals(original.context["collaboration_model_id"], member.context["collaboration_model_id"])
            assertEquals("false", member.context["collaboration_receive_results"])
        }
        val stats = JSONObject(second.request.context[CollaborationTeamOrganizationContext.SUMMARY].toString()).getJSONArray("metric_groups")
        repeat(stats.length()) { index ->
            assertTrue(stats.getJSONObject(index).isNull("quality"))
            assertTrue(stats.getJSONObject(index).isNull("cost_usd_micros"))
        }
    }

    @Test fun historicalDuplicateUnderNewIdRepairsWithoutStoppingOrReplayingTheGoal() {
        val first = advance(initial(assessment(work("build"))))
        val second = advance(settle(first, assessment(work("renamed-build"))))
        assertTrue(workers(second).isEmpty())
        assertTrue(second.request.context[CollaborationGoalRecruitment.FEEDBACK].toString().contains("recall its original"))
        assertEquals("run", second.request.runId)
        assertEquals(first.request.goal, second.request.goal)
        assertEquals(4, roster(second).size)
        assertEquals(1, second.definition.members.count { it.deliveryMode == AgentDeliveryMode.RESPOND })
        assertEquals("build", history(second).single().workId)
    }

    @Test fun changedCriteriaRequireExplicitMappingRepairWithoutReplayingCompletedWork() {
        val assignment = "Publish the goal mapping using preserved criteria and saved artifacts only; do not execute tools"
        val first = advance(initial(assessment(work("map-v1", "lead", assignment = assignment))))
        val changed = assessment(work("map-v2", "lead", assignment = assignment))
        changed.getJSONArray("criteria").put(JSONObject().put("id", "limits")
            .put("requirement", "Document the parser overflow limits").put("status", "open").put("evidence", JSONArray()))
        val second = advance(settle(first, changed))
        assertTrue(workers(second).isEmpty())
        val feedback = second.request.context[CollaborationGoalRecruitment.FEEDBACK].toString()
        assertTrue(feedback.contains("If preserved criteria changed"))
        assertTrue(feedback.contains("old/new host criteria bindings"))
        assertEquals(2, JSONArray(second.request.context[CollaborationGoalLoop.CRITERIA].toString()).length())
        assertEquals("map-v1", history(second).single().workId)
        assertEquals(CollaborationTeamOrganization.signature(work("map-v1", "lead", assignment = assignment)),
            history(second).single().signature)

        val repair = JSONObject(changed.toString())
        repair.getJSONArray("work").getJSONObject(0).put("replication", JSONObject()
            .put("reason", "Revise only the saved mapping for the added acceptance requirement")
            .put("difference", "Criterion limits now requires overflow documentation; map the saved artifacts to it without tool execution"))
        repair.getJSONArray("work").put(work("map-review-v2", "reviewer", "VERIFY",
            "Independently compare the revised mapping to preserved criteria using saved artifacts only")
            .put("depends_on", JSONArray().put("map-v2")).put("independent_review", true))
        val third = advance(settle(second, repair))
        assertEquals(setOf("map-v2", "map-review-v2"), workers(third).map { it.context[CollaborationGoalLoop.WORK_ID] }.toSet())
        assertTrue(workers(third).none { it.context[CollaborationGoalLoop.WORK_ID] == "map-v1" })
        assertEquals(history(second), history(third))
        assertTrue(JSONArray(third.request.context[CollaborationGoalLoop.FINISHED_WORK].toString()).toString().contains("map-v1"))
        val review = workers(third).single { it.context[CollaborationGoalLoop.WORK_ID] == "map-review-v2" }
        val mapping = workers(third).single { it.context[CollaborationGoalLoop.WORK_ID] == "map-v2" }
        assertEquals(setOf(mapping.memberId), review.dependsOnAgentIds)
        assertNotEquals(mapping.context[CollaborationResearchWorkflow.PERSON], review.context[CollaborationResearchWorkflow.PERSON])
    }

    @Test fun mutableAcceptanceMetadataDoesNotMakeCompletedMappingNew() {
        val assignment = "Publish the goal mapping from preserved criteria"
        val first = advance(initial(assessment(work("map-v1", "lead", assignment = assignment))))
        val plan = assessment(work("renamed-map", "lead", assignment = assignment))
        plan.getJSONArray("criteria").getJSONObject(0).put("status", "met")
            .put("evidence", JSONArray().put("changed evidence label"))
            .put("delivery", JSONObject().put("object_id", "new member claim"))
            .put("review", JSONObject().put("revision", 99))
        val second = advance(settle(first, plan))
        assertTrue(workers(second).isEmpty())
        assertTrue(second.request.context[CollaborationGoalRecruitment.FEEDBACK].toString()
            .contains("Status/evidence updates or cosmetic renaming are not material inputs"))
        assertEquals(CollaborationTeamOrganization.signature(work("map-v1", "lead", assignment = assignment)),
            history(second).single().signature)
        assertEquals("map-v1", history(second).single().workId)
        assertEquals(first.request.runId, second.request.runId)
        assertEquals(first.request.goal, second.request.goal)
    }

    @Test fun changedCriteriaCannotUnlockACompletedSideEffectUnderANewWorkId() {
        val assignment = "Perform the one-shot fixture operation and preserve its host receipt"
        val first = advance(initial(assessment(work("one-shot", assignment = assignment))))
        val plan = assessment(work("renamed-one-shot", assignment = assignment)
            .put("material_input_binding", JSONObject().put("source", "host").put("criteria_sha256", "f".repeat(64))))
        plan.getJSONArray("criteria").put(JSONObject().put("id", "mapping")
            .put("requirement", "Independently review the saved goal mapping").put("status", "open").put("evidence", JSONArray()))
        // settle supplies a durable fixture outcome; no operation or provider is invoked by this test.
        val completed = settle(first, plan)
        val next = advance(completed)
        assertTrue(workers(next).isEmpty())
        assertEquals("one-shot", history(next).single().workId)
        assertEquals(first.definition, completed.definition)
        assertFalse(completed.events.isEmpty())
        assertTrue(next.request.context[CollaborationGoalRecruitment.FEEDBACK].toString()
            .contains("Do not rerun completed tool calls or side effects"))
        assertEquals(setOf("one-shot"), CollaborationGoalLoop.finishedWork(next))
    }

    @Test fun resourceRecoveryIsIncludedBeforeStandbyAndSubgroupsAreProjected() {
        val plan = assessment().put("blockers", JSONArray().put(JSONObject().put("id", "dataset")
            .put("kind", "resource").put("reason", "Required dataset unavailable").put("resume_when", "Authorized dataset accessible")))
        val next = advance(initial(plan))
        val recovery = workers(next).single()
        assertTrue(CollaborationResourceRecovery.isReservedWorkId(recovery.context.getValue(CollaborationGoalLoop.WORK_ID)))
        assertEquals("active", recovery.context[CollaborationTeamOrganization.STATE])
        assertEquals(1, JSONArray(recovery.context[CollaborationTeamOrganization.SUBGROUPS]).length())
        assertTrue(JSONObject(recovery.context[CollaborationTeamOrganization.SIGNATURES]).has(recovery.context[CollaborationGoalLoop.WORK_ID]))
        val summary = JSONObject(next.request.context[CollaborationTeamOrganizationContext.SUMMARY].toString())
        assertEquals(1, summary.getInt("subgroup_count"))
        assertTrue(recovery.objective.contains("Do not buy"))
    }

    @Test fun unresolvedWorkOrPlannerPreventsCheckpointReplacement() {
        val first = advance(initial(assessment(work("build"))))
        listOf(workers(first).single().memberId, first.definition.primaryMemberId).forEach { unresolved ->
            val settled = settle(first, assessment(work("next", assignment = "Test overflow behavior")))
            val live = settled.copy(events = settled.events.filterNot { it.childId == unresolved } +
                AgentSubagentEvent(10L, "run", unresolved, AgentSubagentEventKinds.CHILD_RUNNING, childStatus = AgentSubagentStatus.RUNNING))
            assertNull(CollaborationGoalLoop.advance(live, live.definition.primaryMemberId, Long.MAX_VALUE, true))
            assertEquals(first.definition, live.definition)
            assertTrue(live.events.any { it.childId == unresolved && it.childStatus == AgentSubagentStatus.RUNNING })
        }
    }

    @Test fun invalidIndependentReviewDoesNotGainAuthorityThroughAllocation() {
        val first = advance(initial(assessment(work("build"))))
        val plan = assessment(work("review", "author", "VERIFY", "Independently review the parser")
            .put("depends_on", JSONArray().put("build")).put("independent_review", true))
        val second = advance(settle(first, plan))
        assertTrue(workers(second).isEmpty())
        assertTrue(second.request.context[CollaborationWorkGraph.FEEDBACK].toString().contains("different author"))
        assertEquals("author", JSONObject(second.request.context[CollaborationGoalLoop.FINISHED_AUTHORS].toString()).getString("build"))
        assertEquals(4, roster(second).size)
    }

    @Test fun observationsInfluenceVacancyReuseButNeverOverrideExplicitMemberAssignment() {
        val first = advance(initial(assessment(work("bounds", "author", assignment = "Check signed integer limits"),
            work("syntax", "backup", assignment = "Check decimal syntax against grammar"))))
        val vacancy = JSONObject().put("id", "test-gap").put("template_member", "author").put("role", "User-appointed tester")
            .put("scope", "Check Unicode digit rejection").put("reason", "An available tester can cover the remaining input gap")
        val nextPlan = assessment(work("unicode", "recruit:test-gap", assignment = "Verify that non-ASCII digits are rejected"))
            .put("recruit", JSONArray().put(vacancy))
        val completed = settle(first, nextPlan, mapOf("bounds" to AgentSubagentStatus.FAILED))
        val next = advance(completed)
        // reviewer has no comparable observations, so it must not be treated as free or successful.
        assertEquals("author", workers(next).single().context[CollaborationResearchWorkflow.PERSON])
        val withoutUnknown = completed.copy(definition = completed.definition.copy(members = completed.definition.members.filterNot {
            it.memberId == "reviewer" && it.context[CollaborationGoalLoop.ROSTER] == "true"
        }))
        val adapted = advance(withoutUnknown)
        assertEquals("backup", workers(adapted).single().context[CollaborationResearchWorkflow.PERSON])
        assertTrue(adapted.definition.members.none { it.context[CollaborationGoalRecruitment.PUBLISHED] == "false" })
        val explicit = advance(settle(first, assessment(work("unicode", "author", assignment = "Verify non-ASCII digit rejection")),
            mapOf("bounds" to AgentSubagentStatus.FAILED)))
        assertEquals("author", workers(explicit).single().context[CollaborationResearchWorkflow.PERSON])
    }

    @Test fun promptExposesOnlyScopedMetadataAndKeepsIndependentMembersIsolated() {
        val first = advance(initial(assessment(work("build"))))
        val second = advance(settle(first, assessment(work("review", "reviewer", "VERIFY", "Review all parser branches")
            .put("depends_on", JSONArray().put("build")).put("independent_review", true))))
        val lead = second.definition.members.first { it.memberId == second.definition.primaryMemberId }
        val leadRequest = second.request.copy(runId = "child-run", parentRunId = "run")
        val leadPrompt = CollaborationTeamOrganizationContext.prompt(lead, leadRequest, true)
        assertTrue(leadPrompt.contains("succeeded_dispatches"))
        assertTrue(leadPrompt.contains("\"quality\":null"))
        assertFalse(leadPrompt.contains("\"quality\":1"))
        val reviewer = workers(second).single()
        val isolated = CollaborationTeamOrganizationContext.prompt(reviewer, leadRequest, true)
        assertTrue(isolated.contains("Host assignment organization"))
        assertFalse(isolated.contains("succeeded_dispatches"))
        assertFalse(isolated.contains("dispatch_sample"))
        assertTrue(CollaborationTeamOrganizationContext.prompt(lead, leadRequest.copy(parentRunId = "other"), true)
            .contains("measurements unknown"))
        assertTrue(CollaborationTeamOrganizationContext.prompt(lead.copy(context = lead.context + ("collaboration_group_id" to "other")),
            leadRequest, true).contains("measurements unknown"))
        assertEquals("", CollaborationTeamOrganizationContext.prompt(lead.copy(context = lead.context - CollaborationGoalLoop.ENABLED),
            leadRequest, true))
    }

    @Test fun cancelledGoalCannotBeAdvancedByOrganization() {
        val record = initial(assessment(work("build"))).let { it.copy(events = it.events.dropLast(1) +
            AgentSubagentEvent(20, "run", kind = AgentSubagentEventKinds.SUPERVISOR_CANCELLED, runStatus = AgentSubagentRunStatus.CANCELLED)) }
        assertNull(CollaborationGoalLoop.advance(record, "lead", Long.MAX_VALUE, true))
    }

    @Test fun memberContextCannotOverrideTheHostOrganizationProjection() {
        val next = advance(initial(assessment(work("build"))))
        val claimed = mapOf(CollaborationTeamOrganizationContext.SUMMARY to "member claims perfect quality",
            CollaborationTeamOrganizationHistory.HISTORY to "member claims zero cost")
        val dispatched = next.request.context + claimed + CollaborationTeamOrganizationContext.dispatchContext(next.request)
        assertEquals(next.request.context[CollaborationTeamOrganizationContext.SUMMARY], dispatched[CollaborationTeamOrganizationContext.SUMMARY])
        assertEquals("", dispatched[CollaborationTeamOrganizationHistory.HISTORY])
        assertEquals("", dispatched[CollaborationTeamOrganizationProjection.COMPLETIONS])
        assertEquals("", CollaborationTeamOrganizationContext.dispatchContext(next.request, workers(next).single())[
            CollaborationTeamOrganizationContext.SUMMARY])
        val absent = initial(assessment()).request
        assertTrue(CollaborationTeamOrganizationContext.dispatchContext(absent).values.all(String::isEmpty))
    }

    @Test fun rejectedProjectionInvalidatesPlanSummaryWithoutErasingHostHistory() {
        val plan = assessment(work("new-domain", "recruit:new-role", assignment = "Check the binary wire encoding"))
            .put("recruit", JSONArray().put(JSONObject().put("id", "new-role").put("template_member", "author")
                .put("role", "Protocol specialist").put("scope", "Binary wire format validation").put("reason", "Distinct protocol responsibility")))
        val first = advance(initial(assessment(work("build"))))
        val pending = advance(settle(first, plan))
        assertFalse(pending.request.context[CollaborationTeamOrganizationContext.SUMMARY].toString().isBlank())
        val rejected = CollaborationGoalRecruitment.applyProjection(pending, emptyMap())
        assertEquals("", rejected.request.context[CollaborationTeamOrganizationContext.SUMMARY])
        assertEquals(pending.request.context[CollaborationTeamOrganizationHistory.HISTORY], rejected.request.context[CollaborationTeamOrganizationHistory.HISTORY])
        assertEquals(people().map { it.memberId }.toSet(), roster(rejected).map { it.memberId }.toSet())
        assertTrue(workers(rejected).isEmpty())
    }

    @Test fun productionPromptBridgeIncludesHostPolicyWithoutChangingLockedAuthority() = runBlocking {
        val first = advance(initial(assessment(work("build"))))
        val next = advance(settle(first, assessment(work("review", "reviewer", "VERIFY", "Review parser against the specification")
            .put("depends_on", JSONArray().put("build")).put("independent_review", true))))
        val actions = mutableListOf<AgentAction>()
        val registration = AgentRegistration(agentId = "fixture", installationId = "fixture-installation", deviceId = "fixture-device",
            providerId = "galaxyssi-connectors", displayName = "Fixture", kind = AgentConnectorKind.AGENT,
            location = AgentResourceLocation.TRUSTED_DESKTOP, status = AgentEndpointStatus.ONLINE,
            capabilities = setOf(AgentCapability.RESEARCH), protocol = AgentProtocolRange("1.0", "1.0", "1.0",
                setOf("run.cancel", "run.recover", "run.events", "message.respond", "message.observe")),
            connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED, adapterType = "fixture")
        val provider = ActionExecutorAgentProvider(registrationSource = { listOf(registration) }, delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                actions.add(action)
                return AgentActionResult(action.id, true, assessment().toString())
            }
        })
        val directory = AgentAdapterDirectory().apply { register(provider) }
        val worker = ActionExecutorAgentTeamMemberWorker(provider, directory,
            screenProvider = { ScreenContext(foregroundApp = "Fixture", pageTitle = "Organization") })
        try {
            listOf(next.definition.members.first { it.memberId == next.definition.primaryMemberId }, workers(next).single()).forEach { member ->
                worker.execute(AgentTeamMemberExecutionContext(member,
                    next.request.copy(runId = stableAgentTeamMemberRunId("run", member.memberId), parentRunId = "run",
                        requiredCapabilities = member.requiredCapabilities, idempotencyKey = "run:${member.memberId}"),
                    AgentSubagentContextHandoff("", emptyList(), 0, 8000, false), 1, AgentSubagentProvenance()))
            }
        } finally {
            provider.disconnect()
        }
        assertEquals(2, actions.size)
        assertTrue(actions[0].parameters.getValue("prompt").contains("Host organization policy"))
        assertTrue(actions[0].parameters.getValue("prompt").contains("succeeded_dispatches"))
        assertFalse(actions[1].parameters.getValue("prompt").contains("succeeded_dispatches"))
        assertTrue(actions[1].parameters.getValue("prompt").contains("Host assignment organization"))
        actions.forEach {
            assertEquals("true", it.parameters["manual_target_locked"])
            assertEquals("authorized-model", it.parameters["manual_model_id"])
            assertEquals("fixture", it.parameters["connector_id"])
        }
    }
}
