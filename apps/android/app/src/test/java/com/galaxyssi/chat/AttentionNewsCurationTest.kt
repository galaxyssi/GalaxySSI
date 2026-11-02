package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionNewsCurationTest {
    private val now = 1_800_000_000_000L
    private fun item(id: Int, source: String = "publisher$id.org", topic: String = "topic$id", title: String = "Research discovery number $id") =
        GlobalProactiveInboxItem(id.toString(), setOf("message-$id"), title, "Complete translated article preview", topic,
            GlobalProactiveTarget.NEW_CONVERSATION, false, "", "", emptySet(), now - id, now - id, 0, null,
            newsArticleKey = "article-$id", newsSummary = AttentionNewsSummary(source, setOf(topic), now - id, now - id))
    private fun picks(items: List<GlobalProactiveInboxItem>, limit: Int = 30) = AttentionNewsCuration.select(items, now, limit)

    @Test fun highVolumeTechnologySourceDoesNotCrowdOutOtherInterests() {
        val busy = (1..100).map { item(it, "busy.org", "technology") }
        val varied = (101..130).map { item(it, "source${it % 10}.org", "interest${it % 10}") }
        val selected = picks(busy + varied)
        assertEquals(30, selected.size)
        assertTrue(selected.count { it.toInt() <= 100 } <= 3)
        for (topic in varied.map { it.topic }.distinct()) assertTrue(varied.any { it.topic == topic && it.key in selected })
    }

    @Test fun onePublisherOrOneSubscriptionCanStillFillTheShortlist() {
        assertEquals(30, picks((1..100).map { item(it, "only.org", "only") }).size)
        assertEquals(8, picks((1..8).map { item(it, "only.org", "only") }).size)
    }

    @Test fun duplicatesAreOnlyFoldedForIdenticalSameDayHeadlines() {
        val original = item(1, title = "A substantial new discovery in gene repair")
        val duplicate = item(2, title = "Ａ substantial new discovery in gene repair!")
        val tomorrow = item(3, title = original.title).let { it.copy(newsSummary = it.newsSummary!!.copy(publishedAtMillis = now - 86_400_000)) }
        val changed = item(4, title = "No substantial new discovery in gene repair")
        val versions = listOf(item(5, title = "Model 6.1 is released with new capabilities"),
            item(6, title = "Model 6.2 is released with new capabilities"))
        val short = listOf(item(7, title = "Update"), item(8, title = "Update"))
        val languages = listOf(item(9, title = "A useful new guide to C++ development"),
            item(10, title = "A useful new guide to C development"))
        val selected = picks(listOf(original, duplicate, tomorrow, changed) + versions + short + languages)
        assertTrue("1" in selected); assertFalse("2" in selected)
        assertTrue(selected.containsAll(listOf("3", "4", "5", "6", "7", "8", "9", "10")))
    }

    @Test fun articleSelectionDoesNotAlterOriginalsOrReadAndVerificationState() {
        val rows = (1..100).map { item(it) }
        val before = rows.toList()
        val selected = picks(rows)
        assertEquals(before, rows)
        assertTrue(rows.all { it.isNew && !it.urgent && it.newsSummary!!.selected.not() })
        assertEquals(30, selected.size)
    }

    @Test fun missingMetadataPrivateMessagesAndStaleNewsAreNotCurated() {
        val old = item(3).let { it.copy(newsSummary = it.newsSummary!!.copy(publishedAtMillis = now - 8 * 86_400_000L)) }
        val future = item(4).let { it.copy(newsSummary = it.newsSummary!!.copy(publishedAtMillis = now + 600_000)) }
        val oldKnowledge = item(5).let { it.copy(newsSummary = it.newsSummary!!.copy(publishedAtMillis = 0,
            collectedAtMillis = now - 90 * 86_400_000L, knowledge = true)) }
        val disabled = item(6).let { it.copy(newsSummary = it.newsSummary!!.copy(topics = emptySet())) }
        assertEquals(setOf("5"), picks(listOf(item(1).copy(newsSummary = null), item(2).copy(newsArticleKey = ""),
            old, future, oldKnowledge, disabled)))
    }

    @Test fun prioritiesAndTiesAreDeterministicAndReadsDoNotChangeTheSelection() {
        val rows = (1..80).map { item(it, "one.org", "only") }
        val urgent = item(999, "one.org", "only").copy(urgent = true)
        val selected = picks(rows + urgent)
        assertTrue("999" in selected)
        assertEquals(selected.toList(), picks((rows + urgent).reversed()).toList())
        assertEquals(selected, picks((rows + urgent).map { it.copy(viewedAtMillis = now) }))
        assertTrue(picks(rows, 0).isEmpty())
        assertEquals(30, picks(rows, 1000).size)
    }

    @Test fun overlappingSubscriptionsDoNotDuplicateStoriesOrConsumeEveryTopicQuota() {
        val rows = (1..60).map { id -> item(id).let {
            it.copy(newsSummary = it.newsSummary!!.copy(topics = setOf("ai", "agents", "research")))
        } }
        val selected = picks(rows)
        assertEquals(30, selected.size)
        assertEquals(30, selected.distinct().size)
    }

    @Test fun curatedReaderKeepsItsSnapshotAndArchiveRemainsComplete() {
        val rows = (1..60).map { item(it).let { row -> row.copy(newsSummary = row.newsSummary!!.copy(selected = it <= 30)) } }
        val timeline = ProactiveAttentionTimeline().apply { update(rows, emptySet()); begin(AttentionFeedFilter.CURATED) }
        assertEquals(20, timeline.visible.size)
        while (timeline.loadOlder()) Unit
        assertEquals(30, timeline.visible.size)
        val old = timeline.visible.toList()
        timeline.markRead(setOf(old.first().key), now)
        timeline.update(rows + item(100).let { it.copy(createdAtMillis = now + 1, deliveredAtMillis = now + 1,
            newsSummary = it.newsSummary!!.copy(selected = true)) }, emptySet())
        assertEquals(old.map { it.key }, timeline.visible.map { it.key })
        assertEquals(1, timeline.newerCount)
        timeline.begin(AttentionFeedFilter.ALL)
        while (timeline.loadOlder()) Unit
        assertEquals(61, timeline.visible.size)
    }

    @Test fun tenThousandCandidatesStayBoundedAndStable() {
        val rows = (1..10_000).map { item(it, "source${it % 50}.org", "topic${it % 31}") }
        val started = System.nanoTime()
        val selected = picks(rows)
        println("curation_candidates=10000 selected=${selected.size} elapsed_ms=${(System.nanoTime() - started) / 1_000_000}")
        assertEquals(30, selected.size)
        assertEquals(selected, picks(rows.shuffled(kotlin.random.Random(7))))
    }
}
