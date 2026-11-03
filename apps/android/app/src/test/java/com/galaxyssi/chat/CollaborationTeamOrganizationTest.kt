package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTeamOrganizationTest {
    private fun person(id: String, role: String = "Tester", model: String = "authorized") = AgentTeamMember(
        "codex", AgentDeliveryMode.IGNORE, role = role, instanceId = id, context = mapOf(
            CollaborationResearchWorkflow.PERSON to id, CollaborationGoalLoop.ROSTER to "true",
            "collaboration_group_id" to "group", "collaboration_model_id" to model, "collaboration_name" to id))
    private fun people() = listOf(person("lead", "Coordinator"), person("a"), person("b"))
    private fun work(id: String = "job", member: String = "a", stage: String = "EXECUTE", assignment: String = "Run fixture A") =
        JSONObject().put("id", id).put("member", member).put("stage", stage).put("assignment", assignment)
    private fun recruit(id: String = "gap") = JSONObject().put("id", id).put("template_member", "a")
        .put("role", "Tester").put("scope", "Check fixture A").put("reason", "Independent test coverage")
    private fun checkpoint() = CollaborationTeamOrganization.Checkpoint(coordinatorId = "lead", settled = true)
    private fun plan(jobs: List<JSONObject>, recruits: JSONArray? = null,
                     checkpoint: CollaborationTeamOrganization.Checkpoint = checkpoint(), roster: List<AgentTeamMember> = people()) =
        CollaborationGoalRecruitment.plan(roster, recruits, JSONArray(jobs), listOf("NewTester"), checkpoint)
    private fun sample(id: String, outcome: CollaborationTeamOrganization.Outcome = CollaborationTeamOrganization.Outcome.SUCCEEDED,
                       elapsed: Long? = null, cost: Long? = null) = CollaborationTeamOrganization.Observation(
        "dispatch-$id", id, "codex", "authorized", "Tester", "EXECUTE", "old-$id", outcome = outcome,
        elapsedMillis = elapsed, costUsdMicros = cost)

    @Test fun duplicatePlanIsRejectedWithoutMutatingInputOrCreatingPeople() {
        val jobs = listOf(work(), work("duplicate", "recruit:gap"))
        val before = jobs.map { it.toString() }
        val result = plan(jobs, JSONArray().put(recruit()))
        assertTrue(result.error.contains("Duplicate work"))
        assertEquals(people(), result.people)
        assertTrue(result.aliases.isEmpty())
        assertEquals(before, jobs.map { it.toString() })
    }

    @Test fun duplicateCheckRunsWithoutRecruitment() {
        assertTrue(plan(listOf(work(), work("again", "b"))).error.contains("Duplicate work"))
    }

    @Test fun caseSensitiveCodeAndDifferentInputsAreNotCollapsed() {
        assertEquals("", plan(listOf(work(assignment = "Run A"), work("other", "b", assignment = "Run a"))).error)
        assertEquals("", plan(listOf(work(assignment = "print('a b')"), work("other", "b", assignment = "print('a  b')"))).error)
        assertEquals("", plan(listOf(work().put("depends_on", JSONArray().put("v1")),
            work("other", "b").put("depends_on", JSONArray().put("v2")))).error)
    }

    @Test fun independentReviewersArePreservedButSameReviewerDuplicationIsRejected() {
        assertEquals("", plan(listOf(work(stage = "VERIFY"), work("second", "b", "VERIFY"))).error)
        assertTrue(plan(listOf(work(stage = "VERIFY"), work("second", "a", "VERIFY"))).error.contains("Duplicate work"))
        assertEquals("", plan(listOf(work(stage = "CHALLENGE"), work("second", "b", "CHALLENGE"))).error)
    }

    @Test fun deliberateReplicationNeedsBothReasonAndDifference() {
        val duplicate = work("replicate", "b").put("replication", JSONObject().put("reason", "Reproduce independently"))
        assertTrue(plan(listOf(work(), duplicate)).error.contains("Intentional replication"))
        duplicate.getJSONObject("replication").put("difference", "Use a separately obtained input sample")
        assertEquals("", plan(listOf(work(), duplicate)).error)
    }

    @Test fun completedEvidenceUnderRenamedIdTriggersRecallInsteadOfBlindRepeat() {
        val observation = sample("a").copy(signature = CollaborationTeamOrganization.signature(work()))
        val result = plan(listOf(work()), checkpoint = checkpoint().copy(observations = listOf(observation)))
        assertTrue(result.error.contains("recall its original"))
        assertTrue(result.error.contains("not goal acceptance"))
        listOf(CollaborationTeamOrganization.Outcome.FAILED, CollaborationTeamOrganization.Outcome.UNKNOWN).forEach { outcome ->
            assertEquals("", plan(listOf(work()), checkpoint = checkpoint().copy(
                observations = listOf(observation.copy(outcome = outcome)))).error)
        }
    }

    @Test fun stableCompletedIdIsLeftForExistingGraphReplaySuppression() {
        val result = plan(listOf(work()), checkpoint = checkpoint().copy(finishedWork = setOf("job")))
        assertEquals("", result.error)
        assertEquals(setOf("lead"), result.organization!!.activePeople)
        assertTrue(result.organization.subgroups.isEmpty())
    }

    @Test fun cosmeticWorkAndClaimedBindingChangesCannotBypassStoredSignature() {
        val original = work()
        val signature = CollaborationTeamOrganization.signature(original)
        val renamed = work("renamed", "b").put("title", "New display name").put("status", "met")
            .put("evidence", JSONArray().put("new receipt"))
            .put("criteria_sha256", "f".repeat(64))
            .put("material_input_binding", JSONObject().put("source", "host").put("sha256", "a".repeat(64)))
        assertEquals(signature, CollaborationTeamOrganization.signature(renamed))
        val result = plan(listOf(renamed), checkpoint = checkpoint().copy(
            observations = listOf(sample("a").copy(signature = signature))))
        assertTrue(result.error.contains("recall its original"))
        assertEquals(people(), result.people)
        assertTrue(result.aliases.isEmpty())
    }

    @Test fun duplicateFeedbackExplainsCriteriaChangedMappingRepairWithoutReplay() {
        val job = work(assignment = "Publish the mapping from the preserved criteria")
        val result = plan(listOf(job), checkpoint = checkpoint().copy(observations = listOf(
            sample("a").copy(signature = CollaborationTeamOrganization.signature(job)))))
        listOf("If preserved criteria changed", "mapping-only revision", "work.replication={reason,difference}",
            "old/new host criteria bindings", "changed criterion IDs", "independent review",
            "Do not rerun completed tool calls or side effects").forEach { assertTrue(result.error, result.error.contains(it)) }
        assertTrue(CollaborationTeamOrganizationContext.instructions().contains("Status/evidence updates are not material input changes"))
    }

    @Test fun replicationCannotReplayACompletedStableWorkId() {
        val job = work().put("replication", JSONObject().put("reason", "Criteria changed")
            .put("difference", "A newly required mapping constraint"))
        val checkpoint = checkpoint().copy(finishedWork = setOf("job"), finishedAuthors = mapOf("job" to "a"))
        val result = plan(listOf(job), checkpoint = checkpoint)
        assertEquals("", result.error)
        assertTrue(CollaborationWorkGraph.compile(listOf(job), checkpoint.finishedWork, checkpoint.finishedAuthors).work.isEmpty())
        assertEquals(setOf("lead"), result.organization!!.activePeople)
        assertTrue(result.organization.subgroups.isEmpty())
    }

    @Test fun inFlightWorkCannotBeRepeatedEvenWithReplicationClaim() {
        val job = work().put("replication", JSONObject().put("reason", "Retry").put("difference", "New attempt"))
        val pending = CollaborationTeamOrganization.InFlight("a", "prior", CollaborationTeamOrganization.signature(job))
        val result = plan(listOf(job), checkpoint = checkpoint().copy(settled = false, inFlight = listOf(pending)))
        assertTrue(result.error.contains("in-flight"))
        assertEquals(people(), result.people)
    }

    @Test fun staleFinishedLedgerCannotBypassInFlightOwnership() {
        val job = work().put("replication", JSONObject().put("reason", "Retry").put("difference", "Another attempt"))
        val boundary = checkpoint().copy(settled = false, finishedWork = setOf("job"),
            inFlight = listOf(CollaborationTeamOrganization.InFlight("a", "job", CollaborationTeamOrganization.signature(job))))
        val result = plan(listOf(job), checkpoint = boundary)
        assertTrue(result.error.contains("in-flight"))
        assertEquals(people(), result.people)
        assertTrue(result.aliases.isEmpty())
    }

    @Test fun idleRoleIsReusedWithoutChangingItsModelRoleOrHistory() {
        val existing = people().map { it.copy(context = it.context + ("history_reference" to "originals:${it.memberId}")) }
        val result = plan(listOf(work("new", "recruit:gap")), JSONArray().put(recruit()), roster = existing)
        assertEquals("", result.error)
        assertEquals(3, result.people.size)
        assertEquals("a", result.aliases["recruit:gap"])
        result.people.zip(existing).forEach { (actual, prior) ->
            assertEquals(prior.role, actual.role)
            assertEquals(prior.agentId, actual.agentId)
            assertEquals(prior.requiredCapabilities, actual.requiredCapabilities)
            assertEquals(prior.context["history_reference"], actual.context["history_reference"])
            assertEquals(prior.context["collaboration_model_id"], actual.context["collaboration_model_id"])
            assertEquals(prior.deliveryMode, actual.deliveryMode)
        }
        val changed = recruit().put("scope", "Different scope")
        assertTrue(plan(listOf(work("new", "recruit:gap")), JSONArray().put(changed), roster = result.people)
            .error.contains("vacancy ID"))
    }

    @Test fun busyMemberAndPriorAuthorAreNotReusedForIndependentReview() {
        val review = work("review", "recruit:gap", "VERIFY").put("independent_review", true)
            .put("depends_on", JSONArray().put("artifact"))
        val result = plan(listOf(review), JSONArray().put(recruit()), checkpoint().copy(
            finishedAuthors = mapOf("artifact" to "a"), finishedWork = setOf("artifact")))
        assertEquals("b", result.aliases["recruit:gap"])
        val busy = plan(listOf(work("own", "a"), work("review", "recruit:gap", "VERIFY")), JSONArray().put(recruit()))
        assertEquals("b", busy.aliases["recruit:gap"])
        val running = plan(listOf(work("review", "recruit:gap", "VERIFY")), JSONArray().put(recruit()),
            checkpoint().copy(settled = false, inFlight = listOf(CollaborationTeamOrganization.InFlight("a", "running"))))
        assertEquals("b", running.aliases["recruit:gap"])
    }

    @Test fun incompatibleProviderOrModelIsNeverChosenForReuse() {
        val roster = listOf(person("lead", "Coordinator"), person("a", "Researcher"), person("b", model = "other"))
        val result = plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()), roster = roster)
        assertEquals("", result.error)
        assertEquals(4, result.people.size)
        assertEquals("authorized", result.people.last().context["collaboration_model_id"])
        assertNotEquals("b", result.aliases["recruit:gap"])
    }

    @Test fun observedDominanceCanChooseAnotherCompatibleIdleMember() {
        val observations = listOf(sample("a", CollaborationTeamOrganization.Outcome.FAILED, 50, 12), sample("b", elapsed = 20, cost = 5))
        val result = plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()), checkpoint().copy(observations = observations))
        assertEquals("b", result.aliases["recruit:gap"])
    }

    @Test fun unknownIsNeitherFreeNorFailureAndCannotOutrankByMissingDimensions() {
        val scenarios = listOf(
            listOf(sample("a", cost = 90), sample("b")),
            listOf(sample("a", elapsed = 90), sample("b")),
            listOf(sample("a", CollaborationTeamOrganization.Outcome.FAILED), sample("b", CollaborationTeamOrganization.Outcome.UNKNOWN)),
            listOf(sample("a", CollaborationTeamOrganization.Outcome.FAILED)))
        scenarios.forEach { observations ->
            val result = plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()), checkpoint().copy(observations = observations))
            assertEquals("a", result.aliases["recruit:gap"])
        }
    }

    @Test fun differentModelHistoryCannotInfluenceAllocation() {
        val observations = listOf(sample("a", CollaborationTeamOrganization.Outcome.FAILED).copy(modelId = "old-model"), sample("b"))
        assertEquals("a", plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()),
            checkpoint().copy(observations = observations)).aliases["recruit:gap"])
    }

    @Test fun dependencySubgroupsAreStableAndDoNotChangeIndependentReviewAuthority() {
        val producer = work("produce")
        val reviewer = work("review", "b", "VERIFY").put("depends_on", JSONArray().put("produce")).put("independent_review", true)
        val separate = work("separate", "a", assignment = "Inspect distinct data")
        val result = plan(listOf(producer, reviewer, separate))
        val groups = result.organization!!.subgroups
        assertEquals(2, groups.size)
        assertEquals(setOf("a", "b"), groups.first { "produce" in it.workIds }.people)
        val reversed = plan(listOf(separate, reviewer, producer)).organization!!.subgroups
        assertEquals(groups.map { it.id }.toSet(), reversed.map { it.id }.toSet())
        assertTrue(reviewer.getBoolean("independent_review"))
        assertEquals("b", reviewer.getString("member"))
    }

    @Test fun contractionRequiresSettledCheckpointAndPreservesAllMembers() {
        val result = plan(listOf(work()))
        assertTrue(result.organization!!.contractionApplied)
        assertEquals(setOf("b"), result.organization.standbyPeople)
        assertEquals(3, result.people.size)
        assertEquals("standby", result.people.last().context[CollaborationTeamOrganization.STATE])
        val next = plan(listOf(work(member = "b")), roster = result.people)
        assertEquals("active", next.people.last().context[CollaborationTeamOrganization.STATE])
        listOf(checkpoint().copy(settled = false), checkpoint().copy(coordinatorId = ""),
            checkpoint().copy(inFlight = listOf(CollaborationTeamOrganization.InFlight("b", "running")))).forEach { boundary ->
            val live = plan(listOf(work()), checkpoint = boundary)
            assertFalse(live.organization!!.contractionApplied)
            assertTrue(live.organization.standbyPeople.isEmpty())
            assertEquals(3, live.people.size)
        }
    }

    @Test fun stableVacancyBindingCannotBypassBusyOrKnownAuthorChecks() {
        val first = plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()))
        assertEquals("a", first.aliases["recruit:gap"])
        val review = work("review", "recruit:gap", "VERIFY", "Check the saved artifact")
            .put("depends_on", JSONArray().put("artifact")).put("independent_review", true)
        val checkpoints = listOf(
            checkpoint().copy(settled = false, inFlight = listOf(CollaborationTeamOrganization.InFlight("a", "running"))),
            checkpoint().copy(finishedWork = setOf("artifact"), finishedAuthors = mapOf("artifact" to "a")),
            checkpoint().copy(coordinatorId = "a"))
        checkpoints.forEach { boundary ->
            val next = plan(listOf(review), JSONArray().put(recruit()), boundary, first.people)
            assertTrue(next.error, next.error.contains("Bound vacancy member"))
            assertEquals(first.people, next.people)
            assertTrue(next.aliases.isEmpty())
        }
        val occupied = plan(listOf(work("explicit", "a", assignment = "Keep explicit responsibility"), review),
            JSONArray().put(recruit()), roster = first.people)
        assertTrue(occupied.error.contains("Bound vacancy member"))
        val idleAgain = plan(listOf(work("next", "recruit:gap", assignment = "Inspect a distinct fixture")),
            JSONArray().put(recruit()), roster = first.people)
        assertEquals("", idleAgain.error)
        assertEquals(first.aliases, idleAgain.aliases)
        assertEquals(3, idleAgain.people.size)
    }

    @Test fun capabilityMismatchDoesNotReuseOrExpandExistingAuthority() {
        val roster = listOf(person("lead", "Coordinator"), person("a", "Researcher").copy(requiredCapabilities = setOf(AgentCapability.RESEARCH)),
            person("b"))
        val next = plan(listOf(work(member = "recruit:gap")), JSONArray().put(recruit()), roster = roster)
        assertEquals("", next.error)
        assertEquals(4, next.people.size)
        assertNotEquals("b", next.aliases["recruit:gap"])
        assertEquals(roster[1].requiredCapabilities, next.people.last().requiredCapabilities)
        assertEquals(roster[2].requiredCapabilities, next.people[2].requiredCapabilities)
    }

    @Test fun allocationChangesOnlyItsThreeMetadataKeys() {
        val original = people().map { it.copy(context = it.context + mapOf("resource_grant" to "read-only",
            "collaboration_receive_results" to "false", "history_reference" to "saved:${it.memberId}")) }
        val decision = CollaborationTeamOrganization.allocate(original, listOf(work()), checkpoint())
        val keys = setOf(CollaborationTeamOrganization.STATE, CollaborationTeamOrganization.SUBGROUPS, CollaborationTeamOrganization.SIGNATURES)
        decision.people.zip(original).forEach { (actual, prior) ->
            assertEquals(prior, actual.copy(context = actual.context.filterKeys { it !in keys }))
        }
        assertEquals(setOf("b"), decision.standbyPeople)
    }

    @Test fun unknownCoordinatorCannotAuthorizeStandby() {
        val decision = CollaborationTeamOrganization.allocate(people(), listOf(work()), checkpoint().copy(coordinatorId = "outside-roster"))
        assertFalse(decision.contractionApplied)
        assertTrue(decision.standbyPeople.isEmpty())
        assertTrue(decision.people.none { it.context[CollaborationTeamOrganization.STATE] == "standby" })
    }

    @Test fun completedDependencyDoesNotJoinOtherwiseIndependentPendingGroups() {
        val jobs = listOf(work("a-branch").put("depends_on", JSONArray().put("saved")),
            work("b-branch", "b", assignment = "Use saved data for a different check").put("depends_on", JSONArray().put("saved")))
        val decision = CollaborationTeamOrganization.allocate(people(), jobs,
            checkpoint().copy(finishedWork = setOf("saved"), finishedAuthors = mapOf("saved" to "lead")))
        assertEquals(2, decision.subgroups.size)
        assertTrue(decision.subgroups.all { it.workIds.size == 1 && "saved" !in it.workIds })
    }

    @Test fun legacyEntryCannotAssumeExistingMembersAreIdleWithoutHostCheckpoint() {
        val result = CollaborationGoalRecruitment.plan(people(), JSONArray().put(recruit()),
            JSONArray().put(work(member = "recruit:gap")), listOf("NewTester"))
        assertEquals("", result.error)
        assertFalse(result.aliases.getValue("recruit:gap") in people().map(CollaborationTeamOrganization::person))
        assertNull(result.organization)
    }

    @Test fun manyDistinctAssignmentsDoNotBecomeAnOrganizationStepBudget() {
        val result = plan((0 until 80).map { work("work-$it",
            assignment = "Check the square checksum of disjoint input integers ${it * 10}..${it * 10 + 9}") })
        assertEquals("", result.error)
        assertEquals(80, result.organization!!.subgroups.size)
        assertEquals(3, result.people.size)
        var roster = people()
        repeat(1001) { iteration ->
            val next = plan(listOf(work("iteration-$iteration",
                assignment = "Check the square checksum of disjoint input integers ${iteration * 10}..${iteration * 10 + 9}")), roster = roster)
            assertEquals("", next.error)
            assertEquals(3, next.people.size)
            roster = next.people
        }
    }
}
