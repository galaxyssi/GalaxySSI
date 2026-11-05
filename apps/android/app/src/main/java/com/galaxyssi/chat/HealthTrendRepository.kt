package com.galaxyssi.chat

internal class HealthTrendChangedException : IllegalStateException("Health records changed during this calculation")

internal object HealthTrendRepository {
    fun load(store: HealthRecordStore, spec: HealthTrendSpec, cancelled: () -> Unit = {}, progress: (Long) -> Unit = {},
             signal: android.os.CancellationSignal? = null): HealthTrendSummary =
        calculate(store, spec, spec.bucketDays, cancelled, progress, signal)

    fun point(store: HealthRecordStore, spec: HealthTrendSpec, field: String, expectedVersion: String,
              cancelled: () -> Unit = {}, signal: android.os.CancellationSignal? = null): HealthTrendPoint {
        require(field in spec.metric.requiredFields)
        if (store.metricVersion(spec.metric) != expectedVersion) throw HealthTrendChangedException()
        val summary = calculate(store, spec, spec.days.toInt(), cancelled, {}, signal)
        if (summary.version != expectedVersion) throw HealthTrendChangedException()
        return summary.points.singleOrNull { it.field == field } ?: throw HealthTrendChangedException()
    }

    private fun calculate(store: HealthRecordStore, spec: HealthTrendSpec, bucketDays: Int,
                          cancelled: () -> Unit, progress: (Long) -> Unit,
                          signal: android.os.CancellationSignal?): HealthTrendSummary {
        val version = store.metricVersion(spec.metric)
        val builder = HealthTrendBuilder(spec, bucketDays); var cursor: HealthPageCursor? = null; var scanned = 0L
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
