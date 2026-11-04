package com.galaxyssi.chat

import android.content.Context
import android.content.Intent

internal data class HealthReportReviewDisposition(val resumeAt: Long = 0, val handledAt: Long = 0)
internal data class HealthReportReviewCursor(val createdAt: Long, val id: String)
internal data class HealthReportReview(
    val id: String, val name: String, val kind: HealthOverviewReviewKind, val createdAt: Long,
    val disposition: HealthReportReviewDisposition, val finished: Boolean
) {
    fun state(now: Long) = when {
        finished || disposition.handledAt > 0 -> HealthReminderState.COMPLETE
        disposition.resumeAt > now -> HealthReminderState.SNOOZED
        else -> HealthReminderState.PENDING
    }
}
internal data class HealthReportReviewPage(val rows: List<HealthReportReview>, val next: HealthReportReviewCursor?)

internal fun HealthReportReview.intent(context: Context, fixture: String? = null): Intent = when (kind) {
    HealthOverviewReviewKind.OCR -> Intent(context, HealthCaptureActivity::class.java).putExtra("health_job", id)
        .putExtra("health_review_test_id", fixture)
    HealthOverviewReviewKind.TABLE -> Intent(context, HealthTableActivity::class.java).putExtra("health_table", id)
}

internal class HealthReportReviewRepository(private val context: Context, private val names: HealthOverviewDatabases) {
    fun page(store: HealthReminderStore, filter: HealthReminderFilter, before: HealthReportReviewCursor?, now: Long): HealthReportReviewPage {
        if (!context.getDatabasePath(names.originals).exists() && !context.getDatabasePath(names.records).exists()) {
            return HealthReportReviewPage(emptyList(), null)
        }
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            HealthTableStore(context, names.records).use { tables ->
                val visible = ArrayList<HealthReportReview>(PAGE)
                var cursor = before
                // Bound decryption work even if a filtered page has many handled imports.
                repeat(4) {
                    val jobs = originals.reviewJobs(cursor)
                    for (job in jobs) {
                        val item = review(job, originals, tables, store)
                        if (item != null && matches(item.state(now), filter)) {
                            if (visible.size == PAGE) return HealthReportReviewPage(visible, cursor)
                            visible += item
                        }
                        cursor = HealthReportReviewCursor(job.createdAt, job.id)
                    }
                    if (jobs.size < 30) return HealthReportReviewPage(visible, null)
                }
                return HealthReportReviewPage(visible, cursor)
            }
        }
    }

    fun act(store: HealthReminderStore, expected: HealthReportReview, action: HealthReminderAction, now: Long) {
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            HealthTableStore(context, names.records).use { tables ->
                val current = originals.job(expected.id)?.let { review(it, originals, tables, store) }
                if (current == null || current != expected || current.state(now) == HealthReminderState.COMPLETE) throw HealthReminderConflict()
                store.actReport(expected.id, expected.disposition, action, now)
            }
        }
    }

    fun byId(store: HealthReminderStore, ids: Set<String>): Map<String, HealthReportReview> {
        if (ids.isEmpty() || !context.getDatabasePath(names.originals).exists() && !context.getDatabasePath(names.records).exists()) return emptyMap()
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            HealthTableStore(context, names.records).use { tables ->
                return ids.mapNotNull { id -> originals.job(id)?.let { review(it, originals, tables, store) } }.associateBy { it.id }
            }
        }
    }

    private fun review(job: HealthImportJob, originals: HealthOriginalStore, tables: HealthTableStore,
        store: HealthReminderStore): HealthReportReview? {
        val original = originals.originalForJob(job.id)?.takeIf { it.id == job.originalId } ?: return null
        val disposition = store.reportDisposition(job.id)
        return when (job.state) {
            HealthImportState.REVIEW -> if (job.nextPage > 0) HealthReportReview(job.id, original.name,
                HealthOverviewReviewKind.OCR, job.createdAt, disposition, false) else null
            HealthImportState.TABLE_REVIEW -> {
                val table = tables.batch(job.id)?.takeIf { it.originalId == original.id } ?: return null
                when (table.state) {
                    HealthTableState.SHEET_SELECTION, HealthTableState.MAPPING, HealthTableState.READY ->
                        HealthReportReview(job.id, original.name, HealthOverviewReviewKind.TABLE, job.createdAt, disposition, false)
                    HealthTableState.SAVED, HealthTableState.UNDONE -> HealthReportReview(job.id, original.name, HealthOverviewReviewKind.TABLE,
                        job.createdAt, disposition, true)
                    else -> null
                }
            }
            else -> null
        }
    }

    private fun matches(state: HealthReminderState, filter: HealthReminderFilter) = when (filter) {
        HealthReminderFilter.ALL -> true
        HealthReminderFilter.HANDLED -> state == HealthReminderState.COMPLETE
        HealthReminderFilter.PENDING -> state != HealthReminderState.COMPLETE
    }

    private companion object { const val PAGE = 30 }
}
