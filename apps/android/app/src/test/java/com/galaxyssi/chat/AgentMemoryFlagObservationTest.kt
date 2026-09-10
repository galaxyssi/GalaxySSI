package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryFlagObservationTest {
    private val item = AgentMemoryItem(AgentMemoryKind.PREFERENCE, "Chinese", id = "target", key = "language",
        scope = AgentMemoryScope.CONVERSATION, scopeId = "one", timestampMillis = 1)
    private val other = item.copy(id = "unrelated", scopeId = "two")

    private fun equivalent(before: AgentMemoryItem, after: AgentMemoryItem): List<GlobalConversationEvent> {
        val full = GlobalPersistentContextObservationExtractor.memoryMutations(listOf(other, before), listOf(other, after), 100)
        val delta = GlobalPersistentContextObservationExtractor.memoryMutations(listOf(before), listOf(after), 100)
        assertEquals(full, delta)
        assertTrue(delta.none { it.messageId == other.id })
        return delta
    }

    @Test fun importanceDeltaMatchesThePreviousWholeCollectionObservation() {
        assertEquals(GlobalConversationEventType.MEMORY_UPDATED, equivalent(item, item.copy(important = true)).single().type)
    }
    @Test fun makingMemoryPrivateStillRetractsThePreviouslyVisibleObservation() {
        val event = equivalent(item, item.copy(privateMemory = true)).single()
        assertEquals(GlobalConversationEventType.MEMORY_DELETED, event.type)
        assertTrue(event.content.isEmpty())
        assertTrue(event.retractedEventIds.isNotEmpty())
    }
    @Test fun makingMemoryPublicStillCreatesItsVisibleObservation() {
        assertEquals(GlobalConversationEventType.MEMORY_CREATED, equivalent(item.copy(privateMemory = true), item).single().type)
    }
    @Test fun privateImportanceAndUnchangedFlagsDoNotPublishPrivateContent() {
        assertTrue(equivalent(item.copy(privateMemory = true), item.copy(privateMemory = true, important = true)).isEmpty())
        assertTrue(equivalent(item, item).isEmpty())
    }
}
