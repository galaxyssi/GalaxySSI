package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentScopedPermissionPolicyTest {
    @Test
    fun sessionPermissionOnlySuppressesConfirmationInsideItsSession() {
        val store = FakeConfirmationConsentStore(
            allowedSessionId = "session-1",
            decisionChoice = AgentPermissionChoice.ALLOW_SESSION
        )
        val policy = DefaultAgentSafetyPolicy(confirmationConsentStore = store)
        val plan = plan(locationAction())

        assertFalse(policy.review(plan, "session-1").requiresConfirmation)
        assertTrue(policy.review(plan, "session-2").requiresConfirmation)
    }

    @Test
    fun permanentDenialBlocksTheMatchingTool() {
        val store = FakeConfirmationConsentStore(
            denied = true,
            decisionChoice = AgentPermissionChoice.DENY_ALWAYS
        )
        val review = DefaultAgentSafetyPolicy(
            confirmationConsentStore = store
        ).review(plan(locationAction()), "session-1")

        assertTrue(review.blocked)
        assertTrue("permission_permanently_denied" in review.warnings)
    }

    @Test
    fun consequentialActionStillRequiresConfirmationAfterPersistentAllow() {
        val store = FakeConfirmationConsentStore(
            allowedSessionId = "session-1",
            decisionChoice = AgentPermissionChoice.ALLOW_ALWAYS
        )
        val highRisk = AgentAction(
            id = "reply",
            kind = AgentActionKind.REPLY_NOTIFICATION,
            target = "Android",
            risk = AgentRisk.HIGH,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Reply to a notification"
        )

        val review = DefaultAgentSafetyPolicy(
            confirmationConsentStore = store
        ).review(plan(highRisk), "session-1")

        assertTrue(review.requiresConfirmation)
        assertFalse(review.blocked)
    }

    private fun locationAction() = AgentAction(
        id = "location",
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "Android",
        risk = AgentRisk.MEDIUM,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Read location",
        parameters = mapOf("tool_id" to "android.location.foreground")
    )

    private fun plan(action: AgentAction) = AgentPlan(
        goal = action.description,
        screen = ScreenContext(foregroundApp = "", pageTitle = ""),
        steps = emptyList(),
        actions = listOf(action)
    )
}

private class FakeConfirmationConsentStore(
    private val allowedSessionId: String = "",
    private val denied: Boolean = false,
    private val decisionChoice: AgentPermissionChoice? = null
) : AgentConfirmationConsentStore {
    override fun decision(
        consentKey: String,
        sessionId: String,
        consume: Boolean
    ): AgentConfirmationConsentDecision {
        val sessionMatches = allowedSessionId.isBlank() || allowedSessionId == sessionId
        return AgentConfirmationConsentDecision(
            allowed = !denied && decisionChoice != null && sessionMatches,
            denied = denied && sessionMatches,
            choice = decisionChoice
        )
    }

    override fun rememberedKeys(): Set<String> = emptySet()

    override fun record(
        consentKey: String,
        choice: AgentPermissionChoice,
        sessionId: String
    ) = AgentConfirmationConsentDecision(
        allowed = choice.approved,
        denied = !choice.approved,
        choice = choice
    )

    override fun forget(consentKey: String): Boolean = false

    override fun endSession(sessionId: String) = Unit

    override fun clear() = Unit
}
