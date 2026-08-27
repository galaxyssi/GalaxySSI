package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentTranscriptDecodeCacheTest {
    @Test
    fun returnsOnlyEntryMatchingCurrentEncryptedPayload() {
        val cache = AgentTranscriptDecodeCache(capacity = 2)
        val entry = transcriptEntry("entry-1", "first")

        cache.put(entry.id, "ciphertext-a", entry)

        assertEquals(entry, cache.get(entry.id, "ciphertext-a"))
        assertNull(cache.get(entry.id, "ciphertext-b"))
    }

    @Test
    fun evictsLeastRecentlyUsedEntryWithoutLimitingPersistedHistory() {
        val cache = AgentTranscriptDecodeCache(capacity = 2)
        val first = transcriptEntry("entry-1", "first")
        val second = transcriptEntry("entry-2", "second")
        val third = transcriptEntry("entry-3", "third")
        cache.put(first.id, "ciphertext-1", first)
        cache.put(second.id, "ciphertext-2", second)
        assertEquals(first, cache.get(first.id, "ciphertext-1"))

        cache.put(third.id, "ciphertext-3", third)

        assertEquals(first, cache.get(first.id, "ciphertext-1"))
        assertNull(cache.get(second.id, "ciphertext-2"))
        assertEquals(third, cache.get(third.id, "ciphertext-3"))
    }

    @Test
    fun expiresDecodedTranscriptEntries() {
        var now = 10L
        val cache = AgentTranscriptDecodeCache(
            capacity = 2,
            ttlNanos = 30L,
            clockNanos = { now }
        )
        val entry = transcriptEntry("entry-1", "sensitive")
        cache.put(entry.id, "ciphertext", entry)

        now = 40L

        assertNull(cache.get(entry.id, "ciphertext"))
    }

    private fun transcriptEntry(id: String, text: String) = AgentTranscriptEntry(
        id = id,
        role = AgentTranscriptRole.ASSISTANT,
        text = text,
        timestampMillis = 1L,
        conversationId = "conversation-1"
    )
}
