package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthResultPolicyTest {
    private val now = 1_790_000_000_000L
    private fun laboratory(value: String) = HealthDraft(HealthMetric.CRP, mapOf("crp" to value), "mg/L", now)
    @Test fun numericFormattingAndItsReportedNotationBothSurviveRoundTrip() {
        val record = HealthObservationPolicy.observation(laboratory("000,50"), now)
        assertEquals("0.5", record.draft.values["crp"]); assertEquals("000,50", record.draft.reportedValues["crp"])
        assertEquals(record, HealthObservation.from(record.json()))
    }
    @Test fun comparisonsKeepTheirOperatorAndAreNotExactNumbers() {
        for ((raw, expected) in mapOf("< 00.10" to "<0.1", ">=2" to ">=2", "\u2264 3,50" to "<=3.5", "\u2265 0" to ">=0", ">3" to ">3")) {
            val value = HealthResult.parse(raw, HealthResultForm.LABORATORY)!!
            assertEquals(expected, value.canonical); assertEquals(raw, value.raw); assertEquals(HealthResultKind.COMPARISON, value.kind); assertNull(value.exactNumber)
        }
    }
    @Test fun rangesPreserveBothBoundsInsteadOfTheirMidpoint() {
        for (raw in listOf("1.2 - 3.4", "1,2\u20133,4", "1.2 to 3.4", "1.2~3.4")) {
            val value = HealthResult.parse(raw, HealthResultForm.LABORATORY)!!
            assertEquals("range:1.2..3.4", value.canonical); assertEquals("1.2", value.number); assertEquals("3.4", value.upper); assertNull(value.exactNumber)
        }
    }
    @Test fun reversedIncompleteAndUnparseableBoundsAreNotSaved() {
        for (raw in listOf("3-1", "<", "1-", "-2", "1/2", "NaN", "Infinity", "1e99", "1.2.3", "=1+2", "< -1")) {
            assertNull(raw, HealthResult.parse(raw, HealthResultForm.LABORATORY))
        }
    }
    @Test fun qualitativeLabelsAndGradesAreNotConvertedToNumbersOrBooleans() {
        for (raw in listOf("negative", "positive", "trace", "indeterminate", "\u9634\u6027", "\u9633\u6027", "\u5f31\u9633\u6027", "\u00b1", "++", "3+")) {
            val value = HealthResult.parse(raw, HealthResultForm.QUALITATIVE)!!
            assertEquals(raw, value.raw); assertEquals(HealthResultKind.QUALITATIVE, value.kind); assertNull(value.exactNumber)
        }
    }
    @Test fun qualitativeResultsCannotBecomeNumericMeasurements() {
        for (raw in listOf("", "0", "123", "<1", "=SUM(A1)", "1.2")) assertNull(raw, HealthResult.parse(raw, HealthResultForm.QUALITATIVE))
        assertNull(HealthResult.parse("negative", HealthResultForm.POSITIVE))
    }
    @Test fun zeroRequiresARecordedValueAndIsNotAFallbackForMissingData() {
        assertNull(HealthResult.parse("", HealthResultForm.NONNEGATIVE))
        assertEquals(BigDecimal.ZERO, HealthResult.parse("0", HealthResultForm.NONNEGATIVE)!!.exactNumber)
        assertNull(HealthResult.parse("0", HealthResultForm.POSITIVE))
    }
    @Test fun countsAreWholeNumbersWithoutAmbiguousThousandsSeparators() {
        assertEquals("1234", HealthResult.parse("001234", HealthResultForm.COUNT)!!.canonical)
        for (value in listOf("1.2", "1.0", "1,000", "1 000", "-1", "<1")) assertNull(value, HealthResult.parse(value, HealthResultForm.COUNT))
    }
    @Test fun rangesAndBoundsAreNotAcceptedAsDailyScalarVitals() {
        for (form in listOf(HealthResultForm.POSITIVE, HealthResultForm.NONNEGATIVE, HealthResultForm.COUNT)) {
            assertNull(HealthResult.parse("<12", form)); assertNull(HealthResult.parse("1-2", form))
        }
    }
    @Test fun resultBoundsAndControlCharactersDoNotCreatePartialValues() {
        for (value in listOf("9".repeat(21), "a".repeat(129), "negative\npositive", "x\u0000y")) {
            assertNull(HealthResult.parse(value, HealthResultForm.LABORATORY)); assertNull(HealthResult.parse(value, HealthResultForm.QUALITATIVE))
        }
    }
    @Test fun explicitTypedMetadataMustAgreeWithTheActualValue() {
        val j = laboratory("<0.1").json()
        j.getJSONObject("results").getJSONObject("crp").put("kind", "NUMBER")
        assertTrue(runCatching { HealthDraft.from(j) }.isFailure)
    }
    @Test fun legacyPayloadWithoutTypedOrReferenceFieldsStillLoads() {
        val draft = laboratory("1.2"); val j = draft.json()
        listOf("results", "reported_values", "reference").forEach(j::remove)
        assertEquals(draft, HealthDraft.from(j))
    }
    @Test fun incompleteDraftsKeepTheirTextRatherThanInventingTypedResults() {
        val draft = laboratory("<").copy(reference = "verify later")
        assertEquals(draft, HealthDraft.from(draft.json())); assertEquals(0, draft.json().getJSONObject("results").length())
        assertNotNull(HealthObservationPolicy.validate(draft, now))
    }
    @Test fun editingAValueDoesNotKeepStaleReportedNotation() {
        val first = HealthObservationPolicy.observation(laboratory("001.00"), now)
        val edit = HealthObservationPolicy.observation(first.editable().copy(values = mapOf("crp" to "2")), now)
        assertEquals("2", edit.draft.reportedValues["crp"]); assertEquals(2, edit.revision)
    }
    @Test fun reportedReferenceIntervalsAreNotUsedToInventClassification() {
        val record = HealthObservationPolicy.observation(laboratory("<0.1").copy(reference = "0.0 - 5.0 (report laboratory)"), now)
        assertEquals("0.0 - 5.0 (report laboratory)", HealthObservation.from(record.json()).draft.reference)
        assertFalse(record.json().toString().contains("normal")); assertFalse(record.json().toString().contains("diagnosis"))
    }
    @Test fun referenceEditsDoNotEraseReportedValues() {
        val record = HealthObservationPolicy.observation(laboratory("< 00.10"), now)
        val edit = HealthObservationPolicy.observation(record.editable().copy(reference = "<5"), now)
        assertEquals("< 00.10", edit.draft.reportedValues["crp"])
        assertEquals(HealthObservationPolicy.duplicateKey(record), HealthObservationPolicy.duplicateKey(edit))
    }
    @Test fun mathematicallyEquivalentBoundsDeduplicateButBoundsDoNotBecomeExactValues() {
        fun key(raw: String) = HealthObservationPolicy.duplicateKey(HealthObservationPolicy.observation(laboratory(raw), now))
        assertEquals(key("< 0.10"), key("<0.1")); assertEquals(key("1 - 2"), key("1.0~2.0"))
        assertNotEquals(key("<1"), key("1")); assertNotEquals(key("1-1"), key("1")); assertNotEquals(key("<1"), key("<=1"))
    }
    @Test fun qualitativeResultsNeedNoInventedPhysicalUnit() {
        val draft = HealthDraft(HealthMetric.URINE_PROTEIN, mapOf("urine_protein" to "negative"), measuredAt = now)
        assertNull(HealthObservationPolicy.validate(draft, now)); assertEquals("", HealthObservationPolicy.observation(draft, now).draft.unit)
        assertNotNull(HealthObservationPolicy.validate(draft.copy(unit = "mg/L"), now))
    }
    @Test fun laboratoryReportsCanHaveAReportedQualitativeLabelWithoutAnInventedUnit() {
        for (raw in listOf("negative", "not detected", "\u672a\u68c0\u51fa", "\u00b1")) {
            val record = HealthObservationPolicy.observation(laboratory(raw).copy(unit = ""), now)
            assertEquals("", record.draft.unit); assertEquals(HealthResultKind.QUALITATIVE, HealthResult.parse(raw, record.draft.metric.form)!!.kind)
            assertNull(HealthResult.parse(raw, record.draft.metric.form)!!.exactNumber)
        }
    }
    @Test fun numericLaboratoryResultsStillRequirePhysicalUnits() {
        for (raw in listOf("1", "0", "<0.1", "1-2")) assertEquals(HealthValidationIssue.INVALID_UNIT, HealthObservationPolicy.validate(laboratory(raw).copy(unit = ""), now)?.issue)
    }
    @Test fun unrecognizedTextIsNotGuessedToBeANormalOrNegativeLaboratoryResult() {
        for (raw in listOf("see report", "normal", "unknown", "5 high")) assertNull(HealthResult.parse(raw, HealthResultForm.LABORATORY))
    }
}
