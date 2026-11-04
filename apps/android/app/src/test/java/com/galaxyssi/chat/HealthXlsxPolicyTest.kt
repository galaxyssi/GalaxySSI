package com.galaxyssi.chat

import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthXlsxPolicyTest {
    private val headers = listOf("time", "systolic", "diastolic", "unit", "note")
    private fun batch() = HealthTableBatch(UUID.randomUUID().toString(), UUID.randomUUID().toString(), "a".repeat(64), "test.xlsx", "xlsx",
        headers = headers, mapping = HealthTablePolicy.suggest(headers, HealthMetric.BLOOD_PRESSURE).copy(zone = "UTC"),
        sheets = listOf(HealthXlsxSheet(0, "Home", "VISIBLE"), HealthXlsxSheet(1, "Lab", "HIDDEN")), sheetIndex = 1)
    private fun row() = HealthTableRow(1, mapOf("time" to "2026-09-01T12:00:00Z", "systolic" to "124", "diastolic" to "82", "unit" to "mmHg"),
        sourceRow = 42, addresses = mapOf("time" to "A42", "systolic" to "B42"))
    @Test fun physicalWorksheetAndRowAreNotReplacedByPreviewOrdinals() {
        val draft = HealthTablePolicy.evaluate(batch(), row()).draft!!
        assertEquals(42L, draft.evidence?.tableRow); assertEquals(2, draft.evidence?.page)
        assertEquals("Lab", draft.evidence?.tableSheet); assertEquals("table-row-42", draft.evidence?.candidateId)
        assertTrue(draft.evidence!!.rawText.contains("Sheet: Lab"))
        assertEquals(draft, HealthDraft.from(draft.json()))
    }
    @Test fun formulaResultsAreBlockedUntilExplicitlyAllowed() {
        val source = row().copy(formulas = mapOf("systolic" to "100+24"))
        assertEquals("formula_ack", HealthTablePolicy.evaluate(batch(), source).issue)
        val confirmed = batch().let { it.copy(mapping = it.mapping.copy(allowFormulaCache = true)) }
        val draft = HealthTablePolicy.evaluate(confirmed, source).draft!!
        assertEquals("124", draft.values["systolic"])
        assertTrue(draft.evidence!!.rawText.contains("=100+24")); assertTrue(draft.evidence!!.rawText.contains("not recalculated"))
    }
    @Test fun absentFormulaCacheDoesNotBecomeZeroEvenWhenAllowed() {
        val batch = batch().let { it.copy(mapping = it.mapping.copy(allowFormulaCache = true)) }
        val source = row().copy(cells = row().cells - "systolic", formulas = mapOf("systolic" to "100+24"))
        val result = HealthTablePolicy.evaluate(batch, source)
        assertNull(result.draft); assertEquals(HealthTableRowState.MISSING, result.state); assertEquals("formula_cache", result.issue)
    }
    @Test fun unmappedFormulasDoNotBlockIndependentMeasurementFields() {
        val source = row().copy(formulas = mapOf("other" to "NOW()"))
        assertEquals(HealthTableRowState.VALID, HealthTablePolicy.evaluate(batch(), source).state)
    }
    @Test fun mappedNotesAndUnitsAlsoRequireFormulaConsent() {
        for (key in listOf("note", "unit", "time")) assertEquals(key, "formula_ack", HealthTablePolicy.evaluate(batch(), row().copy(formulas = mapOf(key to "A1"))).issue)
    }
    @Test fun selectedSpreadsheetErrorCannotBeSavedButUnmappedErrorsAreRetained() {
        assertEquals("excel_error", HealthTablePolicy.evaluate(batch(), row().copy(errors = setOf("systolic"))).issue)
        assertEquals(HealthTableRowState.VALID, HealthTablePolicy.evaluate(batch(), row().copy(errors = setOf("unused"))).state)
    }
    @Test fun numericCellNormalizationPreservesTheOriginalNotationInEvidence() {
        val source = row().copy(cells = row().cells + ("systolic" to "1.24E2"), numbers = mapOf("systolic" to "124"))
        val draft = HealthTablePolicy.evaluate(batch(), source).draft!!
        assertEquals("124", draft.values["systolic"]); assertTrue(draft.evidence!!.rawText.contains("1.24E2"))
    }
    @Test fun excelDatesRequireChoosingExcelFormatRatherThanGuessing() {
        val source = row().copy(cells = row().cells + ("time" to "46266.5"), excelDates = mapOf("time" to "2026-09-01T12:00"))
        assertEquals("time", HealthTablePolicy.evaluate(batch(), source).issue)
        val b = batch().let { it.copy(mapping = it.mapping.copy(date = HealthTableDate.EXCEL)) }
        assertEquals(Instant.parse("2026-09-01T12:00:00Z").toEpochMilli(), HealthTablePolicy.evaluate(b, source).draft!!.measuredAt)
    }
    @Test fun wholeDaySerialRequiresAUserChosenTimeAndKeepsThatDecisionInEvidence() {
        val source = row().copy(cells = row().cells + ("time" to "46266"), excelDates = mapOf("time" to "2026-09-01T00:00"))
        val b = batch().let { it.copy(mapping = it.mapping.copy(date = HealthTableDate.EXCEL)) }
        assertEquals("time", HealthTablePolicy.evaluate(b, source).issue)
        val draft = HealthTablePolicy.evaluate(b.copy(mapping = b.mapping.copy(dateOnlyTime = "08:15")), source).draft!!
        assertEquals(Instant.parse("2026-09-01T08:15:00Z").toEpochMilli(), draft.measuredAt)
        assertTrue(draft.evidence!!.rawText.contains("Confirmed date-only time: 08:15"))
    }
    @Test fun invalidWholeDayTimesCannotFabricateMidnight() {
        val source = row().copy(cells = row().cells + ("time" to "46266"), excelDates = mapOf("time" to "2026-09-01T00:00"))
        val b = batch()
        for (time in listOf("", "8:00", "24:00", "12:60", "00:00Z")) assertNull(time,
            HealthTablePolicy.evaluate(b.copy(mapping = b.mapping.copy(date = HealthTableDate.EXCEL, dateOnlyTime = time)), source).draft)
    }
    @Test fun explicitMidnightIsAllowedAndTimezoneStillApplies() {
        val source = row().copy(cells = row().cells + ("time" to "46266"), excelDates = mapOf("time" to "2026-09-01T00:00"))
        val b = batch().let { it.copy(mapping = it.mapping.copy(date = HealthTableDate.EXCEL, dateOnlyTime = "00:00", zone = "Asia/Shanghai")) }
        assertEquals(Instant.parse("2026-08-31T16:00:00Z").toEpochMilli(), HealthTablePolicy.evaluate(b, source).draft!!.measuredAt)
    }
    @Test fun date1904ProvenanceSurvivesSerialization() {
        val b = batch().copy(date1904 = true, headerRow = 5, mappingRevision = 7)
        assertEquals(b, HealthTableBatch.from(b.json()))
        val record = HealthTablePolicy.evaluate(b, row()).draft!!
        assertTrue(record.evidence!!.rawText.contains("Excel epoch: 1904"))
    }
    @Test fun sourceCellMetadataRoundTripsIndependentlyFromNormalizedValues() {
        val source = row().copy(formulas = mapOf("systolic" to "100+24"), numbers = mapOf("systolic" to "124"),
            excelDates = mapOf("time" to "2026-09-01T12:00"), errors = setOf("unused"))
        assertEquals(source, HealthTableRow.from(source.json()))
    }
    @Test fun legacyCsvJsonRowsAndBatchesRetainTheirOriginalDefaults() {
        val j = row().json(); listOf("source_row", "formulas", "numbers", "excel_dates", "errors", "addresses").forEach(j::remove)
        assertEquals(1L, HealthTableRow.from(j).sourceRow); assertTrue(HealthTableRow.from(j).formulas.isEmpty())
        val b = batch().json(); listOf("sheets", "sheet_index", "header_row", "date_1904").forEach(b::remove)
        assertEquals(-1, HealthTableBatch.from(b).sheetIndex); assertTrue(HealthTableBatch.from(b).sheets.isEmpty())
    }
    @Test fun spreadsheetDateInterpretationCannotLeakIntoCsvOrJson() {
        val b = batch().let { it.copy(format = "csv", mapping = it.mapping.copy(date = HealthTableDate.EXCEL)) }
        val source = row().copy(cells = row().cells + ("time" to "46266.5"), excelDates = mapOf("time" to "2026-09-01T12:00"))
        assertNull(HealthTablePolicy.evaluate(b, source).draft)
    }
    @Test fun activePhasesDoNotRequireRepeatedFullPreviewCountsWhileCheckpointsAdvance() {
        assertTrue(HealthTableState.READING.working); assertTrue(HealthTableState.VALIDATING.working)
        assertTrue(HealthTableState.SAVING.working); assertTrue(HealthTableState.UNDOING.working)
        assertFalse(HealthTableState.MAPPING.working); assertFalse(HealthTableState.READY.working)
        assertFalse(HealthTableState.SAVED.working); assertFalse(HealthTableState.UNDONE.working)
    }
}
