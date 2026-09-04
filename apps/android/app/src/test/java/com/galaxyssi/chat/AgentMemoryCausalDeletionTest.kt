package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMemoryCausalDeletionTest {
    @Test
    fun tombstoneContainsOnlyIdentifiersHashesAndRetractions() {
        val deleted = memory(
            id = "memory-v2",
            value = "My private preference is concise output",
            key = "response style",
            timestampMillis = 2_000L
        )

        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deleted), 3_000L)
        assertNotNull(tombstone)
        val encoded = AgentMemoryCausalDeletionPolicy.encode(tombstone!!).toString()

        assertTrue("memory-v2" in tombstone.memoryIds)
        assertTrue(tombstone.retractedEventIds.any { it == "memory-root:memory-v2" })
        assertFalse(encoded.contains(deleted.value))
        assertFalse(encoded.contains(deleted.key))
    }

    @Test
    fun deletedSemanticIdentityCannotReturnFromAnOlderBackup() {
        val deleted = memory(
            id = "memory-current",
            value = "Prefer concise output",
            key = "response style",
            timestampMillis = 2_000L
        )
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deleted), 3_000L)!!
        val staleBackup = memory(
            id = "memory-old-backup",
            value = "Prefer verbose output",
            key = "response style",
            timestampMillis = 1_000L
        )
        val unrelated = memory(
            id = "memory-other",
            value = "Use English",
            key = "language",
            timestampMillis = 1_000L
        )

        val filtered = AgentMemoryCausalDeletionPolicy.filterRestoredItems(
            listOf(staleBackup, unrelated),
            listOf(tombstone)
        )

        assertEquals(listOf(unrelated), filtered)
    }

    @Test
    fun deliberateNewMemoryAfterDeletionIsAllowed() {
        val deleted = memory(
            id = "memory-old",
            value = "Use light mode",
            key = "theme",
            timestampMillis = 1_000L
        )
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deleted), 2_000L)!!
        val newMemory = memory(
            id = "memory-new",
            value = "Use dark mode",
            key = "theme",
            timestampMillis = 3_000L
        )

        assertEquals(
            listOf(newMemory),
            AgentMemoryCausalDeletionPolicy.filterRestoredItems(listOf(newMemory), listOf(tombstone))
        )
    }

    @Test
    fun backupFilterUsesTheSameCausalPolicy() {
        val deleted = memory(
            id = "memory-deleted",
            value = "Old project status",
            key = "project status",
            timestampMillis = 1_000L
        )
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(deleted), 2_000L)!!
        val input = JSONArray()
            .put(memoryJson(deleted))
            .put(memoryJson(memory("memory-safe", "Keep this", "other", 1_500L)))

        val output = AgentMemoryCausalDeletionPolicy.filterBackupItems(input, listOf(tombstone))

        assertEquals(1, output.length())
        assertEquals("memory-safe", output.getJSONObject(0).getString("id"))
    }

    @Test
    fun replayEventRetractsEveryDeletedVersionWithoutRestoringContent() {
        val first = memory("memory-v1", "Use one-line answers", "response style", 1_000L)
        val second = first.copy(
            id = "memory-v2",
            value = "Use concise verified answers",
            version = 2,
            supersedesId = first.id,
            timestampMillis = 2_000L
        )
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(first, second), 3_000L)!!

        val events = AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)
        val event = events.single()

        assertEquals(GlobalConversationEventType.MEMORY_DELETED, event.type)
        assertEquals("retract_only", event.metadata["projection"])
        assertTrue(event.content.isBlank())
        assertTrue(event.retractedEventIds.contains("memory-root:memory-v1"))
        assertTrue(event.retractedEventIds.contains("memory-root:memory-v2"))
        assertEquals(tombstone.retractedEventIds, event.effectiveRetractions())
    }

    @Test
    fun largeDeletionIsSplitWithoutLosingRetractions() {
        val deleted = (1..100).map { index ->
            memory(
                id = "memory-$index",
                value = "Value $index",
                key = "key-$index",
                timestampMillis = index.toLong()
            )
        }
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deleted, 2_000L)!!

        val events = AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)

        assertTrue(events.size > 1)
        assertTrue(events.all { it.retractedEventIds.size <= 128 })
        assertEquals(
            tombstone.retractedEventIds,
            events.flatMapTo(linkedSetOf()) { it.retractedEventIds }
        )
    }

    private fun memory(
        id: String,
        value: String,
        key: String,
        timestampMillis: Long
    ): AgentMemoryItem = AgentMemoryItem(
        id = id,
        kind = AgentMemoryKind.PREFERENCE,
        value = value,
        key = key,
        timestampMillis = timestampMillis
    )

    private fun memoryJson(item: AgentMemoryItem): JSONObject = JSONObject()
        .put("id", item.id)
        .put("kind", item.kind.name)
        .put("value", item.value)
        .put("key", item.key)
        .put("scope", item.scope.name)
        .put("scope_id", item.scopeId)
        .put("timestamp_millis", item.timestampMillis)
}
