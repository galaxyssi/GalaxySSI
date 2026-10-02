package com.galaxyssi.chat

import com.galaxyssi.chat.CollaborationTeamOrganizationProjection as P
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** In-memory event-contract fixtures only; no provider, business execution or semantic acceptance is simulated. */
class CollaborationTeamOrganizationProjectionTest {
    private val scope = P.Scope("run", "team", "group", "conversation", "turn")
    private val authority = P.Authority("workspace-read-only", 7, "host-permission-digest")
    private fun person(id: String) = AgentTeamMember("fixture", AgentDeliveryMode.IGNORE,
        requiredCapabilities = setOf(AgentCapability.RESEARCH), role = "Tester", instanceId = id, context = mapOf(
            "collaboration_group_id" to "group", "collaboration_model_id" to "locked-model", "collaboration_receive_results" to "false",
            CollaborationResearchWorkflow.PERSON to id, CollaborationGoalLoop.ROSTER to "true", "resource_grant" to "read-only"))
    private val roster get() = listOf(person("a"), person("b"))
    private fun binding(person: String = "a", dispatch: String = "dispatch-a", generation: Long = 1,
                        work: String = "job", stage: String = "EXECUTE") = P.Binding(person(person).copy(
        instanceId = dispatch, deliveryMode = AgentDeliveryMode.OBSERVE, objective = "Opaque assignment contract",
        context = person(person).context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to work,
            CollaborationResearchWorkflow.STAGE to stage, CollaborationWorkGraph.POLICY to "success",
            CollaborationWorkGraph.PREVIOUS_DEPENDENCIES to "[]")), generation, authority, stage in setOf("VERIFY", "CHALLENGE"))
    private fun ownership(binding: P.Binding = binding()) = P.Ownership(binding.generation, listOf(binding))
    private fun event(binding: P.Binding = binding(), sequence: Long = 2, status: AgentSubagentStatus = AgentSubagentStatus.SUCCEEDED,
                      output: String = "opaque-event-fixture") = P.HostEvent(binding.generation, AgentSubagentEvent(sequence, "run",
        binding.member.memberId, AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = status,
        result = AgentSubagentChildResult("run", binding.member.memberId, "run", 1, status, output = output,
            startedAtMillis = 10, completedAtMillis = 20, provenance = AgentSubagentProvenance("agent-team", "team", "run",
                mapOf("instance_id" to binding.member.memberId, "agent_id" to "fixture")))))
    private fun running(binding: P.Binding = binding(), sequence: Long = 3) = P.HostEvent(binding.generation,
        AgentSubagentEvent(sequence, "run", binding.member.memberId, AgentSubagentEventKinds.CHILD_RUNNING, childStatus = AgentSubagentStatus.RUNNING))
    private fun terminal(generation: Long = 1, sequence: Long = 10, status: AgentSubagentRunStatus = AgentSubagentRunStatus.SUCCEEDED) =
        P.HostEvent(generation, AgentSubagentEvent(sequence, "run", kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = status))
    private fun project(events: List<P.HostEvent> = emptyList(), owners: P.Ownership = ownership(), ledger: P.Ledger = P.Ledger()) =
        P.project(scope, owners, events, ledger)
    private fun record(owners: P.Ownership = ownership(), events: List<P.HostEvent> = emptyList(), context: Map<String, String> = emptyMap()) =
        AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", roster + owners.bindings.map { it.member },
            primaryInstanceId = owners.bindings.first().member.memberId),
            AgentRunRequest("conversation", "turn", "task", runId = "run", goal = "Contract tests only", context = context), events.map { it.event })
    @Test fun oneVerifiedProjectionGeneratesFinishedAuthorsAndActiveQueue() {
        val pending = binding("b", "pending", work = "other")
        val result = project(listOf(event()), P.Ownership(1, listOf(binding(), pending)))
        assertEquals(setOf("job"), result.finishedWork)
        assertEquals(mapOf("job" to "a"), result.finishedAuthors)
        assertEquals(listOf(pending), result.active)
        assertEquals(binding().key(scope), result.ledger.receipts.getValue("job").owner)
        assertFalse(result.settled)
    }

    @Test fun reorderingAndExactDuplicatesDoNotChangeMembershipOrProjection() {
        val events = listOf(running(sequence = 1), event(), terminal())
        val expected = project(events)
        repeat(30) { seed ->
            val replay = (events + events + events).shuffled(kotlin.random.Random(seed))
            assertEquals(expected, project(replay))
        }
        assertEquals(1, expected.ownership.bindings.size)
        assertTrue(expected.settled)
    }

    @Test fun oldGenerationCannotFinishOrSettleCurrentDispatchEvenWithHigherSequence() {
        val old = event(sequence = 999).copy(generation = 0)
        val result = project(listOf(old, terminal(0, 1000)))
        assertEquals(project(), result)
        assertEquals(1, result.active.size)
        assertTrue(result.finishedWork.isEmpty())
    }

    @Test fun foreignSupervisorAndUnboundProvenanceNeverBecomeCompletion() {
        val valid = event()
        val foreign = valid.copy(event = valid.event.copy(supervisorId = "foreign"))
        val unbound = valid.copy(event = valid.event.copy(result = valid.event.result!!.copy(
            provenance = valid.event.result.provenance.copy(sourceId = "wrong-team"))))
        listOf(foreign, unbound).forEach {
            val result = project(listOf(it, terminal()))
            assertEquals(1, result.active.size)
            assertTrue(result.finishedWork.isEmpty())
            assertTrue(result.finishedAuthors.isEmpty())
            assertFalse(result.settled)
        }
    }

    @Test fun mismatchedResultEnvelopeCannotAdvanceQueue() {
        val valid = event()
        val result = valid.event.result!!
        listOf(result.copy(parentId = "other"), result.copy(depth = 2), result.copy(childId = "other"),
            result.copy(supervisorId = "other"), result.copy(status = AgentSubagentStatus.RUNNING)).forEach { mismatch ->
            assertEquals(1, project(listOf(valid.copy(event = valid.event.copy(result = mismatch)))).active.size)
        }
    }

    @Test fun newerRunningWithoutResultOverridesOlderTerminalInAnyListOrder() {
        val events = listOf(event(), running(), terminal())
        listOf(events, events.reversed()).forEach {
            val result = project(it)
            assertEquals(1, result.active.size)
            assertTrue(result.finishedWork.isEmpty())
            assertFalse(result.settled)
        }
    }

    @Test fun conflictingSameSequenceIsNotResolvedByListOrder() {
        val events = listOf(event(), event(output = "conflicting-fixture"), terminal())
        val result = project(events)
        assertEquals(result, project(events.reversed()))
        assertFalse(result.safeToApply)
        assertEquals(1, result.active.size)
        assertTrue(result.finishedWork.isEmpty())
        assertTrue(runCatching { P.finishedContext(result) }.isFailure)
    }

    @Test fun immutableSavedReceiptCannotBeOverwrittenByAnotherResultOfSameDispatch() {
        val original = project(listOf(event()))
        val changed = project(listOf(event(sequence = 90, output = "conflict")), ledger = original.ledger)
        assertFalse(changed.safeToApply)
        assertEquals(original.ledger, changed.ledger)
        assertEquals(1, changed.active.size)
    }

    @Test fun conflictingTerminalsWithDifferentSequencesNeedNewHostGeneration() {
        val result = project(listOf(event(), event(sequence = 9, status = AgentSubagentStatus.FAILED), terminal()))
        assertFalse(result.safeToApply)
        assertTrue(result.finishedWork.isEmpty())
        assertEquals(1, result.active.size)
    }

    @Test fun savedReceiptRoundTripRetainsCurrentOwnerWithoutRecertifyingGoal() {
        val original = project(listOf(event()))
        val context = P.finishedContext(original)
        val restored = P.readLedger(record(context = context))
        assertEquals(original.ledger, restored)
        val resumed = project(ledger = restored)
        assertEquals(original.ledger, resumed.ledger)
        assertTrue(resumed.active.isEmpty())
        assertFalse(resumed.settled)
        assertTrue(resumed.verifiedResults.isEmpty())
        assertFalse(context.keys.any { it.contains("acceptance") })
    }

    @Test fun malformedOrCrossScopeSavedReceiptsFailClosed() {
        val context = P.finishedContext(project(listOf(event())))
        listOf("run_id" to "foreign", "group_id" to "foreign").forEach { (key, value) ->
            val bad = JSONObject(context.getValue(P.COMPLETIONS)).put(key, value).toString()
            assertTrue(runCatching { P.readLedger(record(context = context + (P.COMPLETIONS to bad))) }.isFailure)
        }
        val bad = JSONObject(context.getValue(P.COMPLETIONS))
        bad.getJSONObject("receipts").getJSONObject("job").put("generation", "1")
        assertTrue(runCatching { P.readLedger(record(context = context + (P.COMPLETIONS to bad.toString()))) }.isFailure)
    }

    @Test fun legacyFinishedIdsAndAuthorsArePreservedWithoutInventingOwnerReceipts() {
        val saved = P.Ledger(setOf("job", "older"), mapOf("job" to "legacy-author"))
        val result = project(listOf(event()), ledger = saved)
        assertEquals(saved, result.ledger)
        assertTrue(result.ledger.receipts.isEmpty())
    }

    @Test fun ownershipRoundTripRejectsMutatedDispatchContractAndLegacyFallback() {
        val owners = ownership()
        val context = P.ownershipContext(scope, owners)
        val original = record(context = context)
        assertEquals(owners, P.readOwnership(original))
        assertTrue(runCatching { P.legacy(original) }.isFailure)
        val changed = original.copy(definition = original.definition.copy(members = original.definition.members.map {
            if (it.memberId == "dispatch-a") it.copy(context = it.context + ("resource_grant" to "all")) else it
        }))
        assertTrue(runCatching { P.readOwnership(changed) }.isFailure)
    }

    @Test fun duplicateCurrentOwnersAreRejectedWithoutRosterMutation() {
        val original = binding()
        listOf(listOf(original, original), listOf(original, binding("b", "second"))).forEach { bindings ->
            assertTrue(runCatching { project(owners = P.Ownership(1, bindings)) }.isFailure)
        }
        assertEquals("read-only", original.member.context["resource_grant"])
    }

    @Test fun supervisorGenerationAndCancellationRemainCheckpointBarriers() {
        assertFalse(project(listOf(event(), terminal(0))).settled)
        val cancel = terminal(status = AgentSubagentRunStatus.CANCELLED)
        assertFalse(project(listOf(event(), cancel)).settled)
        val conflict = project(listOf(event(), terminal(), cancel))
        assertFalse(conflict.safeToApply)
        assertFalse(conflict.settled)
    }

    @Test fun failedSkippedAndCancelledDispatchesAreNotBusinessSuccess() {
        listOf(AgentSubagentStatus.FAILED, AgentSubagentStatus.SKIPPED, AgentSubagentStatus.CANCELLED).forEach { status ->
            val result = project(listOf(event(status = status)))
            assertTrue(result.finishedWork.isEmpty())
            assertTrue(result.active.isEmpty())
            assertFalse(result.settled)
        }
    }

}
