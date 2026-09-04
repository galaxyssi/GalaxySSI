package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPreferenceModeTest {
    @Test
    fun wireValuesRoundTripAndUnknownValuesStayCautious() {
        AgentPreferenceMode.entries.forEach { mode ->
            assertEquals(mode, AgentPreferenceMode.fromWireValue(mode.wireValue))
        }
        assertEquals(
            AgentPreferenceMode.CAUTIOUS,
            AgentPreferenceMode.fromWireValue("future-mode")
        )
    }

    @Test
    fun everyPresetKeepsTheHighRiskGuardEnabled() {
        AgentPreferenceMode.entries.forEach { mode ->
            assertTrue(mode.name, AgentPreferenceModePolicy.profile(mode).highRiskGuard)
        }
    }

    @Test
    fun automationRunsLowRiskActionsWhileCautiousModeAsksFirst() {
        assertEquals(
            PermissionMode.AUTO_LOW_RISK,
            AgentPreferenceModePolicy.profile(AgentPreferenceMode.AUTOMATION).permissionMode
        )
        assertEquals(
            PermissionMode.ASK_BEFORE_ACTION,
            AgentPreferenceModePolicy.profile(AgentPreferenceMode.CAUTIOUS).permissionMode
        )
        assertEquals(
            AgentTaskExecutionMode.AUTO_COMPLETE,
            AgentPreferenceModePolicy.profile(AgentPreferenceMode.AUTOMATION).taskExecutionMode
        )
    }

    @Test
    fun developerModeExpandsStructuredDetailsWithoutDisablingSafety() {
        val profile = AgentPreferenceModePolicy.profile(AgentPreferenceMode.DEVELOPER)

        assertTrue(profile.expandStructuredDetails)
        assertTrue(profile.highRiskGuard)
        assertFalse(profile.minimizeClarifications)
    }
}
