package com.galaxyssi.chat

import android.content.Context

internal fun healthTableTaskLabel(context: Context, batch: HealthTableBatch): String {
    if (batch.error.isNotBlank()) return context.getString(healthXlsxErrorResource(batch.error))
    return with(context) { when (batch.state) {
        HealthTableState.READING -> if (batch.format == "xlsx") getString(R.string.health_xlsx_reading, batch.rows) else getString(R.string.health_import_preparing)
        HealthTableState.SHEET_SELECTION -> getString(R.string.health_xlsx_choose_sheet)
        HealthTableState.MAPPING -> getString(R.string.health_table_queue_ready)
        HealthTableState.VALIDATING -> getString(R.string.health_table_validating, batch.cursor, batch.rows)
        HealthTableState.READY -> getString(R.string.health_table_title)
        HealthTableState.SAVING -> getString(R.string.health_table_saving, batch.cursor, batch.rows)
        HealthTableState.SAVED -> getString(R.string.health_table_import_done)
        HealthTableState.UNDOING -> getString(R.string.health_table_undoing, batch.cursor, batch.rows)
        HealthTableState.UNDONE -> getString(R.string.health_table_import_undone)
        HealthTableState.FAILED -> getString(R.string.health_table_resume_error)
    } }
}
