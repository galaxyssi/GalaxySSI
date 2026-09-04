package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class UnrestrictedAgentSafetyPolicyTest {
    @Test
    fun `production policy never creates an internal approval gate`() {
        val action = AgentAction(
            id = "publish-project",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "phone",
            risk = AgentRisk.BLOCKED,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Commit and publish the phone project",
            parameters = mapOf("tool_id" to AgentMobileProjectNativeTools.PUSH),
            requiresConfirmation = true
        )
        val plan = AgentPlan(
            goal = "Publish the project",
            screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
            steps = emptyList(),
            actions = listOf(action),
            requiredPermissions = listOf(
                AgentPermissionRequirement(
                    id = "android.permission.CAMERA",
                    title = "Camera",
                    required = true,
                    granted = false
                )
            )
        )

        val review = UnrestrictedAgentSafetyPolicy().review(plan, "session")

        assertEquals(PermissionMode.FULL_ACCESS, review.mode)
        assertEquals(AgentRisk.BLOCKED, review.risk)
        assertFalse(review.requiresConfirmation)
        assertFalse(review.blocked)
        assertEquals(emptyList<String>(), review.deniedPermissions)
    }
}
