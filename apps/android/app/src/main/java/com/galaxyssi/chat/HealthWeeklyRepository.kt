package com.galaxyssi.chat

import android.os.CancellationSignal

internal class HealthWeeklyChanged : IllegalStateException("Health report data changed")
internal class HealthWeeklyTooManyRecords : IllegalStateException("Too many records for the report PDF")

internal object HealthWeeklyRepository {
    fun requireCurrent(store: HealthRecordStore, stamp: HealthWeeklyStamp) {
        if (store.metricVersions(stamp.scope.metrics) != stamp.versions) throw HealthWeeklyChanged()
    }

    fun calculate(store: HealthRecordStore, scope: HealthWeeklyScope, previous: HealthWeeklyStamp? = null,
        signal: CancellationSignal? = null): HealthWeeklySnapshot {
        val stamp = previous ?: HealthWeeklyStamp(scope, store.metricVersions(scope.metrics), System.currentTimeMillis())
        require(stamp.scope == scope)
        requireCurrent(store, stamp)
        val accumulators = scope.metrics.associateWith { HealthWeeklyAccumulator(it, scope.first, 7, scope.zone) }
        forEach(store, scope.recordScope(), signal) { accumulators.getValue(it.draft.metric).add(it) }
        val stats = healthWeeklyMetrics.filter { it in scope.metrics }.map { accumulators.getValue(it).finish() }
        val sleep = if (scope.hasBaseline) {
            val baseline = HealthWeeklyAccumulator(HealthMetric.SLEEP_DURATION, scope.baselineFirst, 14, scope.zone)
            forEach(store, scope.baselineScope(), signal, baseline::add)
            HealthWeeklyComparison(stats.single { it.metric == HealthMetric.SLEEP_DURATION }, baseline.finish())
        } else null
        signal?.throwIfCanceled()
        requireCurrent(store, stamp)
        return HealthWeeklySnapshot(scope, stamp.versions, stamp.calculatedAt, stats, sleep)
    }

    fun page(store: HealthRecordStore, stamp: HealthWeeklyStamp, after: HealthPageCursor?, signal: CancellationSignal? = null): HealthWeeklyRecords {
        require(stamp.scope.records)
        requireCurrent(store, stamp)
        val scope = stamp.scope.recordScope()
        val result = store.exportChunk(scope, after, signal)
        val records = result.records.filter(scope::matches).map(HealthWeeklyRecord::from)
        signal?.throwIfCanceled()
        requireCurrent(store, stamp)
        return HealthWeeklyRecords(records, result.next)
    }

    fun rawRecords(store: HealthRecordStore, snapshot: HealthWeeklySnapshot, signal: CancellationSignal?, emit: (HealthWeeklyRecord) -> Unit) {
        require(snapshot.scope.records)
        if (snapshot.recordCount > HealthWeeklyScope.MAX_PDF_RECORDS) throw HealthWeeklyTooManyRecords()
        requireCurrent(store, snapshot.stamp)
        var count = 0L
        forEach(store, snapshot.scope.recordScope(), signal) {
            if (++count > snapshot.recordCount) throw HealthWeeklyChanged()
            emit(HealthWeeklyRecord.from(it))
        }
        if (count != snapshot.recordCount) throw HealthWeeklyChanged()
        requireCurrent(store, snapshot.stamp)
    }

    private fun forEach(store: HealthRecordStore, scope: HealthRecordExportScope, signal: CancellationSignal?, consumer: (HealthObservation) -> Unit) {
        var cursor: HealthPageCursor? = null
        do {
            signal?.throwIfCanceled()
            val page = store.exportChunk(scope, cursor, signal)
            for (record in page.records) { signal?.throwIfCanceled(); if (scope.matches(record)) consumer(record) }
            cursor = page.next
        } while (cursor != null)
    }
}
