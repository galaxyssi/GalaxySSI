package com.galaxyssi.chat

import android.content.Context

internal object HealthOriginalRetention {
    fun recover(context: Context, databases: HealthOverviewDatabases = HealthOverviewDatabases()) {
        HealthOriginalStore(context, databases.originals, databases.originalRoot(context)).use { originals ->
            HealthRecordStore(context, databases.records).use { records ->
                HealthTableStore(context, databases.records).use { tables ->
                    var after = ""
                    while (true) {
                        val ids = originals.reviewOriginalIds(after)
                        if (ids.isEmpty()) break
                        for (id in ids) {
                            val state = originals.job(id)?.state
                            if (state == null || state == HealthImportState.CANCELLED || state == HealthImportState.ORIGINAL_ONLY ||
                                (state == HealthImportState.REVIEW && records.overviewHasOriginalHistory(id)) ||
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
