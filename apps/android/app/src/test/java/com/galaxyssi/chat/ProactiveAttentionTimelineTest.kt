package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ProactiveAttentionTimelineTest {
    @Test fun arrivalAndReviewDoNotReorderOrReplaceTheReadingSnapshot() {
        val timeline = timeline(100)
        timeline.expanded += "100"
        timeline.update(listOf(item(101)) + (1..100).map { item(it).copy(content = "reviewed") }, emptySet())
        assertEquals((100 downTo 81).map(Int::toString), timeline.visible.map { it.key })
        assertEquals("body-100", timeline.visible.first().content)
        assertEquals(setOf("100"), timeline.expanded)
        assertEquals(1, timeline.newerCount)
    }

    @Test fun continuousOlderPagingReachesEveryRecordWithoutDuplicates() {
        val timeline = timeline(1205)
        while (timeline.loadOlder()) Unit
        assertEquals((1205 downTo 1).map(Int::toString), timeline.visible.map { it.key })
        assertFalse(timeline.hasOlder)
        assertFalse(timeline.loadOlder())
    }

    @Test fun aLargeNewBurstIsLoadedInAdjacentBatchesWithoutGaps() {
        val timeline = timeline(40)
        timeline.update((1..105).map(::item), emptySet())
        assertEquals(65, timeline.newerCount)
        assertTrue(timeline.loadNewer())
        assertEquals("60", timeline.visible.first().key)
        while (timeline.loadNewer()) Unit
        while (timeline.loadOlder()) Unit
        assertEquals((105 downTo 1).map(Int::toString), timeline.visible.map { it.key })
    }

    @Test fun autoReadDoesNotRemoveAnItemFromTheUnreadSnapshot() {
        val timeline = timeline(45, AttentionFeedFilter.UNREAD)
        timeline.markRead(setOf("45", "44"), 1000)
        assertEquals(43, timeline.unreadCount)
        assertEquals("45", timeline.visible.first().key)
        assertFalse(timeline.visible.first().isNew)
        timeline.begin(AttentionFeedFilter.UNREAD)
        assertEquals("43", timeline.visible.first().key)
    }

    @Test fun restoredUnreadSnapshotRetainsReadItemsAndContinuesOlderItems() {
        val timeline = timeline(60, AttentionFeedFilter.UNREAD)
        timeline.loadOlder()
        val keys = timeline.visible.map { it.key }
        val restored = ProactiveAttentionTimeline()
        restored.update((1..61).map { item(it).copy(viewedAtMillis = if (it == 60) 100 else 0) }, emptySet())
        restored.begin(AttentionFeedFilter.UNREAD, keys)
        assertEquals(keys, restored.visible.map { it.key })
        assertEquals(1, restored.newerCount)
        restored.loadOlder()
        assertEquals(60, restored.visible.size)
        assertFalse(restored.visible.first().isNew)
    }

    @Test fun savingDoesNotReorderAndUnsaveDoesNotRemoveTheCurrentRow() {
        val timeline = ProactiveAttentionTimeline()
        timeline.update((1..10).map(::item), setOf("2", "9"))
        timeline.begin(AttentionFeedFilter.SAVED)
        assertEquals(listOf("9", "2"), timeline.visible.map { it.key })
        timeline.update((1..10).map(::item), setOf("2", "7"))
        assertEquals(listOf("9", "2"), timeline.visible.map { it.key })
        timeline.begin(AttentionFeedFilter.SAVED)
        assertEquals(listOf("7", "2"), timeline.visible.map { it.key })
    }

    @Test fun deletedRestoreKeysAreSkippedAndEmptySnapshotCanReceiveNews() {
        val timeline = ProactiveAttentionTimeline()
        timeline.update(emptyList(), emptySet()); timeline.begin(AttentionFeedFilter.ALL, listOf("missing"))
        assertTrue(timeline.visible.isEmpty())
        timeline.update(listOf(item(1)), emptySet())
        assertTrue(timeline.visible.isEmpty())
        assertTrue(timeline.loadNewer())
        assertEquals("1", timeline.visible.single().key)
    }

    @Test fun readDwellRequiresContinuousForegroundVisibility() {
        val dwell = AttentionReadDwell()
        assertTrue(dwell.sample(setOf("a"), 0, true).isEmpty())
        assertTrue(dwell.sample(setOf("a"), 1999, true).isEmpty())
        assertEquals(setOf("a"), dwell.sample(setOf("a"), 2000, true))
        assertTrue(dwell.sample(setOf("a"), 3000, false).isEmpty())
        assertTrue(dwell.sample(setOf("a"), 9000, true).isEmpty())
        assertEquals(setOf("a"), dwell.sample(setOf("a"), 11000, true))
    }

    @Test fun aReloadStartedBeforeReadCommitCannotMakeTheItemUnreadAgain() {
        val timeline = timeline(10)
        timeline.markRead(setOf("10"), 1000)
        timeline.update((1..10).map(::item), emptySet())
        assertEquals(9, timeline.unreadCount)
        assertFalse(timeline.visible.first().isNew)
    }

    @Test fun fastScrollAndFocusLossResetDwell() {
        val dwell = AttentionReadDwell()
        dwell.sample(setOf("a"), 0, true)
        dwell.sample(setOf("b"), 500, true)
        assertTrue(dwell.sample(setOf("a"), 2000, true).isEmpty())
        dwell.reset()
        assertTrue(dwell.sample(setOf("a"), 5000, true).isEmpty())
    }

    @Test fun onlyFullyOffscreenArticlesCollapseWithoutChangingTheSnapshot() {
        val timeline = timeline(20)
        val before = timeline.visible.toList()
        timeline.expanded += setOf("20", "15", "10")
        assertTrue(timeline.collapseOutsideViewport(setOf("16", "15", "14")))
        assertEquals(setOf("15"), timeline.expanded)
        assertEquals(before, timeline.visible)
        assertFalse(timeline.collapseOutsideViewport(setOf("15")))
        assertTrue(timeline.collapseOutsideViewport(setOf("20", "19")))
        assertTrue(timeline.expanded.isEmpty())
    }

    @Test fun anEmptyViewportDuringLayoutDoesNotDiscardExpandedState() {
        val timeline = timeline(20)
        timeline.expanded += "20"
        assertFalse(timeline.collapseOutsideViewport(emptySet()))
        assertEquals(setOf("20"), timeline.expanded)
    }

    private fun timeline(count: Int, filter: AttentionFeedFilter = AttentionFeedFilter.ALL) = ProactiveAttentionTimeline().apply {
        update((1..count).map(::item), emptySet()); begin(filter)
    }
    private fun item(index: Int) = GlobalProactiveInboxItem(index.toString(), setOf("message-$index"), "Title $index", "body-$index", "topic",
        GlobalProactiveTarget.NEW_CONVERSATION, false, "", "", emptySet(), index.toLong(), index.toLong(), 0L, null)
}
