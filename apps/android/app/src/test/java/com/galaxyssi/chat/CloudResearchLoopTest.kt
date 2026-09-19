package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.runBlocking

class CloudResearchLoopTest {
    @Test fun swallowedTransportCancellationStillBecomesToolTimeout(): Unit = runBlocking {
        var now = 0L
        val budget = AgentWebExecutionBudget(100) { now }
        try {
            budget.execute { _, _ ->
                now = 101_000_000L
                "transport-returned-an-error-result"
            }
            fail("Expired tools must not return a global-stop instruction")
        } catch (_: AgentWebBudgetExceededException) { }
    }

    @Test fun toolTimeoutDoesNotInstructModelToStopAllResearch() {
        val output = CloudWebGrounding.failureResult("web_search", AgentWebBudgetExceededException())
        assertEquals("web_tool_timeout", output.getString("error_code"))
        assertTrue(output.getString("next_action").contains("Continue with independent sources"))
        assertFalse(output.getString("next_action").contains("Stop web calls"))
    }

    @Test fun threeStagnantBatchesConvergeButNewEvidenceResetsTheCounter() {
        val progress = CloudWebToolLoopProgress()
        assertFalse(progress.observeEvidenceBatch(emptyList()))
        assertFalse(progress.observeEvidenceBatch(emptyList()))
        assertFalse(progress.observeEvidenceBatch(listOf("""{"evidence_pack":{"items":[{"url":"https://example.com"}]}}""")))
        assertFalse(progress.observeEvidenceBatch(emptyList()))
        assertFalse(progress.observeEvidenceBatch(emptyList()))
        assertTrue(progress.observeEvidenceBatch(emptyList()))
    }

    @Test fun usefulResearchContinuesPastOldDeadlineAndSixtySources() {
        var now = 0L
        val loop = CloudResearchLoop(CloudResearchLimits()) { now }
        repeat(16) { round ->
            loop.beginModelRound()
            assertTrue(loop.reserveTools(1))
            val items = JSONArray()
            repeat(5) { items.put(JSONObject().put("url", "https://source${round * 5 + it}.example/report")) }
            loop.observe(JSONObject().put("evidence_pack", JSONObject().put("items", items)).toString())
            now += 10_000
            assertNull(loop.stopReason())
        }
        assertEquals(80, loop.sourceCount)
        assertEquals(160_000L, loop.elapsedMillis)
        assertTrue(loop.guidance().contains("specific unanswered"))
    }

    @Test fun safetyCeilingsStopNewToolsWithoutRemovingEvidence() {
        val loop = CloudResearchLoop(CloudResearchLimits(maxToolCalls = 2))
        assertTrue(loop.reserveTools(2))
        assertFalse(loop.reserveTools(1))
        assertEquals("tool_limit", loop.stopReason())
        assertTrue(loop.guidance(loop.stopReason()).contains("partial answer"))
        assertTrue(loop.guidance(loop.stopReason()).contains("unresolved"))
    }

    @Test fun oversizedBatchIsRejectedBeforeAnyExecution() {
        val loop = CloudResearchLoop(CloudResearchLimits(maxToolCalls = 2))
        assertFalse(loop.reserveTools(3))
        assertEquals(0, loop.toolCalls)
    }

    @Test fun elapsedAndRoundAndEvidenceLimitsAreIndependent() {
        var now = 0L
        val elapsed = CloudResearchLoop(CloudResearchLimits(maxActiveMillis = 1_000)) { now }
        now = 1_000
        assertEquals("active_time_limit", elapsed.stopReason())
        val rounds = CloudResearchLoop(CloudResearchLimits(maxModelRounds = 2))
        repeat(2) { rounds.beginModelRound() }
        assertEquals("round_limit", rounds.stopReason())
        val evidence = CloudResearchLoop(CloudResearchLimits(maxEvidenceChars = 4))
        evidence.observe("12345")
        assertEquals("evidence_limit", evidence.stopReason())
    }

    @Test fun restoredSourcesAreDeduplicatedAndChargeToolAllowance() {
        val loop = CloudResearchLoop(CloudResearchLimits())
        val output = """{"evidence_pack":{"items":[{"url":"https://example.com/report"}]}}"""
        repeat(2) { loop.observe(output, restored = true) }
        assertEquals(1, loop.sourceCount)
        assertEquals(2, loop.toolCalls)
    }

    @Test fun configurableLimitsAreClampedAndSynthesisHasIndependentAllowance() {
        val limits = CloudResearchLimits.from(JSONObject().put("cloud_research_limits", JSONObject()
            .put("tool_calls", 99999).put("model_rounds", -1).put("active_minutes", 0)
            .put("tool_timeout_seconds", 5).put("model_timeout_seconds", 120)))
        assertEquals(4096, limits.maxToolCalls)
        assertEquals(4, limits.maxModelRounds)
        assertEquals(0L, limits.maxActiveMillis)
        assertEquals(5_000L, limits.toolTimeoutMillis)
        assertEquals(120_000L, limits.modelTimeoutMillis)
    }

    @Test fun independentToolDeadlineDoesNotInheritEarlierElapsedTime() {
        var now = 0L
        val first = AgentWebExecutionBudget(100) { now }
        now = 101_000_000
        assertTrue(first.expired)
        val next = AgentWebExecutionBudget(100) { now }
        assertFalse(next.expired)
        assertEquals(100L, next.remainingMillis)
    }

    @Test fun defaultResearchDoesNotStopAtTwentyMinutesOrHours() {
        var now = 0L
        val loop = CloudResearchLoop(CloudResearchLimits.from(JSONObject())) { now }
        now = 12 * 60 * 60_000L
        assertNull(loop.stopReason())
        assertEquals(512, loop.limits.maxToolCalls)
        assertEquals(256, loop.limits.maxModelRounds)
        assertEquals(8_000_000, loop.limits.maxEvidenceChars)
    }
}
