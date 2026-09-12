package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class KnowledgeIndexKeyMemoTest {
    @Test fun identicalInputsCalculateOnce() = KnowledgeIndexKeyMemo().use { memo ->
        var calls = 0
        repeat(100) { assertEquals("digest", memo.key("source", "private") { calls++; "digest" }) }
        assertEquals(1, calls)
    }

    @Test fun domainsAndUnicodeRemainDistinct() = KnowledgeIndexKeyMemo().use { memo ->
        val inputs = listOf("id" to "\u79c1\u5bc6", "source" to "\u79c1\u5bc6",
            "a:b" to "c", "a" to "b:c", "" to "", "id" to "\uD83D\uDE80")
        inputs.forEachIndexed { i, (kind, value) -> assertEquals("$i", memo.key(kind, value) { "$i" }) }
        inputs.forEachIndexed { i, (kind, value) -> assertEquals("$i", memo.key(kind, value) { error("cache miss") }) }
    }

    @Test fun capacityEvictsLeastRecentlyUsedOnly() = KnowledgeIndexKeyMemo(2).use { memo ->
        memo.key("id", "a") { "a" }; memo.key("id", "b") { "b" }
        memo.key("id", "a") { error("cache miss") }; memo.key("id", "c") { "c" }
        assertEquals(2, memo.size)
        assertEquals("a", memo.key("id", "a") { error("a was evicted") })
        assertEquals("new b", memo.key("id", "b") { "new b" })
        assertEquals(2, memo.size)
    }

    @Test fun failuresAreNotCached() = KnowledgeIndexKeyMemo().use { memo ->
        assertThrows(IllegalStateException::class.java) { memo.key("id", "a") { error("hardware unavailable") } }
        assertEquals(0, memo.size)
        assertEquals("retry", memo.key("id", "a") { "retry" })
    }

    @Test fun closeClearsEntriesAndRejectsReuse() {
        val memo = KnowledgeIndexKeyMemo()
        memo.key("id", "a") { "a" }; memo.close(); memo.close()
        assertEquals(0, memo.size)
        assertThrows(IllegalStateException::class.java) { memo.key("id", "a") { "a" } }
    }

    @Test fun largeInputDoesNotIncreaseEntryBudget() = KnowledgeIndexKeyMemo(3).use { memo ->
        repeat(20) { i -> memo.key("source", "z".repeat(100_000) + i) { "$i" } }
        assertEquals(3, memo.size)
    }
}
