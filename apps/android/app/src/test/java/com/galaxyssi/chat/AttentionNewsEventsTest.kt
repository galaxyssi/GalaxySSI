package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionNewsEventsTest {
    private val hour = 3_600_000L
    private val base = 1_800_000_000_000L
    private val title = "Mission team publishes the first detailed observations of Venus"
    private fun article(i: Int, h: Int, source: String = "source-$i", headline: String = title,
        topic: String = "space", read: Long = 0): GlobalProactiveInboxItem {
        val at = base + h * hour
        return GlobalProactiveInboxItem("key-$i", setOf("message-$i"), headline, "Independent account $i", topic,
            GlobalProactiveTarget.NEW_CONVERSATION, false, "", "", emptySet(), at, at, read, null,
            newsArticleKey = "article-$i", newsSummary = AttentionNewsSummary(source, setOf(topic), at, at, originalTitle = headline))
    }
    @Test fun newCoverageIsRelativeToRecordedReadNotTabOpenAndKeepsSeparateArticles() {
        val a = article(1, 0, read = base + hour)
        val b = article(2, 2)
        val c = article(3, 0)
        val items = listOf(a, b, c)
        val group = AttentionNewsEvents.group(items).getValue(a.key)
        assertEquals(3, group.sources); assertEquals(1, group.newCount)
        assertEquals(listOf(b.key), group.reports.filter(group::arrivedSinceRead).map { it.key })
        assertEquals(items.map { it.newsArticleKey }.toSet(), group.reports.map { it.article }.toSet())
        assertEquals(0, AttentionNewsEvents.group(items.map { it.copy(viewedAtMillis = 0) }).getValue(a.key).newCount)
    }
    @Test fun conservativelyExcludesNegationVersionsUnrelatedTopicsKnowledgeAndSamePublisher() {
        val a = article(1, 0)
        val others = listOf(article(2, 1, headline = "No $title"), article(3, 2, topic = "unrelated"),
            article(4, 0, source = "source-1"), article(5, 80), article(6, 1).let {
                it.copy(newsSummary = it.newsSummary!!.copy(knowledge = true)) })
        for (other in others) assertTrue(AttentionNewsEvents.group(listOf(a, other)).isEmpty())
        assertTrue(AttentionNewsEvents.group(listOf(article(1, 0, headline = "$title 6.1"), article(2, 0, headline = "$title 6.2"))).isEmpty())
    }
    @Test fun attributesANewStatementWithoutMergingOpposingReportsOrRepeatingPreviouslyReadText() {
        val before = article(1, 0, read = base + hour).copy(content = "研究团队表示，目前尚未正式公布发射日期。")
        val after = article(2, 2).copy(content = "研究团队表示，目前尚未正式公布发射日期。第二家报道援引公告称，发射日期已确定。")
        val group = AttentionNewsEvents.group(listOf(before, after)).getValue(before.key)
        assertEquals("source-2" to "第二家报道援引公告称，发射日期已确定。", group.newExcerpt)
        assertTrue(group.reports.single { it.source == "source-1" }.excerpts.single().contains("尚未"))
        assertNull(AttentionNewsEvents.group(listOf(before, after.copy(content = before.content))).getValue(before.key).newExcerpt)
        assertNull(AttentionNewsEvents.group(listOf(before.copy(content = ""), after)).getValue(before.key).newExcerpt)
    }
    @Test fun groupingIsDeterministicAndCannotBridgeAcrossDaysOrFromTranslatedTitles() {
        val a = article(1, 0); val b = article(2, 30); val c = article(3, 60)
        val group = AttentionNewsEvents.group(listOf(c, b, a))
        assertEquals(setOf(a.key, b.key), group.keys)
        assertEquals(group, AttentionNewsEvents.group(listOf(a, b, c)))
        val collision = article(2, 1, headline = "Completely different original story from another publisher").copy(title = a.title)
        assertTrue(AttentionNewsEvents.group(listOf(a, collision)).isEmpty())
        assertTrue(AttentionNewsEvents.group(listOf(a, b.copy(newsSummary = b.newsSummary!!.copy(originalTitle = "")))).isEmpty())
    }
}
