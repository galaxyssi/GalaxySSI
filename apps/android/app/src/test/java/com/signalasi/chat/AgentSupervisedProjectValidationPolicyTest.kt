package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class AgentSupervisedProjectValidationPolicyTest {
    @Test
    fun prevalidatedPlanSkipsDuplicateValidation() {
        val validation = AgentPlanValidation(valid = true)
        val validatorCalls = AtomicInteger()

        val validated = AgentSupervisedProjectValidationPolicy.validated(
            plan = plan(),
            prevalidated = validation
        ) {
            validatorCalls.incrementAndGet()
            AgentPlanValidation(valid = true)
        }

        assertSame(validation, requireNotNull(validated).validation)
        assertEquals(0, validatorCalls.get())
    }

    @Test
    fun absentValidationRunsValidatorOnce() {
        val validation = AgentPlanValidation(valid = true)
        val validatorCalls = AtomicInteger()

        val validated = AgentSupervisedProjectValidationPolicy.validated(plan()) {
            validatorCalls.incrementAndGet()
            validation
        }

        assertSame(validation, requireNotNull(validated).validation)
        assertEquals(1, validatorCalls.get())
    }

    @Test
    fun invalidPrevalidationStillRejectsPlanWithoutRevalidating() {
        val validatorCalls = AtomicInteger()

        val validated = AgentSupervisedProjectValidationPolicy.validated(
            plan = plan(),
            prevalidated = AgentPlanValidation(valid = false, issues = listOf("invalid"))
        ) {
            validatorCalls.incrementAndGet()
            AgentPlanValidation(valid = true)
        }

        assertNull(validated)
        assertEquals(0, validatorCalls.get())
    }

    private fun plan() = AgentPlan(
        planId = "validated-supervised-plan",
        goal = "Continue the phone project",
        screen = ScreenContext(
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
        ),
        steps = emptyList(),
        actions = emptyList(),
        plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
    )
}
