package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDirectActionContextTest {
    @Test
    fun `direct connector action carries durable turn identity and conversation context`() {
        val context = AgentConversationContext(
            conversationId = "conversation-1",
            summary = "Earlier summary",
            turns = listOf(
                AgentTranscriptEntry(
                    id = "entry-1",
                    role = AgentTranscriptRole.USER,
                    text = "Earlier question",
                    timestampMillis = 1L,
                    conversationId = "conversation-1",
                    turnId = "turn-1"
                ),
                AgentTranscriptEntry(
                    id = "entry-2",
                    role = AgentTranscriptRole.USER,
                    text = "Follow-up question",
                    timestampMillis = 2L,
                    conversationId = "conversation-1",
                    turnId = "turn-2"
                )
            ),
            privateMode = false
        )
        val action = AgentAction(
            id = "connector-cloud-models",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "DeepSeek",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            description = "Ask DeepSeek",
            parameters = mapOf("connector_id" to "cloud-models")
        )

        val bound = action.withDirectConversationContext(
            conversationContext = context,
            turnId = "turn-2",
            goal = "Follow-up question",
            executionMode = AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals("conversation-1", bound.parameters["_galaxyssi_conversation_id"])
        assertEquals("turn-2", bound.parameters["_galaxyssi_turn_id"])
        assertEquals("turn-2", bound.parameters["_galaxyssi_task_id"])
        assertEquals("Follow-up question", bound.parameters["original_goal"])
        assertEquals("false", bound.parameters["_galaxyssi_conversation_has_attachments"])
        assertEquals("auto_complete", bound.parameters["_galaxyssi_task_execution_mode"])
        assertEquals("cloud-models", bound.parameters["connector_id"])
        assertTrue(bound.parameters["_galaxyssi_conversation_context"].orEmpty().contains("Earlier question"))
        assertTrue(!bound.parameters["_galaxyssi_conversation_context"].orEmpty().contains("Follow-up question"))
    }

    @Test
    fun `private direct connector action disables long-term writes`() {
        val context = AgentConversationContext(
            conversationId = "private-conversation",
            summary = "",
            turns = emptyList(),
            privateMode = true
        )
        val action = AgentAction(
            id = "connector-cloud-models",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Cloud Models",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            description = "Ask a cloud model"
        )

        val bound = action.withDirectConversationContext(
            conversationContext = context,
            turnId = "turn-private",
            goal = "Private question",
            executionMode = AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals("false", bound.parameters["_galaxyssi_long_term_write_allowed"])
    }

    @Test
    fun `explicit action execution mode survives conversation binding`() {
        val context = AgentConversationContext(
            conversationId = "project-conversation",
            summary = "",
            turns = emptyList(),
            privateMode = false
        )
        val action = AgentAction(
            id = "supervise-phone-project",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PROPOSED,
            description = "Plan the next phone project step",
            parameters = mapOf(
                "connector_id" to "codex",
                INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue
            )
        )

        val bound = action.withDirectConversationContext(
            conversationContext = context,
            turnId = "project-turn",
            goal = "Clone the repository on this phone",
            executionMode = AgentTaskExecutionMode.AUTO_COMPLETE
        )

        assertEquals("plan_only", bound.parameters[INTERNAL_TASK_EXECUTION_MODE])
    }
}
