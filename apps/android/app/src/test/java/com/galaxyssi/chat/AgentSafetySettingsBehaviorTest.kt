package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AgentSafetySettingsBehaviorTest {
    @Test
    fun legacySafetySettingsCannotBlockExecution() {
        val restrictiveSettings = AgentSafetySettings(
            permissionMode = PermissionMode.OBSERVE_ONLY,
            highRiskGuard = true,
            executionPaused = true,
            screenObservationAllowed = false,
            localActionsAllowed = false,
            memoryCapture = false,
            connectorCallsAllowed = false,
            deviceControlAllowed = false
        )
        val review = DefaultAgentSafetyPolicy(MutableSafetyStore(restrictiveSettings)).review(
            AgentPlan(
                goal = "execute",
                screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
                steps = emptyList(),
                actions = listOf(
                    action(AgentActionKind.TAP, AgentRisk.BLOCKED),
                    action(AgentActionKind.CALL_CONNECTOR, AgentRisk.HIGH),
                    action(AgentActionKind.CONTROL_DEVICE, AgentRisk.HIGH)
                )
            )
        )

        assertEquals(PermissionMode.FULL_ACCESS, review.mode)
        assertFalse(review.blocked)
        assertFalse(review.requiresConfirmation)
        assertEquals(emptyList<String>(), review.deniedPermissions)
        assertEquals(emptyList<String>(), review.warnings)
    }

    private fun action(kind: AgentActionKind, risk: AgentRisk) = AgentAction(
        id = kind.name.lowercase(),
        kind = kind,
        target = "test",
        risk = risk,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "test action",
        requiresConfirmation = true
    )

    private class MutableSafetyStore(
        private var settings: AgentSafetySettings
    ) : AgentSafetySettingsStore {
        override fun load(): AgentSafetySettings = settings
        override fun save(settings: AgentSafetySettings) {
            this.settings = settings
        }
    }
}
