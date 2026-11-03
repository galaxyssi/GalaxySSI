package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentObservedOutcomeFreshnessTest {
    private val read = "galaxyssi.fixture.document.inspect"
    private val write = "galaxyssi.fixture.document.write"
    private val evidence = """{"path":"outputs/report.csv","readable":true,"rows":3}"""
    private val required = AgentObservedOutcome("report", read, mapOf("/path" to "outputs/report.csv"),
        mapOf("/readable" to true, "/rows" to 3))
    private fun action(id: String = "read", tool: String = read, output: String = evidence,
        status: AgentActionStatus = AgentActionStatus.COMPLETED) = AgentAction(id, AgentActionKind.CALL_NATIVE_TOOL,
        tool, AgentRisk.LOW, status, "Synthetic observation", mapOf("tool_id" to tool), evidence = output)
    private fun diagnose(vararg history: AgentAction, requirement: AgentObservedOutcome = required) =
        AgentObservedOutcomeEvidence.diagnose(requirement, history.toList())
    private fun code(vararg history: AgentAction, requirement: AgentObservedOutcome = required) =
        requireNotNull(diagnose(*history, requirement = requirement)).getString("code")

    @Test fun malformedLatestReceiptCannotFallBackToOldSuccess() {
        for (output in listOf("", "{broken", "null")) {
            assertEquals("invalid_receipt", code(action(), action("new", output = output)))
        }
    }

    @Test fun missingLatestIdentityCannotFallBackToOldSuccess() {
        for (output in listOf("{}", """{"readable":true,"rows":3}""", """{"path":null,"readable":true,"rows":3}""")) {
            assertEquals("subject_not_matched", code(action(), action("new", output = output)))
        }
    }

    @Test fun failedObservationWithoutAUsefulPayloadBlocksStaleSuccess() {
        val latest = action("new", output = """{"error":"network unavailable"}""", status = AgentActionStatus.FAILED)
        assertNotNull(diagnose(action(), latest))
        assertEquals("new", diagnose(action(), latest)!!.getString("action_id"))
    }

    @Test fun provenDifferentSubjectDoesNotInvalidateIndependentObservation() {
        val other = action("other", output = evidence.replace("report.csv", "unrelated.csv"))
        assertNull(diagnose(action(), other))
        assertNull(diagnose(action(), other.copy(status = AgentActionStatus.FAILED)))
    }

    @Test fun plannedUndispatchedReadsDoNotReplaceExecutedObservations() {
        for (status in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION)) {
            assertNull(diagnose(action(), action("not-dispatched", output = "", status = status)))
        }
        assertNull(diagnose(action(), action("not-dispatched", output = "", status = AgentActionStatus.PROPOSED).supersededByPlanRevision(1, 2)))
    }

    @Test fun nonterminalObservationNeverProvesCompletion() {
        for (status in listOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE, AgentActionStatus.BLOCKED, AgentActionStatus.FAILED)) {
            assertEquals("observation_not_completed", code(action(), action("latest", status = status)))
        }
    }

    @Test fun allExplicitUnverifiedMarkersOverrideSuccessfulLookingValues() {
        val markers = listOf(JSONObject().put("state_verified", false), JSONObject().put("delivery_verified", false),
            JSONObject().put("metadata", JSONObject().put("business_success_verified", false)),
            JSONObject().put("metadata", JSONObject().put("business_success_verified", "false"))) +
            listOf("dispatched", "blocked", "unknown", "failed").map { JSONObject().put("metadata", JSONObject().put("goal_status", it)) }
        for (marker in markers) {
            val output = JSONObject(evidence)
            marker.keys().forEach { output.put(it, marker.get(it)) }
            assertEquals("state_unverified", code(action(), action("new", output = output.toString())))
        }
    }

    @Test fun wrapperUncertaintyAndFailureCannotDisappearDuringUnwrapping() {
        for (wrapper in listOf(
            JSONObject().put("metadata", JSONObject().put("business_success_verified", "false")),
            JSONObject().put("delivery_verified", false))) {
            wrapper.put("output", JSONObject(evidence))
            assertEquals("state_unverified", code(action(), action("new", output = wrapper.toString())))
        }
        for (wrapper in listOf(JSONObject().put("status", "failed"),
            JSONObject().put("status", "succeeded").put("receipt", JSONObject().put("status", "waiting")))) {
            wrapper.put("output", JSONObject(evidence))
            assertEquals("receipt_not_succeeded", code(action(), action("new", output = wrapper.toString())))
        }
    }

    @Test fun wrongToolEnvelopeCannotBorrowAnActionsToolIdentity() {
        val wrapper = JSONObject().put("output", JSONObject(evidence)).put("tool_id", "galaxyssi.fixture.other")
        assertEquals("receipt_tool_mismatch", code(action(), action("new", output = wrapper.toString())))
    }

    @Test fun validLegacyAndWrappedReceiptsStillWork() {
        assertNull(diagnose(action()))
        val wrapper = JSONObject().put("output", JSONObject(evidence)).put("tool_id", read).put("status", "succeeded")
            .put("receipt", JSONObject().put("status", "succeeded"))
        assertNull(diagnose(action(output = wrapper.toString())))
        assertNull(diagnose(action().copy(parameters = emptyMap())))
    }

    @Test fun declaredAfterActionMustActuallyHaveBeenAttempted() {
        val after = required.copy(afterToolId = write)
        assertEquals("required_action_not_observed", code(action(), requirement = after))
        for (status in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION,
            AgentActionStatus.BLOCKED)) {
            assertEquals("required_action_not_observed", code(action("write", write, "", status), action(), requirement = after))
        }
        assertEquals("required_action_not_observed", code(action("write", write, "", AgentActionStatus.PROPOSED).supersededByPlanRevision(1, 2), action(), requirement = after))
        assertEquals("required_action_not_observed", code(action("write", write).copy(kind = AgentActionKind.DRAFT_PLAN),
            action(), requirement = after))
    }

    @Test fun pendingEffectNeedsReconciliationEvenIfAReadLooksSuccessful() {
        for (status in listOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)) {
            val result = diagnose(action("write", write, status = status), action(), requirement = required.copy(afterToolId = write))!!
            assertEquals("required_action_still_pending", result.getString("code"))
            assertTrue(result.getString("next_action").contains("do not dispatch it again"))
        }
    }

    @Test fun newestAttemptInvalidatesEarlierObservationAndFreshReadResolvesIt() {
        val after = required.copy(afterToolId = write)
        val first = action("write-1", write)
        val second = action("write-2", write, status = AgentActionStatus.FAILED)
        assertEquals("observation_stale", code(first, action(), second, requirement = after))
        assertNull(diagnose(first, action(), second, action("fresh"), requirement = after))
    }

    @Test fun atomicMutationWithVerifiedReadbackCanProveItsOwnOutcome() {
        assertNull(diagnose(action(), requirement = required.copy(afterToolId = read)))
    }

    @Test fun rolledBackEffectsCannotBeReinterpretedAsAnUnexecutedPlan() {
        val rolledBack = action("write", write, status = AgentActionStatus.ROLLED_BACK)
        assertEquals("required_action_rolled_back", code(rolledBack, action(), requirement = required.copy(afterToolId = write)))
        assertEquals("observation_not_completed", code(action(), action("rolled-back-read", status = AgentActionStatus.ROLLED_BACK)))
        val supersededWithReceipt = action("write", write).supersededByPlanRevision(1, 2)
        assertEquals("required_action_superseded_unresolved", code(supersededWithReceipt, action(), requirement = required.copy(afterToolId = write)))
    }

    @Test fun supersededRunningActionsCannotBeAssumedNeverDispatched() {
        for (status in listOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)) {
            val old = action("write", write, "", status).supersededByPlanRevision(1, 2)
            assertEquals(status.name, old.parameters[SUPERSEDED_SOURCE_STATUS_PARAMETER])
            assertEquals("required_action_superseded_unresolved", code(old, action(), requirement = required.copy(afterToolId = write)))
        }
        val legacy = action("legacy", write, "superseded_by_plan_revision:2", AgentActionStatus.ROLLED_BACK)
        assertEquals("required_action_superseded_unresolved", code(legacy, action(), requirement = required.copy(afterToolId = write)))
    }

    @Test fun freshInspectionRepairsUncertaintyWithoutRepeatingTheEffect() {
        val effect = action("write", write)
        val uncertain = action("read-failed", output = "", status = AgentActionStatus.FAILED)
        val history = listOf(effect, action("old"), uncertain)
        val after = required.copy(afterToolId = write)
        assertNotNull(AgentObservedOutcomeEvidence.diagnose(after, history))
        assertNull(AgentObservedOutcomeEvidence.diagnose(after, history + action("fresh")))
        assertEquals(1, (history + action("fresh")).count { it.parameters["tool_id"] == write })
    }

    @Test fun completionGateRejectsStaleEvidenceAndAcceptsReadOnlyRepair() {
        val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false, outcomes = listOf(required))
        val history = listOf(action(), action("failed", "galaxyssi.fixture.document.inspect", "", AgentActionStatus.FAILED))
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history).isEmpty())
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history + action("fresh")).isEmpty())
    }

    @Test fun diagnosticContainsRepairDirectionButNoPrivatePayload() {
        val latest = action("latest", output = "private malformed value")
        val diagnostic = diagnose(action(), latest)!!.toString()
        assertTrue(diagnostic.contains("next_action"))
        assertTrue(diagnostic.contains("read-only"))
        assertFalse(diagnostic.contains("private malformed value"))
    }
}
