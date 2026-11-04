package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal
import java.math.BigDecimal
import java.math.RoundingMode
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthAnalysisFocus { CHANGES, COVERAGE, NEXT_RECORDS }
internal enum class HealthAnalysisAction { ADD_RECORD, RECORD_REMINDER, WEEKLY_REPORT }
internal data class HealthAnalysisReference(val id: String, val revision: Int, val time: Long, val source: String, val baseline: Boolean)
internal data class HealthAnalysisFact(val key: String, val stat: HealthWeeklyStat, val refs: List<HealthAnalysisReference>)
internal data class HealthAnalysisPreview(val weekly: HealthWeeklySnapshot, val facts: List<HealthAnalysisFact>,
    val focus: HealthAnalysisFocus, val policyVersion: String) {
    val hasData get() = facts.any { it.stat.validDays > 0 }
}
internal data class HealthAnalysisPlan(val factKeys: List<String>, val actions: List<HealthAnalysisAction>)
internal class HealthAnalysisInvalidReply : IllegalStateException()
internal class HealthAnalysisNoModel : IllegalStateException()

internal object HealthAnalysis {
    fun prepare(context: Context, names: HealthOverviewDatabases, scope: HealthWeeklyScope,
        focus: HealthAnalysisFocus, signal: CancellationSignal? = null): HealthAnalysisPreview =
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.track(HealthAccessScope.analysis(scope)) {
                val version = privacy.policy().version
                HealthRecordStore(context, names.records).use { store ->
                    val weekly = HealthWeeklyRepository.calculate(store, scope, signal = signal)
                    val facts = weekly.stats.mapIndexed { index, stat ->
                        val recent = latestReference(store, scope.recordScope().copy(metrics = setOf(stat.metric)), false, signal)
                        val baseline = if (stat.metric == HealthMetric.SLEEP_DURATION && scope.hasBaseline)
                            latestReference(store, scope.baselineScope(), true, signal) else null
                        HealthAnalysisFact("f${index + 1}", stat, listOfNotNull(recent, baseline))
                    }
                    HealthWeeklyRepository.requireCurrent(store, weekly.stamp)
                    HealthAnalysisPreview(weekly, facts, focus, version)
                }
            }
        }

    private fun latestReference(store: HealthRecordStore, scope: HealthRecordExportScope,
        baseline: Boolean, signal: CancellationSignal?): HealthAnalysisReference? {
        var cursor: HealthPageCursor? = null
        var counted: HealthAnalysisReference? = null
        do {
            signal?.throwIfCanceled()
            val page = store.exportChunk(scope, cursor, signal)
            for (row in page.records) {
                if (!scope.matches(row)) continue
                val reference = HealthAnalysisReference(row.id, row.revision, row.draft.measuredAt, row.source, baseline)
                if (counted == null) counted = reference
                if (row.draft.metric.requiredFields.all { field ->
                    HealthResult.parse(row.draft.values[field].orEmpty(), row.draft.metric.form)?.exactNumber != null
                }) return reference
            }
            cursor = page.next
        } while (cursor != null)
        return counted
    }

    fun requireCurrent(context: Context, names: HealthOverviewDatabases, preview: HealthAnalysisPreview, online: Boolean) {
        val policy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        if (!policy.metrics || (online && !policy.online)) throw HealthAccessBlocked()
        if (policy.version != preview.policyVersion) throw HealthWeeklyChanged()
        HealthRecordStore(context, names.records).use { HealthWeeklyRepository.requireCurrent(it, preview.weekly.stamp) }
    }

    fun payload(preview: HealthAnalysisPreview): JSONObject {
        val facts = JSONArray()
        preview.facts.forEach { fact ->
            val stat = fact.stat
            val row = JSONObject().put("id", fact.key).put("metric", stat.metric.name)
                .put("valid_days", stat.validDays).put("recorded_days", stat.recordedDays)
            if (preview.focus == HealthAnalysisFocus.CHANGES) {
                stat.mean?.let {
                    row.put("mean", decimal(it)).put("unit", if (stat.metric == HealthMetric.SLEEP_DURATION) "min" else stat.metric.units.first())
                }
                if (stat.metric == HealthMetric.BLOOD_PRESSURE) row.put("exact_record_count", stat.exactRecords)
            }
            if (stat.metric == HealthMetric.SLEEP_DURATION) preview.weekly.sleep?.let { sleep ->
                row.put("baseline_valid_days", sleep.baseline.validDays)
                if (preview.focus == HealthAnalysisFocus.CHANGES) sleep.deltaMinutes?.let { delta ->
                    row.put("baseline_mean_min", decimal(requireNotNull(sleep.baseline.mean)))
                    row.put("delta_min", decimal(delta))
                }
            }
            facts.put(row)
        }
        return JSONObject().put("focus", preview.focus.name).put("recent_days", 7)
            .put("baseline_days", if (preview.weekly.scope.hasBaseline) 14 else 0)
            .put("facts", facts).put("allowed_actions", JSONArray(HealthAnalysisAction.entries.map { it.name }))
    }

    fun decodeReply(raw: String, preview: HealthAnalysisPreview): HealthAnalysisPlan {
        if (raw.length > 4096) throw HealthAnalysisInvalidReply()
        try {
            val text = raw.trim().let { value ->
                if (value.startsWith("```json\n") && value.endsWith("```")) value.removePrefix("```json\n").dropLast(3).trim() else value
            }
            val reader = org.json.JSONTokener(text)
            val root = reader.nextValue() as? JSONObject ?: throw HealthAnalysisInvalidReply()
            check(reader.nextClean() == '\u0000' && root.keys().asSequence().toSet() == setOf("fact_ids", "actions"))
            fun strings(key: String, max: Int): List<String> {
                val array = root.getJSONArray(key)
                check(array.length() in 1..max)
                return (0 until array.length()).map { array.get(it) as String }.also { check(it.toSet().size == it.size) }
            }
            val keys = strings("fact_ids", 3)
            check(keys.all { key -> preview.facts.any { it.key == key } })
            return HealthAnalysisPlan(keys, strings("actions", 2).map(HealthAnalysisAction::valueOf))
        } catch (_: Exception) { throw HealthAnalysisInvalidReply() }
    }

    suspend fun explain(context: Context, names: HealthOverviewDatabases, preview: HealthAnalysisPreview, destination: String,
        exchange: suspend (JSONObject, () -> Unit) -> String): HealthAnalysisPlan {
        require(preview.hasData)
        val job = currentCoroutineContext()
        val scope = HealthAccessScope.analysis(preview.weekly.scope, destination)
        return HealthPrivacyStore(context, names.privacy).use { privacy ->
            privacy.trackOnlineAnalysis(scope, preview.policyVersion) {
                val guard = {
                    job.ensureActive()
                    requireCurrent(context, names, preview, online = true)
                }
                guard()
                val raw = exchange(payload(preview), guard)
                guard()
                decodeReply(raw, preview)
            }
        }
    }

    private fun decimal(value: BigDecimal) = value.setScale(1, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
}
