package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthTablePolicyTest {
    private val headers = listOf("date", "systolic", "diastolic", "pulse", "unit", "note")
    private fun mapping() = HealthTablePolicy.suggest(headers, HealthMetric.BLOOD_PRESSURE).copy(zone = "UTC")
    private fun batch(m: HealthTableMapping = mapping()) = HealthTableBatch(UUID.randomUUID().toString(), UUID.randomUUID().toString(),
        "a".repeat(64), "test.csv", "csv", headers = headers, mapping = m)
    private fun row() = HealthTableRow(1, mapOf("date" to "2026-09-01T08:10:00Z", "systolic" to "124.00", "diastolic" to "82", "pulse" to "64", "unit" to "mmHg", "note" to "before breakfast"))
    @Test fun unambiguousAliasesSuggestColumnsButNeverGuessUnits() {
        val m = HealthTablePolicy.suggest(listOf("日期", "高压", "低压", "心率"), HealthMetric.BLOOD_PRESSURE)
        assertEquals("日期", m.timeColumn); assertEquals("高压", m.columns["systolic"])
        assertEquals("低压", m.columns["diastolic"]); assertEquals("心率", m.columns["pulse"])
        assertEquals("", m.unit); assertFalse(m.valid(listOf("日期", "高压", "低压", "心率")))
    }
    @Test fun ambiguousAliasesAreNotSilentlyResolved() {
        val m = HealthTablePolicy.suggest(listOf("Date", "date", "SBP", "systolic", "DBP"), HealthMetric.BLOOD_PRESSURE)
        assertEquals("", m.timeColumn); assertEquals("", m.columns["systolic"])
    }
    @Test fun completeSourceKeepsRawDecimalsAndExplicitTableProvenance() {
        val b = batch(); val draft = requireNotNull(HealthTablePolicy.evaluate(b, row()).draft)
        assertEquals("124.00", draft.values["systolic"])
        assertEquals("bpm", draft.unitFor("pulse")); assertEquals("mmHg", draft.unitFor("systolic"))
        assertEquals("table", draft.evidence?.kind); assertEquals(1L, draft.evidence?.tableRow)
        assertTrue(draft.evidence!!.rawText.contains("124.00")); assertTrue(draft.evidence!!.valid())
        val record = HealthObservationPolicy.observation(draft)
        assertEquals("table", record.source); assertEquals("124", record.draft.values["systolic"])
        assertEquals(draft, HealthDraft.from(draft.json()))
    }
    @Test fun eachRequiredFieldRemainsMissingRatherThanBecomingZero() {
        for (key in listOf("date", "systolic", "diastolic")) {
            val result = HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells - key))
            assertEquals(key, HealthTableRowState.MISSING, result.state); assertNull(result.draft)
        }
    }
    @Test fun optionalPulseRemainsAbsent() {
        val result = HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells - "pulse"))
        assertEquals(HealthTableRowState.VALID, result.state)
        assertFalse(HealthObservationPolicy.normalize(result.draft!!).values.containsKey("pulse"))
    }
    @Test fun formulasRangesComparisonsAndQualitativeResultsAreNotFabricated() {
        for (value in listOf("=100+24", "<120", ">=120", "120-130", "negative", "0", "-1", "NaN", "1e2", "12 mmHg")) {
            val result = HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells + ("systolic" to value)))
            assertEquals(value, HealthTableRowState.INVALID, result.state); assertNull(result.draft)
        }
    }
    @Test fun mixedOriginalUnitsAreValidatedPerRowWithoutConversion() {
        val result = HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells + ("unit" to "kPa")))
        assertEquals("kPa", result.draft?.unit); assertEquals("124.00", result.draft?.values?.get("systolic"))
        assertEquals(HealthTableRowState.INVALID, HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells + ("unit" to "mg/dL"))).state)
        assertEquals(HealthTableRowState.MISSING, HealthTablePolicy.evaluate(batch(), row().copy(cells = row().cells - "unit")).state)
    }
    @Test fun explicitConstantUnitWorksWithoutAUnitColumn() {
        val m = mapping().copy(unitColumn = "", unit = "mmHg")
        assertTrue(m.valid(headers)); assertEquals(HealthTableRowState.VALID, HealthTablePolicy.evaluate(batch(m), row().copy(cells = row().cells - "unit")).state)
    }
    @Test fun completeDatesUseTheSelectedStrictFormat() {
        val m = mapping().copy(date = HealthTableDate.YMD)
        assertNotNull(HealthTablePolicy.measuredAt("2026-09-01 08:10", m))
        for (value in listOf("2026-09-01", "2026-02-30 08:10", "2026-09-01 25:00", "09/01/2026 08:10", "")) assertNull(value, HealthTablePolicy.measuredAt(value, m))
        val dmy = m.copy(date = HealthTableDate.DMY)
        assertEquals(HealthTablePolicy.measuredAt("2026-09-01 08:10", m), HealthTablePolicy.measuredAt("01/09/2026 08:10", dmy))
    }
    @Test fun daylightSavingGapsAndOverlapsNeedExplicitOffsets() {
        val m = mapping().copy(zone = "America/New_York")
        assertNull(HealthTablePolicy.measuredAt("2026-03-08T02:30:00", m))
        assertNull(HealthTablePolicy.measuredAt("2026-11-01T01:30:00", m))
        assertNotNull(HealthTablePolicy.measuredAt("2026-11-01T01:30:00-04:00", m))
        assertNotNull(HealthTablePolicy.measuredAt("2026-11-01T01:30:00-05:00", m))
    }
    @Test fun futureDatesAndInvalidZonesCannotCreateRecords() {
        assertEquals(HealthTableRowState.INVALID, HealthTablePolicy.evaluate(batch(), row(), now = 1L).state)
        assertFalse(mapping().copy(zone = "not/a/zone").valid(headers))
    }
    @Test fun duplicateColumnMappingAndUnknownFieldsAreRejected() {
        assertFalse(mapping().copy(columns = mapOf("systolic" to "systolic", "diastolic" to "systolic")).valid(headers))
        assertFalse(mapping().copy(columns = mapping().columns + ("other" to "note")).valid(headers))
    }
    @Test fun mappingAndBatchRoundTripWithoutLosingTimezoneOrRevision() {
        val b = batch().copy(rows = 1000, cursor = 30, mappingRevision = 5, state = HealthTableState.VALIDATING)
        assertEquals(b, HealthTableBatch.from(b.json()))
    }
    @Test fun unsupportedNestedRowsAreVisibleErrorsEvenWhenNumbersLookValid() {
        assertEquals(HealthTableRowState.INVALID, HealthTablePolicy.evaluate(batch(), row().copy(issue = "nested")).state)
    }
    @Test fun allSupportedMetricsUseTheirOwnFieldsAndUnitSets() {
        for (metric in HealthMetric.entries) {
            val h = listOf("time") + metric.fields
            val m = HealthTablePolicy.suggest(h, metric).copy(unit = metric.units.first(), zone = "UTC")
            val b = batch(m).copy(headers = h)
            val cells = metric.fields.associateWith { "50" } + ("time" to "2026-09-01T08:00:00Z")
            assertEquals(metric.name, HealthTableRowState.VALID, HealthTablePolicy.evaluate(b, HealthTableRow(1, cells)).state)
        }
    }
}
