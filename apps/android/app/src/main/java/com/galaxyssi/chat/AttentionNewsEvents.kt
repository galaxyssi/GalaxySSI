package com.galaxyssi.chat

import java.text.Normalizer
import java.util.Locale

data class AttentionEventReport(val key: String, val article: String, val source: String,
    val title: String, val date: Long, val collected: Long, val readAt: Long, val excerpts: List<String> = emptyList())

data class AttentionEvent(val reports: List<AttentionEventReport>) {
    val sources = reports.map { it.source }.distinct().size
    private val lastRead = reports.maxOf { it.readAt }
    fun arrivedSinceRead(report: AttentionEventReport) =
        lastRead > 0 && report.collected > lastRead && report.readAt <= 0
    val newCount = reports.count(::arrivedSinceRead)
    val newExcerpt: Pair<String, String>? by lazy {
        val previouslyRead = reports.filter { it.readAt > 0 }.flatMap { it.excerpts }.mapTo(hashSetOf(), ::comparable)
        if (previouslyRead.isEmpty()) null else reports.asSequence().filter(::arrivedSinceRead)
            .mapNotNull { r -> r.excerpts.firstOrNull { comparable(it) !in previouslyRead }?.let { r.source to it } }.firstOrNull()
    }
    private fun comparable(value: String) = Normalizer.normalize(value, Normalizer.Form.NFKC)
        .lowercase(Locale.ROOT).filterNot(Char::isWhitespace).trimEnd('.', '。', '!', '！')
}

/** Conservative, offline grouping: shared original headline, topic, publication window and differing publishers. */
internal object AttentionNewsEvents {
    private val spaces = Regex("\\s+")
    private const val WINDOW = 36L * 60 * 60 * 1000
    private fun excerpts(item: GlobalProactiveInboxItem): List<String> {
        val text = item.content.take(900)
        val sentences = java.text.BreakIterator.getSentenceInstance(Locale.CHINESE).apply { setText(text) }
        val result = mutableListOf<String>()
        var start = sentences.first()
        var end = sentences.next()
        while (end != java.text.BreakIterator.DONE && result.size < 4) {
            val line = text.substring(start, end).trim()
            if (line.length in 12..220 && line.last() in "。.!！？?" && line.none { it == '\n' || it == '<' } &&
                !line.contains("://") && !line.equals(item.title, ignoreCase = true)) result.add(line)
            start = end; end = sentences.next()
        }
        return result
    }
    private fun headline(item: GlobalProactiveInboxItem): String? {
        val original = item.newsSummary?.originalTitle.orEmpty()
        if (original.length !in 12..512 || item.newsArticleKey.isBlank()) return null
        val title = Normalizer.normalize(original, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
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
                        s.publishedAtMillis, s.collectedAtMillis, i.viewedAtMillis, excerpts(i))
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
