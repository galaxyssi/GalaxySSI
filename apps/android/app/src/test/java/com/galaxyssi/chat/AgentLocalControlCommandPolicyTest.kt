package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentLocalControlCommandPolicyTest {
    @Test
    fun recognizesPhoneLocalPermissionCommands() {
        assertEquals(
            PermissionMode.FULL_ACCESS,
            AgentLocalControlCommandPolicy.permissionMode("set permission mode full access")
        )
        assertEquals(
            PermissionMode.AUTO_LOW_RISK,
            AgentLocalControlCommandPolicy.permissionMode("agent mode automatic")
        )
        assertEquals(
            PermissionMode.FULL_ACCESS,
            AgentLocalControlCommandPolicy.permissionMode(
                "\u8bbe\u7f6e\u5b8c\u5168\u8bbf\u95ee\u7684\u6743\u9650"
            )
        )
        assertTrue(AgentLocalControlCommandPolicy.matches("high-risk guard off"))
    }

    @Test
    fun doesNotCaptureOrdinaryAgentRequests() {
        assertFalse(AgentLocalControlCommandPolicy.matches("Ask Codex to update the Android app"))
        assertFalse(AgentLocalControlCommandPolicy.matches("Give this project full access to the repository"))
    }
}
