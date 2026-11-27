package com.galaxyssi.chat

import java.text.Normalizer
import java.util.Locale

data class AttentionEventReport(val key: String, val article: String, val source: String,
    val title: String, val date: Long, val collected: Long, val readAt: Long)

data class AttentionEvent(val reports: List<AttentionEventReport>) {
    val sources = reports.map { it.source }.distinct().size
    private val lastRead = reports.maxOf { it.readAt }
    fun arrivedSinceRead(report: AttentionEventReport) =
        lastRead > 0 && report.collected > lastRead && report.readAt <= 0
    val newCount = reports.count(::arrivedSinceRead)
}

/** Conservative, offline grouping: shared original headline, topic, publication window and differing publishers. */
internal object AttentionNewsEvents {
    private val spaces = Regex("\\s+")
    private const val WINDOW = 36L * 60 * 60 * 1000
    private fun headline(item: GlobalProactiveInboxItem): String? {
        if (item.title.length !in 12..512 || item.newsArticleKey.isBlank()) return null
        val title = Normalizer.normalize(item.title, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
            .trim().replace(spaces, " ").trimEnd('.', '。')
        if (title.contains('?') || title.contains('？') ||
            (title.count { it in '\u3400'..'\u9fff' } < 12 && title.split(' ').count { it.length > 1 } < 5)) return null
        return title
    }

    fun group(items: List<GlobalProactiveInboxItem>): Map<String, AttentionEvent> {
        val buckets = mutableMapOf<String, MutableList<GlobalProactiveInboxItem>>()
        items.forEach { item ->
            val s = item.newsSummary ?: return@forEach
            if (s.knowledge || s.publishedAtMillis <= 0 || s.topics.isEmpty() || s.source.isBlank()) return@forEach
            val title = headline(item) ?: return@forEach
            buckets.getOrPut(title) { mutableListOf() }.add(item)
        }
        val result = mutableMapOf<String, AttentionEvent>()
        for (bucket in buckets.values) {
            if (bucket.size < 2) continue
            var period = mutableListOf<GlobalProactiveInboxItem>()
            var shared = emptySet<String>()
            fun flush() {
                if (period.size < 2 || period.map { it.newsSummary!!.source }.distinct().size < 2) return
                val reports = period.asReversed().map { i ->
                    val s = i.newsSummary!!
                    AttentionEventReport(i.key, i.newsArticleKey, s.source, i.translatedTitle.ifBlank { i.title },
                        s.publishedAtMillis, s.collectedAtMillis, i.viewedAtMillis)
                }.distinctBy { it.article }
                if (reports.map { it.source }.distinct().size < 2) return
                val event = AttentionEvent(reports)
                reports.forEach { result[it.key] = event }
            }
            for (i in bucket.sortedWith(compareBy<GlobalProactiveInboxItem> { it.newsSummary!!.publishedAtMillis }.thenBy { it.key })) {
                val s = i.newsSummary!!
                val first = period.firstOrNull()?.newsSummary
                if (first != null && (s.publishedAtMillis - first.publishedAtMillis > WINDOW ||
                        shared.intersect(s.topics).isEmpty())) { flush(); period = mutableListOf() }
                shared = if (period.isEmpty()) s.topics else shared.intersect(s.topics)
                period.add(i)
            }
            flush()
        }
        return result
    }
}
