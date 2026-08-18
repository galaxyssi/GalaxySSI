package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentFailureDetailPolicyTest {
    @Test
    fun preservesTheConcreteFailureInsteadOfReplacingItWithFallbackCopy() {
        assertEquals(
            "Git rejected the workspace because safe.directory was not configured.",
            AgentFailureDetailPolicy.visibleMessage(
                error = "  Git rejected the workspace because safe.directory was not configured.  ",
                fallback = "The task did not produce a verified result."
            )
        )
    }

    @Test
    fun usesFallbackOnlyWhenNoConcreteFailureExists() {
        assertEquals(
            "No concrete failure was reported.",
            AgentFailureDetailPolicy.visibleMessage(
                error = "  ",
                fallback = "No concrete failure was reported."
            )
        )
    }
}
