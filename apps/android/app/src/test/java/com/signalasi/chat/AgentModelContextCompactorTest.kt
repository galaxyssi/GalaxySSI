package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentModelContextCompactorTest {
    @Test
    fun compactionSessionEstimatesOnlyNewMessagesAcrossModelRounds() {
        var estimationCount = 0
        val session = AgentModelContextCompactionSession { message ->
            estimationCount += 1
            AgentModelContextCompactor.estimateMessage(message)
        }
        val budget = ConversationContextBudget(
            contextWindowTokens = 32_000,
            reservedOutputTokens = 4_000
        )
        val initial = listOf(
            AgentModelMessage.system("Use tools carefully."),
            AgentModelMessage.user("Inspect the phone workspace.")
        )

        session.compact(initial, budget)
        assertEquals(2, estimationCount)

        val extended = initial + listOf(
            AgentModelMessage(
                role = AgentModelMessageRole.ASSISTANT,
                toolCalls = listOf(
                    AgentModelToolCall(
                        callId = "call-1",
                        toolId = "signalasi.workspace.file.read",
                        arguments = mapOf("path" to "/workspace/README.md")
                    )
                )
            ),
            AgentModelMessage(
                role = AgentModelMessageRole.TOOL,
                toolResult = AgentModelToolResultContent(
                    callId = "call-1",
                    toolId = "signalasi.workspace.file.read",
                    status = "success",
                    output = mapOf("content" to "project context ".repeat(1_000)),
                    message = "Read README.md"
                )
            )
        )

        session.compact(extended, budget)

        assertEquals(4, estimationCount)
        assertEquals(4, session.cachedMessageCount)
    }

    @Test
    fun oldToolBlocksCompactWithoutBreakingCallResultPairs() {
        val messages = buildList {
            add(AgentModelMessage.system("Use tools carefully."))
            add(AgentModelMessage.user("Inspect all files and report the result."))
            repeat(8) { index ->
                add(
                    AgentModelMessage(
                        role = AgentModelMessageRole.ASSISTANT,
                        toolCalls = listOf(
                            AgentModelToolCall(
                                callId = "call-$index",
                                toolId = "signalasi.workspace.file.read",
                                arguments = mapOf(
                                    "path" to "/workspace/file-$index.txt",
                                    "content" to "argument ".repeat(300)
                                )
                            )
                        )
                    )
                )
                add(
                    AgentModelMessage(
                        role = AgentModelMessageRole.TOOL,
                        toolResult = AgentModelToolResultContent(
                            callId = "call-$index",
                            toolId = "signalasi.workspace.file.read",
                            status = "success",
                            output = mapOf("content" to "tool output ".repeat(1_000)),
                            message = "Read file $index"
                        )
                    )
                )
            }
        }

        val result = AgentModelContextCompactor.compact(
            messages,
            ConversationContextBudget(
                contextWindowTokens = 8_192,
                reservedOutputTokens = 2_048,
                triggerRatio = 0.40,
                targetRatio = 0.30
            )
        )

        assertTrue(result.compacted)
        assertTrue(result.compactedEstimatedTokens < result.originalEstimatedTokens)
        assertTrue(result.messages.size < messages.size)
        assertTrue(result.messages.any {
            it.role == AgentModelMessageRole.SYSTEM &&
                it.text.contains("[EARLIER TOOL ACTIVITY - REFERENCE ONLY]")
        })
        val retainedCallIds = result.messages
            .flatMap(AgentModelMessage::toolCalls)
            .mapTo(linkedSetOf(), AgentModelToolCall::callId)
        val retainedResultIds = result.messages
            .mapNotNull(AgentModelMessage::toolResult)
            .mapTo(linkedSetOf(), AgentModelToolResultContent::callId)
        assertTrue(retainedCallIds.isNotEmpty())
        assertTrue(retainedCallIds == retainedResultIds)
        assertTrue(result.messages.last() == messages.last())
    }
}
