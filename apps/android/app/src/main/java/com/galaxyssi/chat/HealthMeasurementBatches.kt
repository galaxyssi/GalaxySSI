package com.galaxyssi.chat

import java.math.BigDecimal

internal data class HealthMeasurementBatch(val key: String, val importedAt: Long, val reports: Int, val name: String)
internal data class HealthMeasurementBatchPage(val items: List<HealthMeasurementBatch>, val next: Pair<Long, String>?)
internal data class HealthMeasurementBatchSnapshot(val latest: Map<HealthMetric, HealthObservation>)

/** Import identity, not calendar date, defines a batch. Original-scoped reads include authenticated secondary links. */
internal class HealthMeasurementBatches(private val originals: HealthOriginalStore) {
    private val db get() = originals.libraryDatabase
    fun label(key: String): Pair<Long, String> {
        val (type, id) = parse(key)
        return if (type == "batch") requireNotNull(originals.captureBatch(id)).let { it.createdAt to "" }
        else requireNotNull(originals.job(id)).let { it.createdAt to it.name }
    }
    fun page(before: Pair<Long, String>? = null): HealthMeasurementBatchPage {
        val args = before?.let { arrayOf(it.first.toString(), it.first.toString(), it.second) }
        val having = if (before == null) "" else " HAVING stamp<CAST(? AS INTEGER) OR (stamp=CAST(? AS INTEGER) AND scope<?)"
        val rows = db.rawQuery("SELECT CASE WHEN p.batch_id IS NULL THEN 'job:'||j.id ELSE 'batch:'||p.batch_id END scope," +
            "MAX(j.created_at) stamp,MIN(j.id),COUNT(DISTINCT i.original_id) FROM jobs j JOIN imports i ON i.job_id=j.id " +
            "LEFT JOIN capture_pages p ON p.job_id=j.id GROUP BY scope$having ORDER BY stamp DESC,scope DESC LIMIT 31", args).use { cursor -> buildList {
            while (cursor.moveToNext()) {
                val key = cursor.getString(0)
                val job = requireNotNull(originals.job(cursor.getString(2)))
                check(key == keyFor(job))
                add(HealthMeasurementBatch(key, cursor.getLong(1), cursor.getInt(3), job.name))
            }
        } }
        val visible = rows.take(30)
        return HealthMeasurementBatchPage(visible, if (rows.size > 30) visible.last().let { it.importedAt to it.key } else null)
    }
    fun reports(key: String, after: String = ""): List<String> {
        val (type, id) = parse(key)
        return db.rawQuery(if (type == "batch")
            "SELECT DISTINCT i.original_id FROM imports i JOIN capture_pages p ON p.job_id=i.job_id WHERE p.batch_id=? AND i.original_id>? ORDER BY i.original_id LIMIT 30"
            else "SELECT original_id FROM imports WHERE job_id=? AND original_id>? ORDER BY original_id LIMIT 30", arrayOf(id, after)).use { c -> buildList {
                while (c.moveToNext()) add(c.getString(0).also { check(HealthProfilePolicy.uuid(it)) })
            } }
    }
    fun load(records: HealthRecordStore, key: String, report: String = "", check: () -> Unit = {}): HealthMeasurementBatchSnapshot {
        val versions = records.metricVersions(HealthMetric.entries.toSet())
        val latest = mutableMapOf<HealthMetric, HealthObservation>()
        var after = ""
        var found = report.isEmpty()
        do {
            check()
            val page = reports(key, after)
            for (original in page) {
                if (report.isNotEmpty() && report != original) continue
                found = true
                var cursor: HealthPageCursor? = null
                do {
                    check()
                    val rows = records.originalPage(original, cursor)
                    rows.records.filter { it.profileId == "self" && it.draft.measuredAt <= System.currentTimeMillis() }.forEach { record ->
                        val old = latest[record.draft.metric]
                        if (old == null || compareValuesBy(record, old, { it.draft.measuredAt }, { it.id }) > 0) latest[record.draft.metric] = record
                    }
                    cursor = rows.next
                } while (cursor != null)
            }
            after = page.lastOrNull().orEmpty()
        } while (page.size == 30)
        kotlin.check(found) { "Report no longer belongs to this batch" }
        if (versions != records.metricVersions(HealthMetric.entries.toSet())) throw HealthWeeklyChanged()
        return HealthMeasurementBatchSnapshot(latest)
    }
    companion object {
        fun keyFor(job: HealthImportJob) = if (job.captureBatch.isNotEmpty()) "batch:${job.captureBatch}" else "job:${job.id}"
        fun parse(key: String): Pair<String, String> {
            val parts = key.split(':')
            require(parts.size == 2 && parts[0] in setOf("job", "batch") && HealthProfilePolicy.uuid(parts[1]))
            return parts[0] to parts[1]
        }
        fun delta(a: HealthObservation?, b: HealthObservation?, field: String): BigDecimal? {
            if (a == null || b == null || a.profileId != "self" || b.profileId != "self") return null
            val x = a.draft; val y = b.draft
            if (x.metric != y.metric || x.unit != y.unit || x.condition != y.condition || x.side != y.side ||
                x.condition == "unspecified" || x.unit.isBlank() || a.source != b.source ||
                a.platformOrigin != b.platformOrigin || a.bluetoothGroup != b.bluetoothGroup) return null
            if (x.evidence?.originalId != y.evidence?.originalId) return null
            val av = HealthResult.parse(x.values[field].orEmpty(), x.metric.form)?.exactNumber ?: return null
            val bv = HealthResult.parse(y.values[field].orEmpty(), y.metric.form)?.exactNumber ?: return null
            return bv - av
        }
    }
}
