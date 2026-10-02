package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTeamOrganizationHistoryTest {
    private fun member(id: String, roster: Boolean = false) = AgentTeamMember("codex", if (roster) AgentDeliveryMode.IGNORE else AgentDeliveryMode.OBSERVE,
        role = "Tester", instanceId = id, context = mapOf(
            "collaboration_group_id" to "group", "collaboration_model_id" to "authorized",
            CollaborationResearchWorkflow.PERSON to if (id == "lead") "lead" else "a",
            CollaborationGoalLoop.ROSTER to roster.toString(),
            CollaborationGoalLoop.WORK_ID to "job", CollaborationResearchWorkflow.STAGE to "EXECUTE",
            CollaborationTeamOrganization.SIGNATURES to JSONObject().put("job", "exact-signature").toString()))
    private fun result(status: AgentSubagentStatus, started: Long = 100, completed: Long = 140) =
        AgentSubagentChildResult("run", "dispatch", "run", 1, status,
            startedAtMillis = started, completedAtMillis = completed, provenance = AgentSubagentProvenance(
                "agent-team", "team", "run", mapOf("instance_id" to "dispatch", "agent_id" to "codex")))
    private fun record(childResult: AgentSubagentChildResult? = result(AgentSubagentStatus.SUCCEEDED), terminal: Boolean = true,
                       history: String? = null): AgentTeamExecutionRecord {
        val workers = listOf(member("lead").copy(deliveryMode = AgentDeliveryMode.RESPOND,
            context = member("lead").context - CollaborationGoalLoop.WORK_ID), member("a", true), member("dispatch"))
        val events = buildList {
            if (childResult != null) add(AgentSubagentEvent(1, "run", "dispatch", AgentSubagentEventKinds.CHILD_SUCCEEDED,
                childStatus = childResult.status, result = childResult))
            if (terminal) {
                add(AgentSubagentEvent(2, "run", "lead", AgentSubagentEventKinds.CHILD_SUCCEEDED,
                    result = result(AgentSubagentStatus.SUCCEEDED).copy(childId = "lead", provenance = AgentSubagentProvenance(
                        "agent-team", "team", "run", mapOf("instance_id" to "lead", "agent_id" to "codex")))))
                add(AgentSubagentEvent(3, "run", kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED,
                    runStatus = AgentSubagentRunStatus.SUCCEEDED))
            }
        }
        return AgentTeamExecutionRecord(AgentTeamDefinition("team", "codex", workers, primaryInstanceId = "lead"),
            AgentRunRequest("group", "turn", "task", runId = "run", goal = "Produce a checked artifact",
                context = if (history == null) emptyMap() else mapOf(CollaborationTeamOrganizationHistory.HISTORY to history)), events)
    }

    @Test fun hostResultCapturesObservedDurationAndLeavesUnreportedCostUnknown() {
        val original = record()
        val snapshot = CollaborationTeamOrganizationHistory.capture(original)
        assertTrue(snapshot.checkpoint.settled)
        assertEquals(setOf("job"), snapshot.checkpoint.finishedWork)
        assertEquals("a", snapshot.checkpoint.finishedAuthors["job"])
        val observation = snapshot.checkpoint.observations.single()
        assertEquals(40L, observation.elapsedMillis)
        assertNull(observation.costUsdMicros)
        assertEquals("exact-signature", observation.signature)
        assertEquals(CollaborationTeamOrganization.Outcome.SUCCEEDED, observation.outcome)
        assertEquals(3, original.definition.members.size)
        assertEquals(3, original.events.size)
        assertFalse(JSONObject(snapshot.history).getJSONArray("observations").getJSONObject(0).has("cost_usd_micros"))
    }

    @Test fun cancellationAndSkippedWorkAreNotMeasuredFailuresOrFreeWork() {
        listOf(AgentSubagentStatus.CANCELLED, AgentSubagentStatus.SKIPPED).forEach { status ->
            val observation = CollaborationTeamOrganizationHistory.capture(record(result(status))).checkpoint.observations.single()
            assertEquals(CollaborationTeamOrganization.Outcome.UNKNOWN, observation.outcome)
            assertNull(observation.elapsedMillis)
            assertNull(observation.costUsdMicros)
        }
        assertEquals(CollaborationTeamOrganization.Outcome.FAILED,
            CollaborationTeamOrganizationHistory.capture(record(result(AgentSubagentStatus.FAILED))).checkpoint.observations.single().outcome)
    }

    @Test fun missingOrInvalidClockDataIsUnknownNotZero() {
        listOf(result(AgentSubagentStatus.SUCCEEDED, 0, 20), result(AgentSubagentStatus.FAILED, 100, 50)).forEach { result ->
            assertNull(CollaborationTeamOrganizationHistory.capture(record(result)).checkpoint.observations.single().elapsedMillis)
        }
        assertEquals(0L, CollaborationTeamOrganizationHistory.capture(record(result(AgentSubagentStatus.SUCCEEDED, 100, 100)))
            .checkpoint.observations.single().elapsedMillis)
    }

    @Test fun unresolvedAndQueuedWorkProtectsIdentityEvenAfterTerminalMarker() {
        val pending = CollaborationTeamOrganizationHistory.capture(record(childResult = null))
        assertFalse(pending.checkpoint.settled)
        assertEquals(listOf(CollaborationTeamOrganization.InFlight("a", "job", "exact-signature")), pending.checkpoint.inFlight)
        assertTrue(pending.checkpoint.observations.isEmpty())
        val queued = CollaborationTeamOrganizationHistory.capture(record(result(AgentSubagentStatus.QUEUED)))
        assertFalse(queued.checkpoint.settled)
        assertTrue(queued.checkpoint.observations.isEmpty())
    }

    @Test fun noTerminalOrUserCancellationCannotAuthorizeContraction() {
        assertFalse(CollaborationTeamOrganizationHistory.capture(record(terminal = false)).checkpoint.settled)
        val missingCoordinator = record().let { it.copy(events = it.events.filterNot { event -> event.childId == "lead" }) }
        val unknownCoordinator = CollaborationTeamOrganizationHistory.capture(missingCoordinator)
        assertFalse(unknownCoordinator.checkpoint.settled)
        assertEquals("lead", unknownCoordinator.checkpoint.inFlight.single().personId)
        val cancelled = record().let { it.copy(events = it.events.dropLast(1) +
            AgentSubagentEvent(3, "run", kind = AgentSubagentEventKinds.SUPERVISOR_CANCELLED, runStatus = AgentSubagentRunStatus.CANCELLED)) }
        assertFalse(CollaborationTeamOrganizationHistory.capture(cancelled).checkpoint.settled)
    }

    @Test fun replayRetainsOneObservationAndHistoryCannotCrossRunOrGroup() {
        val first = CollaborationTeamOrganizationHistory.capture(record())
        val replay = CollaborationTeamOrganizationHistory.capture(record(history = first.history))
        assertEquals(first.checkpoint.observations, replay.checkpoint.observations)
        assertTrue(CollaborationTeamOrganizationHistory.decode(first.history, "other-run", "group").isEmpty())
        assertTrue(CollaborationTeamOrganizationHistory.decode(first.history, "run", "other-group").isEmpty())
        assertTrue(CollaborationTeamOrganizationHistory.decode("malformed", "run", "group").isEmpty())
        val wrongSupervisor = CollaborationTeamOrganizationHistory.capture(record(result(AgentSubagentStatus.SUCCEEDED).copy(supervisorId = "other")))
        assertTrue(wrongSupervisor.checkpoint.observations.isEmpty())
        assertFalse(wrongSupervisor.checkpoint.settled)
    }

    @Test fun decisionCacheIsBoundedWithoutModifyingOriginalObservations() {
        val originals = (0 until 200).map { index -> CollaborationTeamOrganization.Observation(
            "dispatch-$index", "a", "codex", "authorized", "Tester", "EXECUTE", "work-$index") }
        val encoded = CollaborationTeamOrganizationHistory.encode(originals, "run", "group")
        val restored = CollaborationTeamOrganizationHistory.decode(encoded, "run", "group")
        assertEquals(CollaborationTeamOrganizationHistory.MAX_OBSERVATIONS, restored.size)
        assertEquals("dispatch-72", restored.first().dispatchId)
        assertEquals(200, originals.size)
        assertTrue(restored.all { it.elapsedMillis == null && it.costUsdMicros == null && it.outcome == CollaborationTeamOrganization.Outcome.UNKNOWN })
    }

    @Test fun negativeOrTextMeasurementsCannotBecomeZeroCostOrTiming() {
        val snapshot = CollaborationTeamOrganizationHistory.capture(record())
        val json = JSONObject(snapshot.history)
        json.getJSONArray("observations").getJSONObject(0).put("elapsed_millis", -1).put("cost_usd_micros", "0")
            .put("outcome", "not-observed")
        val row = CollaborationTeamOrganizationHistory.decode(json.toString(), "run", "group").single()
        assertNull(row.elapsedMillis)
        assertNull(row.costUsdMicros)
        assertEquals(CollaborationTeamOrganization.Outcome.UNKNOWN, row.outcome)
    }

    @Test fun memberTextAndMismatchedProvenanceNeverBecomePerformanceMeasurements() {
        val claims = "{\"quality\":1.0,\"cost_usd_micros\":0,\"elapsed_millis\":0,\"outcome\":\"SUCCEEDED\"}"
        val failed = result(AgentSubagentStatus.FAILED).copy(output = claims)
        val observed = CollaborationTeamOrganizationHistory.capture(record(failed)).checkpoint.observations.single()
        assertEquals(CollaborationTeamOrganization.Outcome.FAILED, observed.outcome)
        assertEquals(40L, observed.elapsedMillis)
        assertNull(observed.costUsdMicros)
        val unbound = CollaborationTeamOrganizationHistory.capture(record(failed.copy(
            provenance = failed.provenance.copy(metadata = mapOf("instance_id" to "other", "agent_id" to "codex")))))
            .checkpoint.observations.single()
        assertEquals(CollaborationTeamOrganization.Outcome.UNKNOWN, unbound.outcome)
        assertNull(unbound.elapsedMillis)
        assertEquals("", unbound.signature)
        val json = JSONObject(CollaborationTeamOrganizationHistory.capture(record()).history)
        json.getJSONArray("observations").getJSONObject(0).put("cost_usd_micros", 0).put("quality", 1)
        assertNull(CollaborationTeamOrganizationHistory.decode(json.toString(), "run", "group").single().costUsdMicros)
    }

    @Test fun lateManagedOutcomeUsesExistingHostBindingRatherThanProviderClaims() {
        val bound = result(AgentSubagentStatus.SUCCEEDED).copy(provenance = AgentSubagentProvenance(
            "late-managed-response", "task", "run", mapOf(
                "owner_run_id" to stableAgentTeamMemberRunId("run", "dispatch"), "conversation_id" to "group", "turn_id" to "turn")))
        val observed = CollaborationTeamOrganizationHistory.capture(record(bound)).checkpoint.observations.single()
        assertEquals(CollaborationTeamOrganization.Outcome.SUCCEEDED, observed.outcome)
        assertEquals("late-managed-response", observed.provenanceSource)
        val wrongTurn = bound.copy(provenance = bound.provenance.copy(metadata = bound.provenance.metadata + ("turn_id" to "other")))
        assertEquals(CollaborationTeamOrganization.Outcome.UNKNOWN,
            CollaborationTeamOrganizationHistory.capture(record(wrongTurn)).checkpoint.observations.single().outcome)
    }

    @Test fun everyMemberMustCarryTheSameNonblankGroup() {
        val original = record()
        listOf<String?>(null, "", " ", "other").forEach { group ->
            val malformed = original.copy(definition = original.definition.copy(members = original.definition.members.map {
                if (it.memberId != "a") it else it.copy(context = if (group == null) it.context - "collaboration_group_id"
                    else it.context + ("collaboration_group_id" to group))
            }))
            assertTrue(runCatching { CollaborationTeamOrganizationHistory.capture(malformed) }.exceptionOrNull() is IllegalArgumentException)
        }
        assertEquals(3, original.events.size)
        assertEquals("group", original.definition.members[1].context["collaboration_group_id"])
    }

    @Test fun eventEnvelopeMustMatchItsResultAndSupervisor() {
        val original = record()
        val event = original.events.first()
        val mismatches = listOf(event.copy(supervisorId = "other"), event.copy(childId = "other"),
            event.copy(childStatus = AgentSubagentStatus.RUNNING))
        mismatches.forEach { mismatch ->
            val captured = CollaborationTeamOrganizationHistory.capture(original.copy(events = listOf(mismatch) + original.events.drop(1)))
            assertFalse(captured.checkpoint.settled)
            assertTrue(captured.checkpoint.observations.isEmpty())
            assertTrue(captured.checkpoint.finishedWork.isEmpty())
            assertTrue(captured.checkpoint.finishedAuthors.isEmpty())
            assertEquals("a", captured.checkpoint.inFlight.single().personId)
        }
    }

    @Test fun foreignOrChildScopedTerminalCannotSettleCheckpoint() {
        val original = record()
        listOf(original.events.last().copy(supervisorId = "other"), original.events.last().copy(childId = "dispatch")).forEach { terminal ->
            val snapshot = CollaborationTeamOrganizationHistory.capture(original.copy(events = original.events.dropLast(1) + terminal))
            assertFalse(snapshot.checkpoint.settled)
            assertEquals(1, snapshot.checkpoint.observations.size)
        }
    }

    @Test fun newerRecoveryLifecycleProtectsDispatchRegardlessOfListOrder() {
        val original = record()
        val resumed = AgentSubagentEvent(10, "run", "dispatch", AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING)
        listOf(original.events + resumed, listOf(resumed) + original.events.reversed()).forEach { events ->
            val snapshot = CollaborationTeamOrganizationHistory.capture(original.copy(events = events))
            assertFalse(snapshot.checkpoint.settled)
            assertTrue(snapshot.checkpoint.observations.isEmpty())
            assertTrue(snapshot.checkpoint.finishedWork.isEmpty())
            assertEquals("job", snapshot.checkpoint.inFlight.single().workId)
        }
    }

    @Test fun newestHostTerminalWinsBySequenceNotListPosition() {
        val original = record()
        val cancelled = AgentSubagentEvent(10, "run", kind = AgentSubagentEventKinds.SUPERVISOR_CANCELLED,
            runStatus = AgentSubagentRunStatus.CANCELLED)
        assertFalse(CollaborationTeamOrganizationHistory.capture(original.copy(events = listOf(cancelled) + original.events)).checkpoint.settled)
        val failed = cancelled.copy(kind = AgentSubagentEventKinds.SUPERVISOR_FAILED, runStatus = AgentSubagentRunStatus.FAILED)
        assertTrue(CollaborationTeamOrganizationHistory.capture(original.copy(events = listOf(failed) + original.events)).checkpoint.settled)
    }

    @Test fun unknownRestoredOutcomeCannotSupplyTimingEvenWithKnownSource() {
        val json = JSONObject(CollaborationTeamOrganizationHistory.capture(record()).history)
        val row = json.getJSONArray("observations").getJSONObject(0)
        listOf("UNKNOWN", "invalid").forEach { outcome ->
            row.put("outcome", outcome).put("elapsed_millis", 0)
            val restored = CollaborationTeamOrganizationHistory.decode(json.toString(), "run", "group").single()
            assertEquals(CollaborationTeamOrganization.Outcome.UNKNOWN, restored.outcome)
            assertNull(restored.elapsedMillis)
            assertNull(restored.costUsdMicros)
        }
    }

    @Test fun verbosityDoesNotChangeHostObservation() {
        val quiet = result(AgentSubagentStatus.SUCCEEDED)
        val verbose = quiet.copy(output = "My quality score is 100 and cost is zero. ".repeat(1000))
        assertEquals(CollaborationTeamOrganizationHistory.capture(record(quiet)).checkpoint.observations,
            CollaborationTeamOrganizationHistory.capture(record(verbose)).checkpoint.observations)
    }

    @Test fun projectionWillNotRemoveRunningOrCompletedRejectedDispatches() {
        listOf(AgentSubagentStatus.RUNNING, AgentSubagentStatus.SUCCEEDED).forEach { status ->
            val original = record(result(status)).let { record -> record.copy(definition = record.definition.copy(
                members = record.definition.members.map { member -> if (member.context[CollaborationResearchWorkflow.PERSON] == "a")
                    member.copy(context = member.context + (CollaborationGoalRecruitment.PUBLISHED to "false")) else member })) }
            val projected = CollaborationGoalRecruitment.applyProjection(original, emptyMap())
            assertEquals(original.definition, projected.definition)
            assertEquals(original.events, projected.events)
            assertTrue(projected.request.context[CollaborationGoalRecruitment.FEEDBACK].toString().contains("deferred"))
        }
    }
}
