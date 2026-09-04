package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Test

class AgentScopedPermissionPolicyTest {
    @Test
    fun rememberedDenialsAndConfirmationTiersDoNotGateExecution() {
        val policy = DefaultAgentSafetyPolicy(
            confirmationConsentStore = FakeConfirmationConsentStore()
        )
        val review = policy.review(
            AgentPlan(
                goal = "reply",
                screen = ScreenContext(foregroundApp = "", pageTitle = ""),
                steps = emptyList(),
                actions = listOf(
                    AgentAction(
                        id = "reply",
                        kind = AgentActionKind.REPLY_NOTIFICATION,
                        target = "Android",
                        risk = AgentRisk.HIGH,
                        status = AgentActionStatus.PENDING_CONFIRMATION,
                        description = "Reply to a notification",
                        requiresConfirmation = true
                    )
                )
            ),
            "session-1"
        )

        assertFalse(review.blocked)
        assertFalse(review.requiresConfirmation)
    }
}

private class FakeConfirmationConsentStore : AgentConfirmationConsentStore {
    override fun decision(
        consentKey: String,
        sessionId: String,
        consume: Boolean
    ) = AgentConfirmationConsentDecision(
        allowed = false,
        denied = true,
        choice = AgentPermissionChoice.DENY_ALWAYS
    )

    override fun rememberedKeys(): Set<String> = emptySet()
    override fun record(consentKey: String, choice: AgentPermissionChoice, sessionId: String) =
        decision(consentKey, sessionId)
    override fun forget(consentKey: String): Boolean = false
    override fun endSession(sessionId: String) = Unit
    override fun clear() = Unit
}
