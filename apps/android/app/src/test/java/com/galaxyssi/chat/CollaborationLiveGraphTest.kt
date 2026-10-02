package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationLiveGraphTest {
    @Test fun requiresLiveOptInAndAnAuthorizedRoster() {
        val ready = completed(fixture(), PRODUCER)
        val disabled = ready.copy(definition = ready.definition.copy(members = ready.definition.members.map {
            it.copy(context = it.context - CollaborationLiveGraph.ENABLED)
        }))
        val noRoster = ready.copy(definition = ready.definition.copy(members = ready.definition.members.map {
            it.copy(context = it.context + (CollaborationGoalLoop.ROSTER to "false"))
        }))

        for (record in listOf(disabled, noRoster)) {
            assertFalse(CollaborationLiveGraph.enabled(record.definition))
            assertEquals(record, CollaborationLiveGraph.update(record, terminalIds(record), 100))
        }
        assertTrue(CollaborationLiveGraph.enabled(ready.definition))
        assertEquals(1, planners(CollaborationLiveGraph.update(ready, terminalIds(ready), 100)).size)
    }

    @Test fun requiresPersistedResultsAndExactCompletedDispatchIds() {
        val ready = completed(fixture(), PRODUCER)
        val wrongIds = setOf(PRODUCER_WORK, AUTHOR, PROVIDER, SLOW, "unknown-dispatch")
        assertEquals(ready, CollaborationLiveGraph.update(ready, wrongIds, 100))
        assertEquals(ready, CollaborationLiveGraph.update(ready, emptySet(), 100))

        val updated = CollaborationLiveGraph.update(ready, wrongIds + PRODUCER, 100)
        val planner = planners(updated).single()
        assertEquals(listOf(PRODUCER), strings(planner.context[CollaborationLiveGraph.SOURCES]))
        assertEquals(setOf(PRODUCER), planner.dependsOnAgentIds)
        assertPreserved(ready, updated)
    }

    @Test fun onePlannerInFlightCoalescesNewCompletionsIntoOneFollowingCheckpoint() {
        val first = planned()
        val firstPlanner = planners(first).single()
        val moreResults = completed(first, SOURCE_B, SOURCE_C)

        assertEquals(moreResults, CollaborationLiveGraph.update(moreResults, terminalIds(moreResults), 110))
        val returned = terminal(moreResults, firstPlanner.memberId, expansion().toString())
        val next = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        val secondPlanner = planners(next).single { it.memberId != firstPlanner.memberId }

        assertEquals(2, planners(next).size)
        assertEquals(listOf(SOURCE_B, SOURCE_C).sorted(), strings(secondPlanner.context[CollaborationLiveGraph.SOURCES]))
        assertEquals(setOf(PRODUCER, SOURCE_B, SOURCE_C), secondPlanner.dependsOnAgentIds)
        assertFalse(secondPlanner.dependsOnAgentIds.contains(firstPlanner.memberId))
        assertFalse(secondPlanner.dependsOnAgentIds.contains(SLOW))
        assertEquals(setOf(firstPlanner.memberId), applied(next))
        assertEquals(next, CollaborationLiveGraph.update(reopen(next), terminalIds(next), 130))
        assertPreserved(returned, next)
    }

    @Test fun quiescentWorkLeavesContinuationToTheStableFinalCoordinator() {
        val ready = completed(fixture(), PRODUCER, SOURCE_B, SOURCE_C, SLOW)
        assertEquals(ready, CollaborationLiveGraph.update(ready, terminalIds(ready), 100))
        assertTrue(planners(ready).isEmpty())

        val inFlight = planned()
        val planner = planners(inFlight).single()
        val returned = terminal(completed(inFlight, SOURCE_B, SOURCE_C, SLOW), planner.memberId, expansion().toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        assertEquals(returned.definition, updated.definition)
        assertEquals(listOf(planner), planners(updated))
        assertEquals(setOf(planner.memberId), applied(updated))
        assertEquals(FINAL, updated.definition.primaryMemberId)
        assertPreserved(returned, updated)
    }

    @Test fun validIndependentReviewAppendsOnceWithoutReplacingRunningWorkOrFinalIdentity() {
        val first = planned()
        val planner = planners(first).single()
        val returned = terminal(first, planner.memberId, expansion(review()).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        val review = work(updated, REVIEW_WORK)

        assertEquals(returned.definition.members.size + 1, updated.definition.members.size)
        assertEquals(REVIEWER, review.context[CollaborationResearchWorkflow.PERSON])
        assertEquals(AgentDeliveryMode.OBSERVE, review.deliveryMode)
        assertEquals("VERIFY", review.context[CollaborationResearchWorkflow.STAGE])
        assertEquals("true", review.context[CollaborationWorkGraph.INDEPENDENT])
        assertEquals("success", review.context[CollaborationWorkGraph.POLICY])
        assertEquals(setOf(PRODUCER), review.dependsOnAgentIds)
        assertEquals(member(returned, REVIEWER).requiredCapabilities, review.requiredCapabilities)
        assertEquals(member(returned, REVIEWER).context["collaboration_model_id"], review.context["collaboration_model_id"])
        assertFalse(review.memberId in setOf(REVIEW_WORK, REVIEWER, PROVIDER, planner.memberId, FINAL))
        assertNotEquals(stableAgentTeamMemberRunId(RUN, PRODUCER), stableAgentTeamMemberRunId(RUN, review.memberId))
        assertEquals(member(returned, SLOW), member(updated, SLOW))
        assertEquals(AgentSubagentStatus.RUNNING, updated.events.last { it.childId == SLOW }.childStatus)
        assertEquals(setOf(HISTORICAL_WORK, PRODUCER_WORK), CollaborationGoalLoop.finishedWork(updated))
        assertEquals(setOf(planner.memberId), applied(updated))
        assertEquals("", updated.request.context[CollaborationLiveGraph.FEEDBACK])
        assertEquals(updated, CollaborationLiveGraph.update(reopen(updated), terminalIds(updated), 130))
        assertPreserved(returned, updated)
    }

    @Test fun conflictingRedefinitionsRejectTheWholeExpansion() {
        val changes = listOf<(JSONObject) -> Unit>(
            { it.put("assignment", "Replace the running assignment") },
            { it.put("member", REVIEWER) },
            { it.put("stage", "VERIFY") },
            { it.put("depends_on", JSONArray().put(PRODUCER_WORK)) },
            { it.put("dependency_policy", "terminal") },
            { it.put("independent_review", true) }
        )
        for (change in changes) {
            val original = item(SLOW_WORK, SLOW_PERSON)
            change(original)
            assertRejected(expansion(safeAddition(), original), "rewrite existing work")
        }
    }

    @Test fun cyclesRejectTheWholeExpansionInsteadOfAppendingTheValidSibling() {
        assertRejected(expansion(safeAddition(),
            item("cycle-a", AUTHOR, "cycle-b"), item("cycle-b", REVIEWER, "cycle-a")), "cycle")
    }

    @Test fun selfReviewUsesPersonIdentityRatherThanProviderOrDispatchIdentity() {
        assertRejected(expansion(safeAddition(), review().put("member", AUTHOR)), "different author")
    }

    @Test fun unknownMembersAndDependenciesRejectTheWholeExpansion() {
        for (unknown in listOf("outsider", "recruit:unapproved", PROVIDER, PRODUCER)) {
            assertRejected(expansion(safeAddition(), item("unknown-person-work", unknown)), "authorized member")
        }
        assertRejected(expansion(safeAddition(), item("unknown-input", REVIEWER, "missing-work")), "dependency")
        assertRejected(expansion(safeAddition(), item("duplicate", AUTHOR), item("duplicate", REVIEWER)), "Duplicate work IDs")
    }

    @Test fun plannerCannotDeclareAchievementRewriteCriteriaOrRequestNewAuthority() {
        val forbidden = mapOf<String, Any>(
            "decision" to "achieved",
            "criteria" to JSONArray().put(JSONObject().put("id", "weakened").put("status", "met")),
            "goal" to "An easier goal",
            "recruit" to JSONArray().put(JSONObject().put("id", "new-person"))
        )
        for ((key, value) in forbidden) {
            assertRejected(expansion(safeAddition()).put(key, value), "cannot change goal criteria or authority")
        }
        assertRejected(expansion(safeAddition()).put("format", CollaborationGoalLoop.FORMAT), "work-expansion JSON contract")
    }

    @Test fun failedTruncatedAndMalformedPlannerResultsAreAcknowledgedWithoutPartialWork() {
        val cases = listOf(
            Triple(AgentSubagentStatus.FAILED, false, expansion(safeAddition()).toString()),
            Triple(AgentSubagentStatus.SUCCEEDED, true, expansion(safeAddition()).toString()),
            Triple(AgentSubagentStatus.SUCCEEDED, false, "not a JSON plan")
        )
        for ((status, truncated, output) in cases) {
            val first = planned()
            val planner = planners(first).single()
            val returned = terminal(first, planner.memberId, output, status, truncated)
            val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
            assertEquals(returned.definition, updated.definition)
            assertTrue(updated.request.context[CollaborationLiveGraph.FEEDBACK].toString().isNotBlank())
            assertEquals(setOf(planner.memberId), applied(updated))
            assertEquals(updated, CollaborationLiveGraph.update(reopen(updated), terminalIds(updated), 130))
            assertPreserved(returned, updated)
        }
    }

    @Test fun copiedCheckpointReplaysTheSameAppendAndPreservesAllOriginalRequestFields() {
        val first = planned()
        val returned = terminal(first, planners(first).single().memberId, expansion(review()).toString())
        val before = reopen(returned)
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        val recovered = CollaborationLiveGraph.update(reopen(returned), terminalIds(returned), 120)

        assertEquals(before, returned)
        assertEquals(updated, recovered)
        assertEquals(updated, CollaborationLiveGraph.update(reopen(recovered), terminalIds(recovered), 200))
        assertEquals(returned.request.goal, recovered.request.goal)
        for (key in listOf(CollaborationGoalLoop.CRITERIA, CollaborationGoalLoop.ROUND,
            CollaborationGoalLoop.FINISHED_WORK, CollaborationGoalLoop.FINISHED_AUTHORS)) {
            assertEquals(returned.request.context[key], recovered.request.context[key])
        }
        assertPreserved(returned, recovered)
    }

    @Test fun completedInputOrderDoesNotChangePlannerIdentityAndDifferentRunsOrRoundsDo() {
        val left = completed(fixture(), PRODUCER, SOURCE_B)
        val right = completed(fixture(), SOURCE_B, PRODUCER)
        val first = planners(CollaborationLiveGraph.update(left, linkedSetOf(PRODUCER, SOURCE_B), 100)).single()
        val reordered = planners(CollaborationLiveGraph.update(right, linkedSetOf(SOURCE_B, PRODUCER), 100)).single()
        assertEquals(first, reordered)
        assertEquals(listOf(PRODUCER, SOURCE_B).sorted(), strings(first.context[CollaborationLiveGraph.SOURCES]))

        val otherRun = completed(fixture(runId = "another-supervisor"), PRODUCER, SOURCE_B)
        val otherRound = completed(fixture(round = "8"), PRODUCER, SOURCE_B)
        assertNotEquals(first.memberId, planners(CollaborationLiveGraph.update(otherRun, terminalIds(otherRun), 100)).single().memberId)
        assertNotEquals(first.memberId, planners(CollaborationLiveGraph.update(otherRound, terminalIds(otherRound), 100)).single().memberId)
    }

    @Test fun plannerAndIndependentReviewKeepOriginalSourceVisibilityWithoutUnrelatedWork() {
        val first = planned()
        val planner = planners(first).single()
        val returned = terminal(first, planner.memberId, expansion(review()).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        val review = work(updated, REVIEW_WORK)

        for (node in listOf(planner, review)) {
            val access = access(updated, node)
            assertTrue(access.canRead(evidence(updated, PRODUCER)))
            assertFalse(access.canRead(evidence(updated, SOURCE_B)))
            assertFalse(access.canRead(evidence(updated, SLOW)))
            assertEquals(setOf(PRODUCER), node.dependsOnAgentIds)
        }
        assertFalse(access(updated, review).canRead(evidence(updated, planner.memberId)))
        assertFalse(access(updated, member(updated, SOURCE_B)).canRead(evidence(updated, review.memberId)))
    }

    @Test fun existingIndependentReviewRemainsInInventoryAndCannotBeRedefinedByLaterPlanner() {
        val first = planned()
        val withReviewResult = terminal(first, planners(first).single().memberId, expansion(review()).toString())
        val withReview = CollaborationLiveGraph.update(withReviewResult, terminalIds(withReviewResult), 120)
        val completedB = completed(withReview, SOURCE_B)
        val next = CollaborationLiveGraph.update(completedB, terminalIds(completedB), 130)
        val planner = planners(next).single { it.memberId !in applied(next) }
        val completed = next.events.mapNotNull { it.result }.associateBy { it.childId }
        val inventory = JSONObject(CollaborationLiveGraph.inventory(next.definition, completed)).getJSONArray("items")
        val savedReview = (0 until inventory.length()).map { inventory.getJSONObject(it) }.single { it.getString("id") == REVIEW_WORK }
        assertEquals(REVIEWER, savedReview.getString("member"))
        assertEquals("active_or_queued", savedReview.getString("status"))
        assertEquals("true", work(next, REVIEW_WORK).context[CollaborationWorkGraph.INDEPENDENT])

        val returned = terminal(next, planner.memberId,
            expansion(safeAddition(), review().put("independent_review", false)).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 140)
        assertEquals(returned.definition, updated.definition)
        assertTrue(updated.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains("rewrite existing work"))
        assertEquals(planners(next).map { it.memberId }.toSet(), applied(updated))
        assertPreserved(returned, updated)
    }

    @Test fun historicalCompletedWorkIsNotRedispatchedAndUsesItsSavedAuthorForReview() {
        val first = planned()
        val historicalReview = item("historical-review", REVIEWER, HISTORICAL_WORK)
            .put("stage", "VERIFY").put("independent_review", true)
        val returned = terminal(first, planners(first).single().memberId,
            expansion(item(HISTORICAL_WORK, REVIEWER), historicalReview).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        val review = work(updated, "historical-review")
        assertEquals(returned.definition.members.size + 1, updated.definition.members.size)
        assertFalse(updated.definition.members.any { it.context[CollaborationGoalLoop.WORK_ID] == HISTORICAL_WORK })
        assertTrue(review.dependsOnAgentIds.isEmpty())
        assertEquals(listOf(HISTORICAL_WORK), strings(review.context[CollaborationWorkGraph.PREVIOUS_DEPENDENCIES]))
        assertEquals(AUTHOR, CollaborationGoalLoop.finishedAuthors(updated)[HISTORICAL_WORK])
        assertPreserved(returned, updated)

        assertRejected(expansion(safeAddition(), item(HISTORICAL_WORK, REVIEWER),
            item("historical-self-review", AUTHOR, HISTORICAL_WORK).put("independent_review", true)), "different author")
    }

    @Test fun identicalCurrentWorkIsNotRedispatchedAndDependenciesMayTargetRunningWork() {
        val first = planned()
        val returned = terminal(first, planners(first).single().memberId, expansion(
            item(PRODUCER_WORK, AUTHOR), item(SLOW_WORK, SLOW_PERSON),
            item("after-slow", REVIEWER, SLOW_WORK).put("dependency_policy", "terminal")).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        assertEquals(returned.definition.members.size + 1, updated.definition.members.size)
        assertEquals(setOf(SLOW), work(updated, "after-slow").dependsOnAgentIds)
        assertEquals("terminal", work(updated, "after-slow").context[CollaborationWorkGraph.POLICY])
        assertEquals(member(returned, PRODUCER), member(updated, PRODUCER))
        assertEquals(member(returned, SLOW), member(updated, SLOW))
        assertPreserved(returned, updated)
    }

    @Test fun failedWorkCanTriggerDiagnosticPlanningWithoutBecomingSuccessfulEvidence() {
        val failed = terminal(fixture(), PRODUCER, "Producer failed", AgentSubagentStatus.FAILED)
        val first = CollaborationLiveGraph.update(failed, terminalIds(failed), 100)
        val planner = planners(first).single()
        assertEquals(listOf(PRODUCER), strings(planner.context[CollaborationLiveGraph.SOURCES]))
        assertEquals(setOf(PRODUCER), planner.dependsOnAgentIds)
        val returned = terminal(first, planner.memberId, expansion(
            item("diagnose-producer", REVIEWER, PRODUCER_WORK).put("dependency_policy", "terminal")).toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)

        assertEquals(setOf(PRODUCER), work(updated, "diagnose-producer").dependsOnAgentIds)
        assertEquals("terminal", work(updated, "diagnose-producer").context[CollaborationWorkGraph.POLICY])
        assertFalse(CollaborationGoalLoop.finishedWork(updated).contains(PRODUCER_WORK))
        assertFalse(CollaborationGoalLoop.finishedAuthors(updated).containsKey(PRODUCER_WORK))
        assertEquals(member(returned, PRODUCER), member(updated, PRODUCER))
        assertPreserved(returned, updated)
    }

    @Test fun finalStartedOrSupervisorTerminalPreventsAnyFurtherExpansion() {
        val first = planned()
        val returned = terminal(first, planners(first).single().memberId, expansion(review()).toString())
        val finalStarted = returned.copy(events = returned.events + AgentSubagentEvent(
            nextSequence(returned), RUN, FINAL, AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING, timestampMillis = 90))
        val finalFinished = terminal(returned, FINAL, "Final owns continuation")
        val terminalRecords = AgentSubagentRunStatus.values().map { status ->
            returned.copy(events = returned.events + AgentSubagentEvent(nextSequence(returned), RUN,
                kind = "test.supervisor.terminal", runStatus = status, timestampMillis = 90))
        }
        for (record in terminalRecords + listOf(finalStarted, finalFinished)) {
            assertEquals(record, CollaborationLiveGraph.update(record, terminalIds(record), 120))
            assertTrue(applied(record).isEmpty())
        }
    }

    private fun fixture(runId: String = RUN, round: String = "7"): AgentTeamExecutionRecord {
        val people = listOf(LEAD, AUTHOR, REVIEWER, SLOW_PERSON).map { person ->
            AgentTeamMember(PROVIDER, AgentDeliveryMode.IGNORE,
                requiredCapabilities = setOf(AgentCapability.REASONING), role = "Role of $person",
                instanceId = person, context = mapOf(
                    CollaborationLiveGraph.ENABLED to "1", CollaborationGoalLoop.ENABLED to "1",
                    CollaborationGoalLoop.ROSTER to "true", CollaborationResearchWorkflow.PERSON to person,
                    CollaborationResearchWorkflow.STAGE to "DELIVER", "collaboration_group_id" to GROUP,
                    "collaboration_name" to person, "collaboration_model_id" to "authorized-model"))
        }
        fun node(id: String, workId: String, person: String) = people.single { it.memberId == person }.copy(
            instanceId = id, deliveryMode = AgentDeliveryMode.OBSERVE, objective = "Produce $workId",
            context = people.single { it.memberId == person }.context + mapOf(
                CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to workId,
                CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to "success",
                CollaborationWorkGraph.INDEPENDENT to "false"))
        val work = listOf(node(PRODUCER, PRODUCER_WORK, AUTHOR), node(SOURCE_B, "source-B", REVIEWER),
            node(SOURCE_C, "source-C", AUTHOR), node(SLOW, SLOW_WORK, SLOW_PERSON))
        val final = people.first().copy(instanceId = FINAL, deliveryMode = AgentDeliveryMode.RESPOND,
            objective = "Assess the original goal", dependsOnAgentIds = work.map { it.memberId }.toSet(),
            context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        val request = AgentRunRequest(GROUP, "exact-turn", "exact-task", runId = runId, parentRunId = "exact-parent",
            goal = "Original goal: preserve every requirement.\nDo not replace this goal.", idempotencyKey = "exact-request-key",
            createdAtMillis = 1, context = mapOf(
                CollaborationGoalLoop.CRITERIA to "[{\"id\":\"criterion-1\",\"requirement\":\"Independently verified delivery\",\"status\":\"open\",\"evidence\":[]}]",
                CollaborationGoalLoop.ROUND to round, CollaborationGoalLoop.HOST_ACCEPTANCE to "1",
                CollaborationGoalLoop.FINISHED_WORK to JSONArray().put(HISTORICAL_WORK).toString(),
                CollaborationGoalLoop.FINISHED_AUTHORS to JSONObject().put(HISTORICAL_WORK, AUTHOR).toString(),
                "unrelated_context" to "must survive"))
        val events = listOf(AgentSubagentEvent(1, runId, kind = AgentSubagentEventKinds.SUPERVISOR_STARTED, timestampMillis = 1)) +
            work.mapIndexed { index, member -> AgentSubagentEvent(index + 2L, runId, member.memberId,
                AgentSubagentEventKinds.CHILD_RUNNING, childStatus = AgentSubagentStatus.RUNNING, timestampMillis = 2) } +
            AgentSubagentEvent(6, runId, FINAL, AgentSubagentEventKinds.CHILD_QUEUED,
                childStatus = AgentSubagentStatus.QUEUED, timestampMillis = 2)
        return AgentTeamExecutionRecord(AgentTeamDefinition("exact-team", PROVIDER, people + work + final,
            primaryInstanceId = FINAL), request, events, updatedAtMillis = 10)
    }

    private fun planned(): AgentTeamExecutionRecord {
        val ready = completed(fixture(), PRODUCER)
        return CollaborationLiveGraph.update(ready, terminalIds(ready), 100)
    }

    private fun item(id: String, person: String = REVIEWER, vararg dependencies: String) = JSONObject()
        .put("id", id).put("member", person).put("stage", "EXECUTE").put("assignment", "Produce $id")
        .put("depends_on", JSONArray(dependencies.toList()))

    private fun review() = item(REVIEW_WORK, REVIEWER, PRODUCER_WORK)
        .put("stage", "VERIFY").put("independent_review", true)

    private fun safeAddition() = item("valid-sibling", REVIEWER)

    private fun expansion(vararg work: JSONObject) = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
        .put("summary", "Check the new evidence while other work continues").put("work", JSONArray(work.toList()))

    private fun completed(record: AgentTeamExecutionRecord, vararg ids: String) =
        ids.fold(record) { current, id -> terminal(current, id, "Observed result from $id") }

    private fun terminal(record: AgentTeamExecutionRecord, id: String, output: String,
                         status: AgentSubagentStatus = AgentSubagentStatus.SUCCEEDED,
                         truncated: Boolean = false): AgentTeamExecutionRecord {
        require(record.definition.members.any { it.memberId == id })
        val sequence = nextSequence(record)
        val result = AgentSubagentChildResult(record.request.runId, id, record.request.runId, 1, status,
            output = output, outputTruncated = truncated, startedAtMillis = 2, completedAtMillis = sequence)
        return record.copy(events = record.events + AgentSubagentEvent(sequence, record.request.runId, id,
            if (status == AgentSubagentStatus.SUCCEEDED) AgentSubagentEventKinds.CHILD_SUCCEEDED else AgentSubagentEventKinds.CHILD_FAILED,
            childStatus = status, result = result, timestampMillis = sequence))
    }

    private fun nextSequence(record: AgentTeamExecutionRecord) = (record.events.maxOfOrNull { it.sequence } ?: 0L) + 1L

    private fun terminalIds(record: AgentTeamExecutionRecord) = record.events.mapNotNull { it.result }
        .filter { it.status.isTerminal }.map { it.childId }.toSet()

    private fun planners(record: AgentTeamExecutionRecord) = record.definition.members.filter(CollaborationLiveGraph::planner)
    private fun member(record: AgentTeamExecutionRecord, id: String) = record.definition.members.single { it.memberId == id }
    private fun work(record: AgentTeamExecutionRecord, id: String) =
        record.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == id }
    private fun strings(raw: String?) = JSONArray(raw ?: "[]").let { array -> (0 until array.length()).map { array.getString(it) } }
    private fun applied(record: AgentTeamExecutionRecord) = strings(record.request.context[CollaborationLiveGraph.APPLIED]?.toString()).toSet()

    // Recreate policy inputs without depending on the separately tested encrypted codec.
    private fun reopen(record: AgentTeamExecutionRecord) = record.copy(
        definition = record.definition.copy(members = record.definition.members.map {
            it.copy(context = it.context.toMap(), dependsOnAgentIds = it.dependsOnAgentIds.toSet())
        }), request = record.request.copy(context = record.request.context.toMap()),
        events = record.events.map { it.copy(result = it.result?.copy()) })

    private fun assertRejected(plan: JSONObject, feedback: String) {
        val first = planned()
        val planner = planners(first).single()
        val returned = terminal(first, planner.memberId, plan.toString())
        val updated = CollaborationLiveGraph.update(returned, terminalIds(returned), 120)
        assertEquals(returned.definition, updated.definition)
        assertTrue(updated.request.context[CollaborationLiveGraph.FEEDBACK].toString(),
            updated.request.context[CollaborationLiveGraph.FEEDBACK].toString().contains(feedback, ignoreCase = true))
        assertEquals(setOf(planner.memberId), applied(updated))
        assertEquals(updated, CollaborationLiveGraph.update(reopen(updated), terminalIds(updated), 130))
        assertPreserved(returned, updated)
    }

    private fun assertPreserved(before: AgentTeamExecutionRecord, after: AgentTeamExecutionRecord) {
        val mutableContext = setOf(CollaborationLiveGraph.APPLIED, CollaborationLiveGraph.FEEDBACK)
        assertEquals(before.request.copy(context = before.request.context - mutableContext),
            after.request.copy(context = after.request.context - mutableContext))
        assertEquals(before.events, after.events)
        assertEquals(before.interruptedAtMillis, after.interruptedAtMillis)
        assertEquals(before.definition.copy(members = after.definition.members), after.definition)
        assertEquals(before.definition.members.map { it.memberId }, after.definition.members.take(before.definition.members.size).map { it.memberId })
        before.definition.members.filter { it.memberId != before.definition.primaryMemberId }.forEach {
            assertEquals(it, member(after, it.memberId))
        }
        val oldFinal = member(before, before.definition.primaryMemberId)
        val newFinal = member(after, after.definition.primaryMemberId)
        val appended = after.definition.members.drop(before.definition.members.size).map { it.memberId }
        assertEquals(oldFinal.copy(dependsOnAgentIds = oldFinal.dependsOnAgentIds + appended), newFinal)
        assertEquals(after.definition.members.size, after.definition.members.map { it.memberId }.distinct().size)
        assertTrue(after.updatedAtMillis >= before.updatedAtMillis)
    }

    private fun access(record: AgentTeamExecutionRecord, node: AgentTeamMember) = CollaborationWorkspaceAccess(
        GROUP, record.request.runId, record.request.messageId, record.request.context.getValue(CollaborationGoalLoop.ROUND).toString().toLong(),
        node.memberId, node.context.getValue(CollaborationResearchWorkflow.PERSON), node.dependsOnAgentIds)

    private fun evidence(record: AgentTeamExecutionRecord, node: String) = JSONObject().put("group_id", GROUP)
        .put("run_id", record.request.runId).put("turn_id", record.request.messageId)
        .put("round", record.request.context.getValue(CollaborationGoalLoop.ROUND).toString().toLong()).put("node_id", node)

    private companion object {
        const val GROUP = "exact-group"
        const val RUN = "exact-supervisor"
        const val PROVIDER = "shared-provider"
        const val LEAD = "person:coordinator"
        const val AUTHOR = "person:author"
        const val REVIEWER = "person:reviewer"
        const val SLOW_PERSON = "person:slow"
        const val FINAL = "dispatch:final"
        const val PRODUCER = "dispatch:producer/A"
        const val SOURCE_B = "dispatch:source/B"
        const val SOURCE_C = "dispatch:source/C"
        const val SLOW = "dispatch:slow"
        const val PRODUCER_WORK = "producer-A"
        const val SLOW_WORK = "slow-work"
        const val REVIEW_WORK = "review-producer-A"
        const val HISTORICAL_WORK = "finished-in-prior-round"
    }
}
