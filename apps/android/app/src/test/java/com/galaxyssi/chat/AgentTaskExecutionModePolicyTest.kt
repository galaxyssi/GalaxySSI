package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTaskExecutionModePolicyTest {
    @Test
    fun explicitPlanOnlyOverridesAutomaticDefault() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "\u5148\u7ed9\u65b9\u6848\uff0c\u4e0d\u8981\u6267\u884c\u4efb\u4f55\u64cd\u4f5c",
            AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals(AgentTaskExecutionMode.PLAN_ONLY, resolution.mode)
        assertTrue(resolution.explicitlyRequested)
    }

    @Test
    fun explicitAutoCompleteOverridesPlanOnlyDefault() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "\u6309\u8fd9\u4e2a\u65b9\u6848\u6267\u884c\uff0c\u7ee7\u7eed\u6267\u884c\u5230\u5b8c\u6210",
            AgentTaskExecutionMode.PLAN_ONLY
        )

        assertEquals(AgentTaskExecutionMode.AUTO_COMPLETE, resolution.mode)
        assertTrue(resolution.explicitlyRequested)
    }

    @Test
    fun configuredDefaultAppliesWithoutExplicitSignal() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "\u68c0\u67e5\u8fd9\u4e2a\u9879\u76ee\u7684\u6784\u5efa\u72b6\u6001",
            AgentTaskExecutionMode.PLAN_ONLY
        )

        assertEquals(AgentTaskExecutionMode.PLAN_ONLY, resolution.mode)
        assertFalse(resolution.explicitlyRequested)
    }

    @Test
    fun scopedNegativeInstructionDoesNotDisableWholeTask() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "\u68c0\u67e5\u9879\u76ee\uff0c\u4f46\u4e0d\u8981\u6267\u884c\u5220\u9664\u64cd\u4f5c",
            AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals(AgentTaskExecutionMode.AUTO_COMPLETE, resolution.mode)
        assertFalse(resolution.explicitlyRequested)
    }

    @Test
    fun desktopOnlyExecutionRestrictionKeepsPhoneProjectAutomatic() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "Clone the repository, run the tests on this phone, and package the result. " +
                "Do not execute on Desktop and do not push.",
            AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals(AgentTaskExecutionMode.AUTO_COMPLETE, resolution.mode)
        assertFalse(resolution.explicitlyRequested)
    }

    @Test
    fun globalEnglishDoNotExecuteStillProducesPlanOnly() {
        val resolution = AgentTaskExecutionModePolicy.resolve(
            "Review the repository but do not execute anything.",
            AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals(AgentTaskExecutionMode.PLAN_ONLY, resolution.mode)
        assertTrue(resolution.explicitlyRequested)
    }

    @Test
    fun wireValuesRoundTrip() {
        assertEquals(
            AgentTaskExecutionMode.PLAN_ONLY,
            AgentTaskExecutionMode.fromWireValue("plan_only")
        )
        assertEquals(
            AgentTaskExecutionMode.AUTO_COMPLETE,
            AgentTaskExecutionMode.fromWireValue("AUTO_COMPLETE")
        )
    }
}
