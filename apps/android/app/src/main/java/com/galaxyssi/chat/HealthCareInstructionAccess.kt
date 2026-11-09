package com.galaxyssi.chat

import android.content.Context

internal object HealthCareInstructionAccess {
    fun available(context: Context, names: HealthOverviewDatabases, ref: HealthCareInstructionActionRef): Boolean {
        if (ref.invalidated) return false
        return HealthExportShare.openOriginals(context, names.fixture).use { originals ->
            originals.original(ref.original.originalId)?.let { ref.original.matches(it) && originals.present(it) } == true
        }
    }
    fun current(context: Context, names: HealthOverviewDatabases, store: HealthCareStore,
        issue: HealthCareConcern, action: HealthCareAction): Boolean = store.instructionCurrent(issue, action) &&
        store.visitReviewCurrent(issue, action) &&
        (action.instruction?.let { available(context, names, it) } ?: true)
}
