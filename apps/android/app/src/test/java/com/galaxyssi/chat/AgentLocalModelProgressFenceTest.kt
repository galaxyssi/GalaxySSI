package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentLocalModelProgressFenceTest {
    private val identity = AgentLocalDispatchIdentity(123, "local-llm", "conversation", "turn", "native-session", "action")
    private fun event(sequence: Long, type: AgentModelToolLoopEventType = AgentModelToolLoopEventType.TOOL_PROGRESS,
                      loop: String = "local-loop") = AgentModelToolLoopEvent(sequence, type, 1000 + sequence,
        identity.taskId, identity.turnId, identity.taskId, "a".repeat(64), 1,
        details = mapOf("model_loop_id" to loop))

    @Test fun onlyTheExactSessionTurnTaskAndLoopCanAdvanceProgress() {
        val seen = mutableListOf<Long>()
        val sink = AgentLocalModelProgressFence(identity, AgentNativeToolCancellationToken.NONE) { seen += it.sequence }
        sink.onEvent(event(1))
        sink.onEvent(event(9).copy(sessionId = "other"))
        sink.onEvent(event(9).copy(turnId = "other"))
        sink.onEvent(event(9).copy(taskId = "other"))
        sink.onEvent(event(9, loop = "other"))
        sink.onEvent(event(9).copy(details = emptyMap()))
        sink.onEvent(event(2))
        assertEquals(listOf(1L, 2L), seen)
    }

    @Test fun ReplaysAndOutOfOrderEventsCannotReplaceNewerActivity() {
        val seen = mutableListOf<Long>()
        val sink = AgentLocalModelProgressFence(identity, AgentNativeToolCancellationToken.NONE) { seen += it.sequence }
        listOf(1L, 3L, 3L, 2L, 4L).forEach { sink.onEvent(event(it)) }
        assertEquals(listOf(1L, 3L, 4L), seen)
    }

    @Test fun stoppedDispatchNeverManufacturesFreshActivity() {
        val source = AgentNativeToolCancellationSource()
        val seen = mutableListOf<Long>()
        val sink = AgentLocalModelProgressFence(identity, source.token) { seen += it.sequence }
        sink.onEvent(event(1))
        source.cancel()
        sink.onEvent(event(2))
        sink.onEvent(event(3, AgentModelToolLoopEventType.LOOP_COMPLETED))
        assertEquals(listOf(1L), seen)
    }

    @Test fun allTerminalOutcomesFenceLateEventsButWaitingAllowsAnExternalResume() {
        listOf(AgentModelToolLoopEventType.LOOP_COMPLETED, AgentModelToolLoopEventType.LOOP_CANCELLED,
            AgentModelToolLoopEventType.LOOP_FAILED, AgentModelToolLoopEventType.BUDGET_EXCEEDED,
            AgentModelToolLoopEventType.LOOP_DETECTED).forEach { terminal ->
            val seen = mutableListOf<Long>()
            val sink = AgentLocalModelProgressFence(identity, AgentNativeToolCancellationToken.NONE) { seen += it.sequence }
            sink.onEvent(event(1, AgentModelToolLoopEventType.LOOP_WAITING))
            sink.onEvent(event(2, AgentModelToolLoopEventType.LOOP_RESUMED))
            sink.onEvent(event(3, terminal))
            sink.onEvent(event(4))
            assertEquals(terminal.name, listOf(1L, 2L, 3L), seen)
        }
    }

    @Test fun failedPersistenceDoesNotConsumeTheEventOrItsLoopBinding() {
        var fail = true
        val seen = mutableListOf<Long>()
        val sink = AgentLocalModelProgressFence(identity, AgentNativeToolCancellationToken.NONE) {
            if (fail) error("Public storage fixture failure")
            seen += it.sequence
        }
        assertTrue(runCatching { sink.onEvent(event(1, AgentModelToolLoopEventType.LOOP_FAILED)) }.isFailure)
        fail = false
        sink.onEvent(event(1, AgentModelToolLoopEventType.LOOP_FAILED))
        sink.onEvent(event(2))
        assertEquals(listOf(1L), seen)
    }

    @Test fun independentSinksDoNotShareSequenceOrLoopState() {
        val first = mutableListOf<Long>()
        val second = mutableListOf<Long>()
        val a = AgentLocalModelProgressFence(identity, AgentNativeToolCancellationToken.NONE) { first += it.sequence }
        val b = AgentLocalModelProgressFence(identity.copy(sourceMessageId = 124, actionId = "sibling"),
            AgentNativeToolCancellationToken.NONE) { second += it.sequence }
        a.onEvent(event(20, loop = "first"))
        b.onEvent(event(1, loop = "second"))
        assertEquals(listOf(20L), first)
        assertEquals(listOf(1L), second)
    }
}
