package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentVoiceRunReferenceTest {
    private val reference = AgentVoiceRunReference("run", "conversation", "turn", "task")

    @Test fun exactIdentityMatches() {
        assertTrue(reference.matches("conversation", "turn", "task"))
    }

    @Test fun differentConversationTurnOrTaskCannotInvokeVoiceActions() {
        assertFalse(reference.matches("other", "turn", "task"))
        assertFalse(reference.matches("conversation", "other", "task"))
        assertFalse(reference.matches("conversation", "turn", "other"))
    }

    @Test fun incompleteIdentityIsNotAWildcard() {
        assertFalse(reference.copy(runId = "").matches("conversation", "turn", "task"))
        assertFalse(reference.copy(conversationId = "").matches("", "turn", "task"))
        assertFalse(reference.copy(turnId = "").matches("conversation", "", "task"))
        assertFalse(reference.copy(taskId = "").matches("conversation", "turn", ""))
    }

    @Test fun delimitersCannotAliasDifferentIdentities() {
        assertFalse(AgentVoiceRunReference("run", "a:b", "c", "d").matches("a", "b:c", "d"))
    }
}
