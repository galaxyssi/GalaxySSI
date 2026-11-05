package com.galaxyssi.chat

import android.os.CancellationSignal
import java.text.Normalizer
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

internal class HealthOriginalLibrarySearch(query: String, private val zone: ZoneId) {
    private val text = normalize(query.trim())
    private val terms = words(text)
    private val dateRange = dateRange(text)
    private val metrics = if (dateRange == null && terms.isNotEmpty()) HealthMetric.entries.filterTo(linkedSetOf()) { metric ->
        val keys = (HealthMetricCatalog.aliases(metric) + metric.name).map { words(normalize(it)).joinToString("") }
        val combined = terms.joinToString("")
        keys.any { key -> key == combined || combined.length >= 3 && key.contains(combined) }
    } else emptySet()

    fun matches(original: HealthOriginal, records: HealthRecordStore, signal: CancellationSignal): Boolean {
        signal.throwIfCanceled()
        val name = normalize(original.name)
        val nameTerms = words(name)
        if (name.contains(text) || dateRange == null && terms.isNotEmpty() && terms.all { term -> nameTerms.any { it.contains(term) } }) return true
        if (dateRange != null && original.importedAt in dateRange.first until dateRange.second) return true
        if (metrics.isEmpty() && dateRange == null) return false
        val scope = HealthRecordExportScope(
            metrics = metrics.ifEmpty { HealthMetric.entries.toSet() },
            from = dateRange?.first ?: 0L, until = dateRange?.second ?: Long.MAX_VALUE, zone = zone.id, originalId = original.id,
        )
        var after: HealthPageCursor? = null
        do {
            signal.throwIfCanceled()
            val page = records.originalPage(original.id, after, scope, signal, pageSize = 1)
            if (page.records.any { scope.matches(it) && it.draft.evidence?.sha256 == original.sha256 }) return true
            after = page.next
        } while (after != null)
        return false
    }

    private fun dateRange(value: String): Pair<Long, Long>? {
        val parts = DATE.matchEntire(value)?.groupValues ?: return null
        return runCatching {
            val first = LocalDate.of(parts[1].toInt(), parts[2].toInt(), parts[3].ifEmpty { "1" }.toInt())
            require(first.year in 1970..9998)
            val end = if (parts[3].isEmpty()) first.plusMonths(1) else first.plusDays(1)
            val from = first.atStartOfDay(zone).toInstant().toEpochMilli().coerceAtLeast(0)
            val until = end.atStartOfDay(zone).toInstant().toEpochMilli()
            require(until > from)
            from to until
        }.getOrNull()
    }

    companion object {
        private val DATE = Regex("""(\d{4})[-./\u5e74](\d{1,2})(?:[-./\u6708](\d{1,2})\u65e5?|\u6708)?""")
        private val WORD = Regex("""[\p{L}\p{N}]+""")
        private fun normalize(value: String) = Normalizer.normalize(value, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
        private fun words(value: String) = WORD.findAll(value).map { it.value }.toList()
    }
}
