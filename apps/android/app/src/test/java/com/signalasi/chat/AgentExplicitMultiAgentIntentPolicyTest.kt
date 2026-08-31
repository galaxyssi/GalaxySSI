package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExplicitMultiAgentIntentPolicyTest {
    @Test
    fun recognizesExplicitEnglishCoordinationRequests() {
        assertTrue(
            AgentExplicitMultiAgentIntentPolicy.matches(
                "Use multiple Agents to estimate memory; one should calculate and another should audit"
            )
        )
        assertTrue(
            AgentExplicitMultiAgentIntentPolicy.matches(
                "Two independent agents must review the retry design"
            )
        )
    }

    @Test
    fun recognizesExplicitChineseCoordinationRequests() {
        assertTrue(
            AgentExplicitMultiAgentIntentPolicy.matches(
                "\u8bf7\u7528\u591a Agent \u5b8c\u6210\u8fd9\u4e2a\u4efb\u52a1"
            )
        )
        assertTrue(
            AgentExplicitMultiAgentIntentPolicy.matches(
                "\u8ba9\u4e24\u4e2a\u667a\u80fd\u4f53\u72ec\u7acb\u5206\u6790\u540e\u5408\u5e76\u7ed3\u8bba"
            )
        )
    }

    @Test
    fun doesNotCaptureOrdinaryAgentTopicsOrSingleAgentRequests() {
        assertFalse(AgentExplicitMultiAgentIntentPolicy.matches("Compare multi-agent frameworks"))
        assertFalse(AgentExplicitMultiAgentIntentPolicy.matches("Ask Codex to inspect phone memory"))
        assertFalse(AgentExplicitMultiAgentIntentPolicy.matches("Show the available Agents"))
    }
}
