package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthMetricCatalogTest {
    @Test fun everySupportedMetricHasOneCatalogEntryAndEveryCategoryIsRepresented() {
        assertEquals(HealthMetric.entries.toSet(), HealthMetricCatalog.entries.map { it.metric }.toSet())
        assertEquals(HealthMetric.entries.size, HealthMetricCatalog.entries.size)
        assertEquals(HealthMetricGroup.entries.toSet(), HealthMetricCatalog.entries.map { it.group }.toSet())
    }
    @Test fun originalPersistentMetricIdentifiersAndOrdinalsRemainUnchanged() {
        assertEquals(listOf("BLOOD_PRESSURE", "GLUCOSE", "WEIGHT", "HEART_RATE", "CHOLESTEROL", "HEMOGLOBIN"), HealthMetric.entries.take(6).map { it.name })
    }
    @Test fun chineseEnglishAbbreviationsAndUnitsAreSearchable() {
        for ((query, metric) in mapOf("\u8840\u538b" to HealthMetric.BLOOD_PRESSURE, "HbA1c" to HealthMetric.HBA1C, "LDL-C" to HealthMetric.LDL,
            "\u808c\u9150" to HealthMetric.CREATININE, "sleep duration" to HealthMetric.SLEEP_DURATION, "\uff34\uff33\uff28" to HealthMetric.TSH)) {
            assertTrue(query, HealthMetricCatalog.search(query).any { it.metric == metric })
        }
        assertTrue(HealthMetricCatalog.search("mg/dL").any { it.metric == HealthMetric.GLUCOSE })
    }
    @Test fun categoryAndSectionFiltersAreIntersectedWithSearch() {
        assertTrue(HealthMetricCatalog.search("ALT", laboratory = false).isEmpty())
        assertEquals(listOf(HealthMetric.ALT), HealthMetricCatalog.search("ALT", laboratory = true, HealthMetricGroup.LIVER).map { it.metric })
        assertTrue(HealthMetricCatalog.search("ALT", group = HealthMetricGroup.KIDNEY).isEmpty())
        assertTrue(HealthMetricCatalog.search("glucose", laboratory = false).any { it.metric == HealthMetric.GLUCOSE })
        assertTrue(HealthMetricCatalog.search("glucose", laboratory = true).any { it.metric == HealthMetric.GLUCOSE })
    }
    @Test fun unmatchedSearchDoesNotFallbackToUnrelatedHealthRecords() {
        assertTrue(HealthMetricCatalog.search("unknown-xyz").isEmpty())
        assertEquals(HealthMetric.entries.size, HealthMetricCatalog.search("").size)
    }
    @Test fun newMetricAliasesAlsoDriveConservativeTableColumnSuggestions() {
        for (entry in HealthMetricCatalog.entries.filter { it.metric.fields.size == 1 }) {
            val headers = listOf("time", entry.english, "unit", "reference_range")
            val m = HealthTablePolicy.suggest(headers, entry.metric)
            assertEquals(entry.metric.name, entry.english, m.columns[entry.metric.fields.first()])
            assertEquals("reference_range", m.referenceColumn)
        }
    }
    @Test fun ambiguousAliasColumnsAreNotGuessed() {
        val m = HealthTablePolicy.suggest(listOf("time", "LDL", "LDL-C", "unit"), HealthMetric.LDL)
        assertEquals("", m.columns["ldl"])
    }
    @Test fun tableResultsKeepReferenceTextAndQualitativeOrBoundedSemantics() {
        val time = "2026-09-01T08:00:00Z"
        for ((metric, raw) in listOf(HealthMetric.CRP to "<0.1", HealthMetric.HEMOGLOBIN to "120-130", HealthMetric.URINE_PROTEIN to "\u9634\u6027")) {
            val headers = listOf("time", metric.fields.first(), "reference")
            val mapping = HealthTablePolicy.suggest(headers, metric).copy(unit = metric.units.first(), zone = "UTC")
            val batch = HealthTableBatch(java.util.UUID.randomUUID().toString(), java.util.UUID.randomUUID().toString(), "a".repeat(64), "report.csv", "csv", headers, mapping = mapping)
            val result = HealthTablePolicy.evaluate(batch, HealthTableRow(1, mapOf("time" to time, metric.fields.first() to raw, "reference" to "as reported")))
            assertEquals(metric.name, HealthTableRowState.VALID, result.state); assertEquals(raw, result.draft!!.values[metric.fields.first()]); assertEquals("as reported", result.draft!!.reference)
        }
    }
    @Test fun tableUnitAbsenceIsValidOnlyForActualQualitativeRowsNotNumericOrMissingRows() {
        val headers = listOf("time", "crp"); val m = HealthTablePolicy.suggest(headers, HealthMetric.CRP).copy(zone = "UTC")
        val batch = HealthTableBatch(java.util.UUID.randomUUID().toString(), java.util.UUID.randomUUID().toString(), "a".repeat(64), "lab.csv", "csv", headers, mapping = m)
        fun result(value: String) = HealthTablePolicy.evaluate(batch, HealthTableRow(1, mapOf("time" to "2026-09-01T08:00:00Z", "crp" to value)))
        assertEquals(HealthTableRowState.VALID, result("negative").state); assertEquals("", result("negative").draft!!.unit)
        assertEquals("unit", result("<0.1").issue); assertEquals(HealthTableRowState.MISSING, result("").state)
        assertEquals(HealthTableRowState.INVALID, result("unknown").state)
    }
}
