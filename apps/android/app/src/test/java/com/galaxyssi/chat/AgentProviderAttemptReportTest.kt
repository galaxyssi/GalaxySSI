package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentProviderAttemptReportTest {
    private val identity = AgentProviderAttemptReport(42, "conversation", "turn", "task", "action")
    private val transient = AgentProviderFailure(AgentProviderFailureClass.TRANSIENT, true)
    private val billing = AgentProviderFailure(AgentProviderFailureClass.PERMANENT_BILLING, false)

    private fun tracker(sink: (AgentProviderAttemptReport) -> Unit = {}) = AgentProviderAttemptTracker(identity, sink)
    private fun AgentProviderAttemptTracker.start(id: String = "cloud-a") = start(
        "request-${report.attempts.size + 1}", id, "provider-$id", "model-$id", 100L)

    @Test fun codecPreservesHttpFailureAndActualModel() {
        val tracker = tracker()
        tracker.start()
        tracker.finish(240, billing, 402)
        val report = AgentProviderAttemptCodec.decode(AgentProviderAttemptCodec.encode(tracker.report))
        assertEquals(tracker.report, report)
        assertEquals(billing, report.attempts.single().failure())
    }

    @Test fun emptyReportDoesNotConsumeCandidates() {
        val previous = mapOf("remaining_fallback_ids" to "a,b,c")
        assertEquals(previous, identity.mergeMetadata(previous))
    }

    @Test fun onlyActualCallsAreRemovedFromCandidateList() {
        val tracker = tracker()
        tracker.start()
        tracker.finish(10, billing)
        val result = tracker.report.mergeMetadata(mapOf("remaining_fallback_ids" to "cloud-a,cloud-b,codex"))
        assertEquals("cloud-b,codex", result["remaining_fallback_ids"])
        assertEquals(setOf("cloud-a"), AgentConnectorFallbackAction.attempted(result))
    }

    @Test fun innerExhaustionCannotResetOuterRetryBudget() {
        val tracker = tracker()
        repeat(2) { tracker.start(); tracker.finish(15_000, transient) }
        val result = tracker.report.mergeMetadata(mapOf("deferred_retry_ids" to "cloud-a"))
        assertEquals("", result["deferred_retry_ids"])
        assertNull(AgentConnectorFallbackTrail.selectNext("cloud-a", emptyList(), emptyList(),
            AgentConnectorFallbackTrail.parse(result["retried_resource_ids"].orEmpty()).toSet(), true,
            AgentConnectorFallbackAction.attempted(result)))
    }

    @Test fun freshCatalogCannotReviveExhaustedInnerCandidates() {
        val tracker = tracker()
        tracker.start(); tracker.finish(10, billing)
        tracker.start("cloud-b"); tracker.finish(20, transient)
        val metadata = tracker.report.mergeMetadata(emptyMap())
        assertEquals(listOf("codex"), AgentConnectorFallbackTrail.mergeAvailable(emptyList(),
            listOf("cloud-a", "cloud-b", "codex"), "cloud-b", AgentConnectorFallbackAction.attempted(metadata)))
    }

    @Test fun successTracksActualProviderWithoutLosingPriorFailures() {
        val tracker = tracker()
        tracker.start(); tracker.finish(20, billing)
        tracker.start("cloud-b"); tracker.finish(25)
        val result = tracker.report.mergeMetadata(mapOf("attempted_resource_ids" to "hermes"))
        assertEquals("cloud-b", result["resource_id"])
        assertEquals("model-cloud-b", result["resolved_model_id"])
        assertEquals("", result["provider_failure_class"])
        assertEquals("false", result["non_retriable"])
        assertEquals(setOf("hermes", "cloud-a", "cloud-b"), AgentConnectorFallbackAction.attempted(result))
    }

    @Test fun repeatedConnectionOrTokenEventsDoNotRewriteCheckpoint() {
        val saved = mutableListOf<AgentProviderAttemptReport>()
        val tracker = tracker(saved::add)
        tracker.start()
        tracker.progress("connected", 5)
        tracker.progress("connected", 6)
        tracker.progress("first_output", 10)
        repeat(100) { tracker.progress("first_output", 11L + it) }
        tracker.progress("connected", 200)
        tracker.finish(210)
        assertEquals(listOf("started", "connected", "first_output", "completed"), saved.map { it.attempts.last().state })
        assertEquals(4, saved.size)
    }

    @Test fun failureSummaryDoesNotDependOnLocalizedErrorText() {
        val tracker = tracker()
        tracker.start(); tracker.finish(23, billing, 402)
        val response = AgentConnectorResponse(42, "cloud-a", "\u8bf7\u6c42\u5931\u8d25", "conversation", "turn", "task",
            success = false, providerAttempts = tracker.report)
        val restored = AgentConnectorResponseCodec.decode(AgentConnectorResponseCodec.encode(response))
        assertEquals(billing, restored.providerAttempts!!.attempts.last().failure())
        assertEquals(402, restored.providerAttempts!!.attempts.last().httpStatus)
    }

    @Test fun everyIdentityDimensionIsRequired() {
        assertTrue(identity.matches(42, "conversation", "turn", "task", "action"))
        assertFalse(identity.matches(43, "conversation", "turn", "task", "action"))
        assertFalse(identity.matches(42, "other", "turn", "task", "action"))
        assertFalse(identity.matches(42, "conversation", "other", "task", "action"))
        assertFalse(identity.matches(42, "conversation", "turn", "other", "action"))
        assertFalse(identity.matches(42, "conversation", "turn", "task", "other"))
    }

    @Test fun journalIdentityCannotAliasDelimitedIds() {
        assertNotEquals(AgentProviderAttemptJournal.runId(identity.copy(taskId = "a:b", actionId = "c")),
            AgentProviderAttemptJournal.runId(identity.copy(taskId = "a", actionId = "b:c")))
    }

    @Test fun newTurnStartsWithEmptyAttemptHistory() {
        val old = tracker()
        old.start(); old.finish(10, billing)
        val fresh = AgentProviderAttemptTracker(identity.copy(turnId = "new-turn"))
        assertTrue(fresh.report.attempts.isEmpty())
        assertNotEquals(AgentProviderAttemptJournal.runId(old.report), AgentProviderAttemptJournal.runId(fresh.report))
    }

    @Test fun interruptedFallbackKeepsItsCurrentModelAndEarlierFailure() {
        val tracker = tracker()
        tracker.start(); tracker.finish(10, billing)
        tracker.start("cloud-b")
        tracker.progress("first_output", 20)
        val metadata = tracker.report.mergeMetadata(mapOf("remaining_fallback_ids" to "cloud-a,cloud-b,codex"))
        assertEquals("cloud-b", metadata["resource_id"])
        assertEquals("model-cloud-b", metadata["resolved_model_id"])
        assertEquals("first_output", metadata["provider_attempt_state"])
        assertEquals("cloud-a", metadata["retried_resource_ids"])
        assertEquals("codex", metadata["remaining_fallback_ids"])
    }

    @Test(expected = IllegalArgumentException::class) fun cannotStartAnotherAttemptBeforeObservation() {
        val tracker = tracker()
        tracker.start(); tracker.start("cloud-b")
    }

    @Test(expected = IllegalArgumentException::class) fun terminalAttemptCannotCompleteTwice() {
        val tracker = tracker()
        tracker.start(); tracker.finish(10); tracker.finish(11)
    }

    @Test(expected = IllegalArgumentException::class) fun invalidAttemptSequenceRejected() {
        val tracker = tracker()
        tracker.start()
        val value = AgentProviderAttemptCodec.encode(tracker.report)
        value.getJSONArray("attempts").getJSONObject(0).put("ordinal", 9)
        AgentProviderAttemptCodec.decode(value)
    }
}
