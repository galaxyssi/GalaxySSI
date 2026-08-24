package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentModelDisclosureSummarySessionTest {
    @Test
    fun appendedRoundsClassifyOnlyNewMessages() {
        var classifications = 0
        val session = AgentModelDisclosureSummarySession { text ->
            classifications += 1
            AgentDataDisclosureClassifier.classifyText(text)
        }
        val initial = listOf(
            AgentModelMessage.system("Use current screen_context when required."),
            AgentModelMessage.user("Inspect device status.")
        )

        val first = session.summarize(initial)
        val repeated = session.summarize(initial)
        assertEquals(2, classifications)
        assertEquals(first, repeated)

        val extended = initial + listOf(
            AgentModelMessage(
                role = AgentModelMessageRole.ASSISTANT,
                toolCalls = listOf(
                    AgentModelToolCall("call-1", "signalasi.workspace.file.read", emptyMap())
                )
            ),
            AgentModelMessage(
                role = AgentModelMessageRole.TOOL,
                toolResult = AgentModelToolResultContent(
                    callId = "call-1",
                    toolId = "signalasi.workspace.file.read",
                    status = "success",
                    message = "Read recalled memory"
                )
            )
        )

        val summary = session.summarize(extended)

        assertEquals(4, classifications)
        assertEquals(4, session.observedMessageCount)
        assertEquals(
            extended.joinToString("\n") { message ->
                message.text.ifBlank { message.toolResult?.message.orEmpty() }
            }.length,
            summary.textCharacters
        )
        assertTrue(AgentDisclosedDataKind.MESSAGE_TEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.CONVERSATION_HISTORY in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.TOOL_OUTPUT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.SCREEN_CONTEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.MEMORY_CONTEXT in summary.dataKinds)
        assertTrue(AgentDisclosedDataKind.DEVICE_CONTEXT in summary.dataKinds)
    }

    @Test
    fun changedMessagePrefixRebuildsDisclosureState() {
        var classifications = 0
        val session = AgentModelDisclosureSummarySession { text ->
            classifications += 1
            AgentDataDisclosureClassifier.classifyText(text)
        }
        val initial = listOf(
            AgentModelMessage.system("System policy"),
            AgentModelMessage.user("Inspect screen_context")
        )
        session.summarize(initial)

        val replacement = listOf(
            AgentModelMessage.system("Replacement policy"),
            AgentModelMessage.user("Inspect device status")
        )
        val rebuilt = session.summarize(replacement)

        assertEquals(4, classifications)
        assertTrue(AgentDisclosedDataKind.DEVICE_CONTEXT in rebuilt.dataKinds)
        assertTrue(AgentDisclosedDataKind.SCREEN_CONTEXT !in rebuilt.dataKinds)
    }
}
