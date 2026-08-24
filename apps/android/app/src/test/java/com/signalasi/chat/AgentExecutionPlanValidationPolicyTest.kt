package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AgentExecutionPlanValidationPolicyTest {
    @Test
    fun completedValidationReusesThePreparedPlanWithoutRepeatingPolicyWork() {
        val plan = plan()
        var hardenCalls = 0
        var reviewCalls = 0

        val prepared = AgentExecutionPlanValidationPolicy.prepare(
            plan = plan,
            state = AgentExecutionPlanValidationState.COMPLETED,
            harden = {
                hardenCalls += 1
                it
            },
            review = {
                reviewCalls += 1
                review()
            }
        )

        assertSame(plan, prepared)
        assertEquals(0, hardenCalls)
        assertEquals(0, reviewCalls)
    }

    @Test
    fun unvalidatedEntryHardensAndReviewsExactlyOnce() {
        val plan = plan()
        var hardenCalls = 0
        var reviewCalls = 0

        val prepared = AgentExecutionPlanValidationPolicy.prepare(
            plan = plan,
            state = AgentExecutionPlanValidationState.REQUIRED,
            harden = {
                hardenCalls += 1
                it.copy(revision = it.revision + 1)
            },
            review = {
                reviewCalls += 1
                review()
            }
        )

        assertEquals(1, hardenCalls)
        assertEquals(1, reviewCalls)
        assertEquals(plan.revision + 1, prepared.revision)
        assertEquals(PermissionMode.FULL_ACCESS, prepared.safetyReview.mode)
    }

    private fun plan() = AgentPlan(
        goal = "Improve the phone project",
        screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
        steps = emptyList(),
        actions = emptyList(),
        revision = 3
    )

    private fun review() = AgentSafetyReview(
        risk = AgentRisk.LOW,
        requiresConfirmation = false,
        blocked = false,
        mode = PermissionMode.FULL_ACCESS
    )
}
