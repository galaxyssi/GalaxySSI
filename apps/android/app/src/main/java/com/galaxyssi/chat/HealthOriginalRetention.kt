package com.galaxyssi.chat

import android.content.Context

internal object HealthOriginalRetention {
    fun releaseAfterReview(originals: HealthOriginalStore, records: HealthRecordStore, id: String) {
        val job = originals.job(id)
        if (job?.modelRecognized != true || reportComplete(originals, records, job)) originals.releaseReviewOriginal(id)
    }

    private fun reportComplete(originals: HealthOriginalStore, records: HealthRecordStore, job: HealthImportJob): Boolean {
        val result = originals.page(job.id, 1)?.vision?.takeUnless { it.partial } ?: return false
        val source = originals.original(job.originalId) ?: return false
        return result.drafts(job, source, java.time.ZoneId.systemDefault(), System.currentTimeMillis()).all {
            records.recordForEvidence(it) != null || records.recordForOcrLink(it) != null
        }
    }

    fun recover(context: Context, databases: HealthOverviewDatabases = HealthOverviewDatabases()) {
        HealthOriginalStore(context, databases.originals, databases.originalRoot(context)).use { originals ->
            HealthRecordStore(context, databases.records).use { records ->
                HealthTableStore(context, databases.records).use { tables ->
                    var after = ""
                    while (true) {
                        val ids = originals.reviewOriginalIds(after)
                        if (ids.isEmpty()) break
                        for (id in ids) {
                            val job = originals.job(id)
                            val state = job?.state
                            val readyReport = job?.state == HealthImportState.REVIEW && records.overviewHasOriginalHistory(id) &&
                                (!job.modelRecognized || reportComplete(originals, records, job))
                            if (state == null || state == HealthImportState.CANCELLED || state == HealthImportState.ORIGINAL_ONLY ||
                                readyReport ||
                                tables.batch(id)?.state in setOf(HealthTableState.SAVED, HealthTableState.UNDOING, HealthTableState.UNDONE)
                            ) originals.releaseReviewOriginal(id)
                        }
                        after = ids.last()
                    }
                }
            }
        }
    }
}
