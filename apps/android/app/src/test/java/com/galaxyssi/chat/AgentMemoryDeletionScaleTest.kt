package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentMemoryDeletionScaleTest {
    private fun memory(index: Int) = AgentMemoryItem(AgentMemoryKind.PREFERENCE, "\u8bb0\u5fc6-$index",
        id = "memory-$index", key = "key-$index", timestampMillis = 1)

    @Test fun oneDeletionRoundTripsAllIdsFingerprintsAndRetractions() {
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone((0 until 2_101).map(::memory), 2)!!
        assertTrue(tombstone.retractedEventIds.size > 2_000)
        assertEquals(2_101, tombstone.semanticFingerprints.size)
        assertEquals(tombstone, AgentMemoryCausalDeletionPolicy.decode(AgentMemoryCausalDeletionPolicy.encode(tombstone)))
    }

    @Test fun mergeDoesNotEvictEarlierDeletionsBeyondOldCapacity() {
        val records = (0 until 2_105).map { AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(it)), it + 2L)!! }
        val merged = AgentMemoryCausalDeletionPolicy.merge(records.take(2_000), records.drop(2_000) + records.first())
        assertEquals(records, merged)
        assertTrue(AgentMemoryCausalDeletionPolicy.filterRestoredItems(listOf(memory(0), memory(2_104)), merged).isEmpty())
    }

    @Test fun truncatedOrMissingArraysFailIntegrityInsteadOfDroppingRecords() {
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone((0 until 1_201).map(::memory), 2)!!
        for (field in listOf("memory_ids", "semantic_fingerprints", "retracted_event_ids")) {
            val truncated = AgentMemoryCausalDeletionPolicy.encode(tombstone).put(field, JSONArray())
            assertNull(AgentMemoryCausalDeletionPolicy.decode(truncated))
            val missing = AgentMemoryCausalDeletionPolicy.encode(tombstone).apply { remove(field) }
            assertNull(AgentMemoryCausalDeletionPolicy.decode(missing))
        }
    }

    @Test fun nonStringAndDuplicateSetEntriesAreRejected() {
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(1)), 2)!!
        assertNull(AgentMemoryCausalDeletionPolicy.decode(
            AgentMemoryCausalDeletionPolicy.encode(tombstone).put("memory_ids", JSONArray().put(123))))
        assertNull(AgentMemoryCausalDeletionPolicy.decode(
            AgentMemoryCausalDeletionPolicy.encode(tombstone).put("memory_ids", JSONArray().put("memory-1").put("memory-1"))))
    }

    @Test fun opaqueIdentifiersRetainWhitespaceDuringRoundTrip() {
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(1).copy(id = " id ")), 2)!!
        assertEquals(tombstone, AgentMemoryCausalDeletionPolicy.decode(AgentMemoryCausalDeletionPolicy.encode(tombstone)))
    }

    @Test fun suppressionUsesLatestDeletionTimeAndPermitsNewIdentityAfterwards() {
        val first = AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(1)), 2)!!
        val later = AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(1).copy(id = "later")), 10)!!
        val stale = memory(1).copy(id = "stale", timestampMillis = 9)
        val fresh = memory(1).copy(id = "fresh", timestampMillis = 11)
        assertEquals(listOf(fresh), AgentMemoryCausalDeletionPolicy.filterRestoredItems(listOf(stale, fresh), listOf(later, first)))
    }

    @Test fun largeSuppressionIndexDoesNotLoseOldOrNewMembership() {
        val items = (0 until 10_000).map(::memory)
        val deletions = items.filterIndexed { index, _ -> index % 2 == 0 }
            .map { AgentMemoryCausalDeletionPolicy.tombstone(listOf(it), 2)!! }
        assertEquals(items.filterIndexed { index, _ -> index % 2 != 0 },
            AgentMemoryCausalDeletionPolicy.filterRestoredItems(items, deletions))
    }

    @Test fun malformedMemoryBackupIsNotSilentlyPartiallyRestored() {
        try {
            AgentMemoryCausalDeletionPolicy.filterBackupItems(JSONArray().put(JSONObject()).put("invalid"), emptyList())
            fail("Malformed memory input must fail")
        } catch (_: IllegalStateException) { }
    }

    @Test fun missingIdentityValueAndDuplicateMemoryRowsAreRejected() {
        val valid = JSONObject().put("id", "one").put("value", "\u8bb0\u5fc6")
        val cases = listOf(JSONArray().put(JSONObject().put("value", "\u8bb0\u5fc6")),
            JSONArray().put(JSONObject().put("id", "one")), JSONArray().put(valid).put(valid))
        cases.forEach { input ->
            try {
                AgentMemoryCausalDeletionPolicy.filterBackupItems(input, emptyList())
                fail("Invalid memory identity must fail restoration")
            } catch (_: IllegalStateException) { }
        }
    }

    @Test fun legacyMissingScopeMatchesTheStoredGlobalNamespace() {
        val record = AgentMemoryCausalDeletionPolicy.tombstone(listOf(memory(1)), 2)!!
        val legacy = JSONObject().put("id", "older-version").put("value", "\u65e7\u8bb0\u5fc6")
            .put("key", "key-1").put("kind", "PREFERENCE").put("timestamp_millis", 1)
        assertEquals(0, AgentMemoryCausalDeletionPolicy.filterBackupItems(JSONArray().put(legacy), listOf(record)).length())
    }
}
