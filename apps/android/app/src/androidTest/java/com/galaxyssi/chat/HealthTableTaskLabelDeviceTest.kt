package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class HealthTableTaskLabelDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun batch(state: HealthTableState) = HealthTableBatch("unused", "unused", "a".repeat(64), "test.xlsx", "xlsx", rows = 85, cursor = 30, state = state)
    @Test fun completedAndUndoneImportsAreNotStillLabelledAsWaitingForMapping() {
        assertEquals(context.getString(R.string.health_table_import_done), healthTableTaskLabel(context, batch(HealthTableState.SAVED)))
        assertEquals(context.getString(R.string.health_table_import_undone), healthTableTaskLabel(context, batch(HealthTableState.UNDONE)))
    }
    @Test fun allActivePhasesAndTheirActualCheckpointsHaveDifferentLabels() {
        val states = listOf(HealthTableState.SHEET_SELECTION, HealthTableState.READING, HealthTableState.VALIDATING, HealthTableState.SAVING, HealthTableState.UNDOING)
        assertEquals(states.size, states.map { healthTableTaskLabel(context, batch(it)) }.distinct().size)
        assertEquals(context.getString(R.string.health_xlsx_reading, 85L), healthTableTaskLabel(context, batch(HealthTableState.READING)))
        assertEquals(context.getString(R.string.health_table_saving, 30L, 85L), healthTableTaskLabel(context, batch(HealthTableState.SAVING)))
    }
    @Test fun pausedFailuresShowTheirReasonInsteadOfContinuingAProgressLabel() {
        assertEquals(context.getString(R.string.health_xlsx_xml_error), healthTableTaskLabel(context, batch(HealthTableState.READING).copy(error = "xlsx_xml")))
        assertEquals(context.getString(R.string.health_import_memory_pressure), healthTableTaskLabel(context, batch(HealthTableState.SAVING).copy(error = "memory_pressure")))
    }
}
