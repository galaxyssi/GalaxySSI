package com.galaxyssi.chat

import java.text.Normalizer
import java.util.Locale

/** Public article metadata only; selection never rewrites publication, read or verification state. */
data class AttentionNewsSummary(
    val source: String,
    val topics: Set<String>,
    val publishedAtMillis: Long,
    val collectedAtMillis: Long,
    val knowledge: Boolean = false,
    val selected: Boolean = false
)

/** A diverse reading shortlist, not an AI quality score or a semantic claim merger. */
internal object AttentionNewsCuration {
    const val MAX_ITEMS = 30
    private const val DAY = 86_400_000L

    fun select(items: List<GlobalProactiveInboxItem>, now: Long, limit: Int = MAX_ITEMS): Set<String> {
        if (limit <= 0) return emptySet()
        val maximum = limit.coerceAtMost(MAX_ITEMS)
        val ordered = items.asSequence().filter { item ->
            val summary = item.newsSummary ?: return@filter false
            val date = summary.publishedAtMillis.takeIf { it > 0 } ?: summary.collectedAtMillis
            item.newsArticleKey.isNotBlank() && summary.source.isNotBlank() && summary.topics.isNotEmpty() &&
                date <= now + 5 * 60_000L && (summary.knowledge || date >= now - 7 * DAY)
        }.distinctBy { it.key }.sortedWith(compareByDescending<GlobalProactiveInboxItem> { it.urgent }
            .thenBy { it.newsSummary!!.knowledge }
            .thenByDescending { it.newsSummary!!.publishedAtMillis.takeIf { date -> date > 0 }
                ?: it.newsSummary!!.collectedAtMillis }.thenBy { it.key }).toList()
        val unique = ordered.distinctBy(::headlineKey)
        if (unique.isEmpty()) return emptySet()
        val sources = unique.map { it.newsSummary!!.source }.toSet()
        val topics = unique.flatMap { it.newsSummary!!.topics }.toSet()
        // Sparse subscriptions still get a useful shortlist; busy sources cannot crowd out alternatives.
        val sourceCap = maxOf(3, (maximum + sources.size - 1) / sources.size)
        val topicCap = maxOf(3, (maximum + topics.size - 1) / topics.size)
        val selected = linkedSetOf<String>()
        val sourceCounts = mutableMapOf<String, Int>()
        val topicCounts = mutableMapOf<String, Int>()
        repeat(maximum) {
            var best: GlobalProactiveInboxItem? = null
            var bestTopic = ""
            var least = Int.MAX_VALUE
            for (item in unique) {
                if (item.key in selected) continue
                val summary = item.newsSummary!!
                if (sourceCounts.getOrDefault(summary.source, 0) >= sourceCap) continue
                val topic = summary.topics.minWithOrNull(compareBy<String> { topicCounts.getOrDefault(it, 0) }.thenBy { it })!!
                val count = topicCounts.getOrDefault(topic, 0)
                if (count >= topicCap || count >= least) continue
                best = item; bestTopic = topic; least = count
            }
            val item = best ?: return selected
            selected += item.key
            sourceCounts[item.newsSummary!!.source] = sourceCounts.getOrDefault(item.newsSummary!!.source, 0) + 1
            topicCounts[bestTopic] = topicCounts.getOrDefault(bestTopic, 0) + 1
        }
        return selected
    }

    private fun headlineKey(item: GlobalProactiveInboxItem): String {
        // Retain digits and words: versions, negation and different outcomes must not collapse.
        val title = Normalizer.normalize(item.title, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
            .replace(Regex("[\\p{Z}\\s]+"), " ").trim().trimEnd('.', '!', '?', '\u3002', '\uff01', '\uff1f')
        if (title.length < 16 && title.count { it in '\u3400'..'\u9fff' } < 8) return item.key
        val summary = item.newsSummary!!
        val date = summary.publishedAtMillis.takeIf { it > 0 } ?: summary.collectedAtMillis
        return "${summary.knowledge}:${date / DAY}:$title"
    }
}
