package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryBrowseOrderTest {
    @Test fun reverseTimestampEncodingSupportsTheEntireLongRange() {
        val values = listOf(Long.MIN_VALUE, Long.MIN_VALUE + 1, -1, 0, 1, Long.MAX_VALUE - 1, Long.MAX_VALUE)
        assertEquals(values.reversed(), values.sortedBy(AgentMemoryBrowseOrder::time))
        values.forEach { assertEquals(it, AgentMemoryBrowseOrder.time(it).inv()) }
    }
    @Test fun scopeIncludesFiltersPrivacyAndExpiryInstantButNotNavigationDirection() {
        val base = AgentMemoryBrowseRequest()
        val scope = AgentMemoryBrowseOrder.scope(base, "store-a")
        listOf(base.copy(section = AgentMemorySection.HISTORY), base.copy(kinds = setOf(AgentMemoryKind.TASK)),
            base.copy(publicOnly = true), base.copy(nowMillis = 5)).forEach {
            assertNotEquals(scope, AgentMemoryBrowseOrder.scope(it, "store-a"))
        }
        assertNotEquals(scope, AgentMemoryBrowseOrder.scope(base, "store-b"))
        assertEquals(scope, AgentMemoryBrowseOrder.scope(base.copy(backwards = true), "store-a"))
    }
    @Test fun pageSizeIsARequestBoundNotARecordCountLimit() {
        listOf(0, -1, 101, Int.MAX_VALUE).forEach { size ->
            assertNotNull(runCatching { AgentMemoryBrowseOrder.validate(AgentMemoryBrowseRequest(limit = size)) }.exceptionOrNull())
        }
        AgentMemoryBrowseOrder.validate(AgentMemoryBrowseRequest(limit = 100))
        assertNotNull(runCatching { AgentMemoryBrowseOrder.validate(AgentMemoryBrowseRequest(backwards = true)) }.exceptionOrNull())
    }
    @Test fun testStorePagingRoundTripPreservesAllTiedRecords() {
        val store = InMemoryAgentMemoryStore()
        repeat(57) { store.items += AgentMemoryItem(AgentMemoryKind.TASK, "value-$it", id = "id-$it", timestampMillis = 4) }
        val request = AgentMemoryBrowseRequest()
        val first = store.browse(request)
        val second = store.browse(request.copy(cursor = first.next))
        val third = store.browse(request.copy(cursor = second.next))
        assertEquals(57, (first.entries + second.entries + third.entries).map { it.item.id }.toSet().size)
        assertNull(third.next)
        val back = store.browse(request.copy(cursor = second.previous, backwards = true))
        assertEquals(first.entries, back.entries)
    }
    @Test fun testStoreRejectsChangedCursorsAndHidesPrivateExpiredMemory() {
        val store = InMemoryAgentMemoryStore()
        repeat(4) { store.items += AgentMemoryItem(AgentMemoryKind.TASK, "value-$it", id = "id-$it", timestampMillis = it.toLong()) }
        val first = store.browse(AgentMemoryBrowseRequest(limit = 2))
        store.items[0] = store.items[0].copy(privateMemory = true)
        assertTrue(runCatching { store.browse(AgentMemoryBrowseRequest(cursor = first.next)) }.exceptionOrNull() is AgentMemoryPageChanged)
        store.items[1] = store.items[1].copy(expiresAtMillis = 5)
        assertEquals(2, store.browse(AgentMemoryBrowseRequest(publicOnly = true, nowMillis = 10)).entries.size)
    }
}
