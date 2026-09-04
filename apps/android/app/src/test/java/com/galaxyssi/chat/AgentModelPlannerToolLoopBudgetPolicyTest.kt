package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AgentModelPlannerToolLoopBudgetPolicyTest {
    @Test
    fun `compiles every user controlled loop setting into the native tool budget`() {
        val budget = AgentModelPlannerToolLoopBudgetPolicy.compile(
            AgentModelPlannerSettings(
                maxToolCalls = 27,
                maxLoopIterations = 19,
                maxPhaseRetries = 4,
                noProgressTimeoutSeconds = 420
            )
        )

        assertEquals(27, budget.maxToolCalls)
        assertEquals(19, budget.maxRounds)
        assertEquals(4, budget.maxRetriesPerCall)
        assertEquals(420_000L, budget.maxDurationMillis)
        assertFalse(budget.enforceCountLimits)
    }

    @Test
    fun `uses planner defaults instead of legacy hidden limits`() {
        val budget = AgentModelPlannerToolLoopBudgetPolicy.compile(AgentModelPlannerSettings())

        assertEquals(16, budget.maxToolCalls)
        assertEquals(8, budget.maxRounds)
        assertEquals(2, budget.maxRetriesPerCall)
        assertEquals(180_000L, budget.maxDurationMillis)
        assertEquals(2, budget.maxDepth)
        assertEquals(12_000L, budget.maxTokens)
        assertFalse(budget.enforceCountLimits)
    }
}
