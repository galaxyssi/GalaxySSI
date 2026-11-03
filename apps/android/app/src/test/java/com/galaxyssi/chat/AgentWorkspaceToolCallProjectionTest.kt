package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentWorkspaceToolCallProjectionTest {
    @Test fun completedReceiptReplacesTheOriginalRunningRecord() {
        val running = call(AgentToolCallStatus.RUNNING, "{\"awaiting_response\":true}")
        val done = call(AgentToolCallStatus.SUCCEEDED, "{\"message\":\"Done\"}")
        assertEquals(listOf(done), AgentWorkspaceToolCallProjection.merge(listOf(running), listOf(done)))
    }

    @Test fun failedAndCancelledStatesAreNotPromotedToSuccess() {
        for (status in listOf(AgentToolCallStatus.FAILED, AgentToolCallStatus.CANCELLED)) {
            val final = call(status).copy(errorMessage = "stopped")
            val merged = AgentWorkspaceToolCallProjection.merge(listOf(call(AgentToolCallStatus.RUNNING)), listOf(final))
            assertEquals(final, merged.single())
        }
    }

    @Test fun unrelatedCallsRemainIndependentAndRepeatedSnapshotsDoNotDuplicate() {
        val first = call(AgentToolCallStatus.RUNNING)
        val other = first.copy(id = "other")
        val done = first.copy(status = AgentToolCallStatus.SUCCEEDED)
        val merged = AgentWorkspaceToolCallProjection.merge(listOf(first, other), listOf(done, done))
        assertEquals(2, merged.size)
        assertEquals(AgentToolCallStatus.RUNNING, merged.single { it.id == "other" }.status)
        assertEquals(AgentToolCallStatus.SUCCEEDED, merged.single { it.id == "action" }.status)
    }

    @Test fun historySummaryKeepsTheOriginalFullReceiptAndTimes() {
        val receipt = call(AgentToolCallStatus.SUCCEEDED, "{\"streams\":[1,2],\"verified\":true}")
            .copy(startedAtMillis = 10L, completedAtMillis = 20L)
        val summary = call(AgentToolCallStatus.SUCCEEDED, "{\"message\":\"Done\"}")
        assertEquals(receipt, AgentWorkspaceToolCallProjection.merge(listOf(receipt), listOf(summary)).single())
    }

    @Test fun retryDropsPreviousFailureEvidenceAndCompletionTime() {
        val failed = call(AgentToolCallStatus.FAILED, "{\"error\":\"offline\"}")
            .copy(errorMessage = "offline", startedAtMillis = 10L, completedAtMillis = 20L)
        val retry = call(AgentToolCallStatus.RUNNING).copy(startedAtMillis = 30L)
        assertEquals(retry, AgentWorkspaceToolCallProjection.merge(listOf(failed), listOf(retry)).single())
    }

    @Test fun differentAttemptDoesNotBorrowAnOldSuccessfulObservation() {
        val old = call(AgentToolCallStatus.SUCCEEDED, "{\"verified\":true}")
            .copy(startedAtMillis = 10, completedAtMillis = 20)
        val latest = call(AgentToolCallStatus.SUCCEEDED, "{\"message\":\"new attempt\"}")
            .copy(startedAtMillis = 30, completedAtMillis = 40)
        assertEquals(latest, AgentWorkspaceToolCallProjection.merge(listOf(old), listOf(latest)).single())
    }

    @Test fun nativeInvocationDoesNotChangeTheLogicalActionIdentity() {
        val running = action(AgentActionStatus.RUNNING)
        val result = AgentActionResult(running.id, true, "Read", mapOf(
            "invocation_id" to "native-receipt-id", "native_tool_output" to "{\"value\":3}",
            "started_at_millis" to "10", "completed_at_millis" to "20"))
        val before = AgentWorkspaceToolCallProjection.records(listOf(running), null)
        val after = AgentWorkspaceToolCallProjection.records(listOf(running.copy(status = AgentActionStatus.COMPLETED)), result)
        val merged = AgentWorkspaceToolCallProjection.merge(before, after)
        assertEquals(1, merged.size)
        assertEquals(running.id, merged.single().id)
        assertEquals("{\"value\":3}", merged.single().resultJson)
        assertEquals(20L, merged.single().completedAtMillis)
    }

    @Test fun currentActionWinsOverAnOlderHistoryCopy() {
        val stale = action(AgentActionStatus.RUNNING)
        val current = stale.copy(status = AgentActionStatus.COMPLETED)
        val plan = AgentPlan("Read", ScreenContext("Test", pageTitle = "Test"), emptyList(),
            listOf(current), actionHistory = listOf(stale))
        assertEquals(listOf(current), AgentWorkspaceToolCallProjection.actions(plan))
    }

    @Test fun acceptanceOrForeignResultDoesNotClaimGoalCompletion() {
        val waiting = action(AgentActionStatus.WAITING_RESPONSE)
        val accepted = AgentActionResult(waiting.id, true, "Accepted", mapOf("awaiting_response" to "true"))
        assertEquals(AgentToolCallStatus.RUNNING, AgentWorkspaceToolCallProjection.records(listOf(waiting), accepted).single().status)
        val foreign = accepted.copy(actionId = "other", metadata = mapOf("native_tool_output" to "{\"wrong\":true}"))
        assertFalse(AgentWorkspaceToolCallProjection.records(listOf(waiting), foreign).single().resultJson.contains("wrong"))
    }

    @Test fun nonToolActionsAreNotInventedAsCalls() {
        assertTrue(AgentWorkspaceToolCallProjection.records(listOf(
            action(AgentActionStatus.COMPLETED).copy(kind = AgentActionKind.DRAFT_PLAN)), null).isEmpty())
    }

    private fun call(status: AgentToolCallStatus, result: String = "") =
        AgentToolCallRecord("action", "tool", status, "{}", result)

    private fun action(status: AgentActionStatus) = AgentAction("action", AgentActionKind.CALL_NATIVE_TOOL,
        "tool", AgentRisk.LOW, status, "Read", parameters = mapOf("tool_id" to "tool"))
}
