package com.galaxyssi.chat

internal class HealthTrendChangedException : IllegalStateException("Health records changed during this calculation")

internal object HealthTrendRepository {
    fun load(store: HealthRecordStore, spec: HealthTrendSpec, cancelled: () -> Unit = {}, progress: (Long) -> Unit = {},
             signal: android.os.CancellationSignal? = null): HealthTrendSummary {
        val version = store.metricVersion(spec.metric)
        val builder = HealthTrendBuilder(spec); var cursor: HealthPageCursor? = null; var scanned = 0L
        do {
            cancelled(); val page = store.trendChunk(spec, cursor, signal)
            page.records.forEach { cancelled(); builder.add(it); scanned++ }
            if (scanned == page.records.size.toLong() || scanned % 300L == 0L) progress(scanned)
            cursor = page.next
        } while (cursor != null)
        cancelled()
        if (store.metricVersion(spec.metric) != version) throw HealthTrendChangedException()
        return builder.finish().copy(version = version)
    }
}
