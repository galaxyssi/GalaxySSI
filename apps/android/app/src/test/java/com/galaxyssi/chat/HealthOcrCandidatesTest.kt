package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthOcrCandidatesTest {
    private val id = UUID.randomUUID().toString()
    private val job = HealthImportJob(id, "content://test/report", 1)
    private val original = HealthOriginal(id, id, "report.png", "image/png", 10, "a".repeat(64), 1, "test", "file")
    private fun suggest(vararg text: String) = HealthOcrCandidates.suggest(job, original,
        HealthOcrPage(2, 1000, 1000, text.mapIndexed { index, value -> HealthOcrLine(value, listOf(0, index * 50, 800, index * 50 + 30)) }))

    @Test fun reportExtractsSupportedLabsWithoutInventingTimeOrConfirmation() {
        val result = suggest("Glucose 5.6 mmol/L", "Total cholesterol 4.8 mmol/L", "Hemoglobin 142 g/L")
        assertEquals(listOf(HealthMetric.GLUCOSE, HealthMetric.CHOLESTEROL, HealthMetric.HEMOGLOBIN), result.map { it.metric })
        assertEquals(listOf("5.6", "4.8", "142"), result.map { it.values.values.single() })
        result.forEach {
            assertEquals(0L, it.measuredAt); assertFalse(it.evidence!!.confirmed)
            assertEquals(2, it.evidence.page); assertEquals(original.sha256, it.evidence.sha256)
            assertTrue(it.evidence.valid()); assertEquals(1, it.evidence.boxes.size)
        }
    }
    @Test fun chineseAliasesAndDecimalCommaKeepTheOriginalUnits() {
        val result = suggest("葡萄糖：5,6 mmol/L", "总胆固醇 188 mg/dL", "血红蛋白 14 g/dL", "体重 60 kg")
        assertEquals(listOf("mmol/L", "mg/dL", "g/dL", "kg"), result.map { it.unit })
        assertEquals("5.6", result.first().values["glucose"])
    }
    @Test fun missingUnitsStayUnknownRatherThanAssumed() {
        val result = suggest("Glucose 5.6", "Blood pressure 124/82")
        assertEquals(2, result.size); assertTrue(result.all { it.unit.isEmpty() })
    }
    @Test fun comparisonAndRangesAreNotReducedToSingleNumbers() {
        for (text in listOf("Glucose < 5.6 mmol/L", "Glucose >5.6", "Glucose 4.0-6.0", "Glucose 4.0～6.0",
            "Glucose 5.6 ± 0.2", "Glucose 5.6/6.0", "Glucose 1e3", "Glucose 4.0 至 6.0", "Glucose 1.2.3")) {
            assertTrue(text, suggest(text).isEmpty())
        }
    }
    @Test fun referenceAndQualitativeRowsDoNotBecomeMeasurements() {
        for (text in listOf("Glucose reference 3.9-6.1", "Glucose 5.6 mmol/L reference 3.9-6.1", "Glucose negative",
            "Glucose positive 2026", "血糖参考范围 3.9-6.1", "血糖 阴性")) assertTrue(text, suggest(text).isEmpty())
    }
    @Test fun aTimestampAfterAFieldNameIsNotAResult() {
        assertTrue(suggest("Glucose measured 2026-11-03 08:00", "Blood pressure date 2026/11/03", "Glucose 2026-11-03").isEmpty())
    }
    @Test fun pressurePairStaysOneDraftAndRetainsKpa() {
        val result = suggest("Blood pressure: 16.5/10.9 kPa").single()
        assertEquals(HealthMetric.BLOOD_PRESSURE, result.metric)
        assertEquals(mapOf("systolic" to "16.5", "diastolic" to "10.9"), result.values)
        assertEquals("kPa", result.unit)
    }
    @Test fun dualUnitRowsRemainUnspecifiedRatherThanChoosingTheWrongUnit() {
        for (text in listOf("Glucose 5.6 mmol/L (100 mg/dL)", "Weight 60 kg (132 lb)", "Hemoglobin 142 g/L (14.2 g/dL)",
            "Blood pressure 124/82 mmHg kPa")) assertEquals(text, "", suggest(text).single().unit)
    }
    @Test fun pressureComponentsDoNotBorrowUnitsFromAnotherReportRow() {
        val result = suggest("SYS 16.5 kPa", "DIA 10.9 kPa", "Other pressure unit: mmHg").single()
        assertEquals("kPa", result.unit)
    }
    @Test fun separateDeviceLabelsCanAlignUniqueNumbersOnTheSameRow() {
        val lines = listOf(HealthOcrLine("SYS", listOf(100, 100, 200, 140)), HealthOcrLine("124", listOf(700, 100, 850, 140)),
            HealthOcrLine("DIA", listOf(100, 300, 200, 340)), HealthOcrLine("82", listOf(700, 300, 850, 340)),
            HealthOcrLine("PUL", listOf(100, 500, 200, 540)), HealthOcrLine("68", listOf(700, 500, 850, 540)))
        val result = HealthOcrCandidates.suggest(job.copy(mode = "device"), original, HealthOcrPage(1, 1000, 1000, lines)).single()
        assertEquals(mapOf("systolic" to "124", "diastolic" to "82", "pulse" to "68"), result.values)
        assertEquals("", result.unit); assertEquals(3, result.evidence!!.boxes.size)
    }
    @Test fun multiplePossibleDeviceValuesDoNotSelectOneArbitrarily() {
        val lines = listOf(HealthOcrLine("SYS", listOf(100, 100, 200, 140)), HealthOcrLine("124", listOf(400, 100, 500, 140)),
            HealthOcrLine("125", listOf(700, 100, 800, 140)), HealthOcrLine("DIA 82", listOf(100, 300, 800, 340)))
        assertTrue(HealthOcrCandidates.suggest(job.copy(mode = "device"), original, HealthOcrPage(1, 1000, 1000, lines)).isEmpty())
    }
    @Test fun unrelatedHemoglobinTestsAreNeverRelabeledAsHemoglobin() {
        assertTrue(suggest("Mean corpuscular hemoglobin 30 pg", "Hemoglobin A1c 5.6 %", "糖化血红蛋白 5.6 %",
            "平均红细胞血红蛋白含量 30 pg", "MCH 30 pg").isEmpty())
    }
    @Test fun repeatedResultLabelsKeepSeparateTraceableCandidates() {
        val result = suggest("Glucose 5.6 mmol/L", "Glucose 6.2 mmol/L")
        assertEquals(2, result.size); assertEquals(2, result.map { it.evidence!!.candidateId }.distinct().size)
        assertEquals(result, suggest("Glucose 5.6 mmol/L", "Glucose 6.2 mmol/L"))
    }
    @Test fun sourceIdentityDoesNotDependOnRecognizerLineOrdering() {
        val a = HealthOcrLine("Glucose 5.6 mmol/L", listOf(0, 100, 800, 130))
        val b = HealthOcrLine("Hemoglobin 142 g/L", listOf(0, 200, 800, 230))
        fun keys(lines: List<HealthOcrLine>) = HealthOcrCandidates.suggest(job, original, HealthOcrPage(1, 1000, 1000, lines))
            .associate { it.metric to it.evidence!!.candidateId }
        assertEquals(keys(listOf(a, b)), keys(listOf(b, a)))
    }
    @Test fun changedValuesAtTheSameLineCannotBeMistakenForAnEarlierSavedCandidate() {
        assertNotEquals(suggest("Glucose 5.6 mmol/L").single().evidence!!.candidateId,
            suggest("Glucose 6.2 mmol/L").single().evidence!!.candidateId)
    }
    @Test fun recognizedValuesCannotBeSavedWithoutExplicitSourceConfirmation() {
        val draft = suggest("Glucose 5.6 mmol/L").single().copy(measuredAt = 1_790_000_000_000L)
        assertEquals(HealthValidationIssue.UNCONFIRMED_SOURCE, HealthObservationPolicy.validate(draft)?.issue)
        val confirmed = draft.copy(evidence = draft.evidence!!.copy(confirmed = true))
        assertNull(HealthObservationPolicy.validate(confirmed)); assertEquals("ocr", HealthObservationPolicy.observation(confirmed).source)
    }
    @Test fun sourceRoundTripRetainsBoxesAndRejectsReversedCoordinates() {
        val draft = suggest("Glucose 5.6 mmol/L").single()
        assertEquals(draft, HealthDraft.from(JSONObject(draft.json().toString())))
        assertFalse(draft.evidence!!.copy(boxes = listOf(listOf(900, 0, 100, 20))).valid())
        assertFalse(draft.evidence.copy(sha256 = "bad").valid())
    }
    @Test fun oldManualDraftsRemainReadableWithoutEvidence() {
        val manual = HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "60"), "kg", 1_790_000_000_000L)
        assertFalse(manual.json().has("evidence")); assertEquals(manual, HealthDraft.from(manual.json()))
        assertNull(manual.evidence)
    }
    @Test fun collectionOrderIsSeparateFromThePhysicalOriginalPage() {
        val draft = HealthOcrCandidates.suggest(job.copy(documentPage = 7), original,
            HealthOcrPage(1, 1000, 1000, listOf(HealthOcrLine("Glucose 5.6 mmol/L")))).single()
        assertEquals(7, draft.evidence!!.documentPage); assertEquals(1, draft.evidence.page)
        assertEquals(draft, HealthDraft.from(draft.json()))
    }
}
