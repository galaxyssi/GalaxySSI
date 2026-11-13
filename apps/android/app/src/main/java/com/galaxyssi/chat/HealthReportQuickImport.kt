package com.galaxyssi.chat

import android.content.Context
import java.time.LocalDate
import java.time.ZoneId

internal data class HealthReportSupplement(val measuredAt: Long = 0, val fasting: String = "") {
    init { require(measuredAt >= 0 && fasting in setOf("", "fasting", "non_fasting", "unspecified")) }
}

internal data class HealthReportImportPlan(
    val drafts: List<HealthDraft>, val collectedDate: String = "", val partial: Boolean = false
) {
    val needsDate get() = drafts.any { it.measuredAt <= 0 }
    val needsFasting get() = drafts.any { it.metric == HealthMetric.GLUCOSE && it.condition == "unspecified" }
    val needsSupplement get() = needsDate || needsFasting

    fun fill(supplement: HealthReportSupplement): List<HealthDraft> = drafts.map { draft ->
        draft.copy(measuredAt = draft.measuredAt.takeIf { it > 0 } ?: supplement.measuredAt,
            condition = if (draft.metric == HealthMetric.GLUCOSE && draft.condition == "unspecified")
                supplement.fasting.ifEmpty { "unspecified" } else draft.condition)
    }
}

internal data class HealthReportImportOutcome(val saved: Int, val duplicates: Int, val pending: Int, val partial: Boolean)

internal class HealthReportQuickImport(private val context: Context, private val names: HealthOverviewDatabases) {
    private fun originals() = HealthOriginalStore(context, names.originals, names.originalRoot(context))

    private fun plan(job: HealthImportJob, source: HealthOriginal, result: HealthReportVisionResult,
        records: HealthRecordStore): HealthReportImportPlan {
        val zone = ZoneId.systemDefault()
        val drafts = result.drafts(job, source, zone, System.currentTimeMillis()).mapNotNull { suggestion ->
            if (records.recordForEvidence(suggestion) != null || records.recordForOcrLink(suggestion) != null) null
            else records.draft(HealthRecordStore.draftKey(suggestion)) ?: suggestion
        }
        val date = runCatching { LocalDate.parse(result.collected).toString() }.getOrDefault("")
        return HealthReportImportPlan(drafts, date, result.partial)
    }

    fun prepare(id: String): HealthReportImportPlan = originals().use { store ->
        store.withReportVision(id) { job, source, result ->
            HealthRecordStore(context, names.records).use { plan(job, source, result, it) }
        }
    }

    fun save(id: String, expected: HealthReportImportPlan, supplement: HealthReportSupplement,
        checkActive: () -> Unit): HealthReportImportOutcome {
        check(!expected.needsDate || supplement.measuredAt > 0)
        check(!expected.needsFasting || supplement.fasting.isNotBlank())
        return originals().use { store ->
            val outcome = store.withReportVision(id) { job, source, result ->
                HealthRecordStore(context, names.records).use { records ->
                    if (plan(job, source, result, records) != expected) throw HealthReportVisionChanged()
                    records.saveVisionReport(expected.fill(supplement), expected.partial, checkActive)
                }
            }
            if (expected.drafts.isNotEmpty() && outcome.pending == 0 && !outcome.partial)
                runCatching { store.releaseReviewOriginal(id) }
            outcome
        }
    }
}
