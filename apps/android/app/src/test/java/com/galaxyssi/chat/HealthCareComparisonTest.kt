package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareComparisonTest {
    private val now = 1_793_000_000_000L
    private fun reading(value: String, at: Long = now, unit: String = "mmol/L", condition: String = "fasting") =
        HealthObservation(UUID.randomUUID().toString(), 1, HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to value), unit, at, condition = condition, reference = "4-6"), at)
    private fun context(r: HealthObservation) = HealthCareContext(HealthCareRecordRef(r.id, r.revision),
        HealthCareTruth.YES, HealthCareTruth.NO, HealthCareTruth.NO, HealthCareSpecimen.LAB_PLASMA, 8,
        HealthCareTruth.NO, now)
    private fun assess(r: List<HealthObservation>, previous: HealthCareAssessment? = null, c: HealthCareContext? = null) =
        HealthCarePolicy.assess(HealthMetric.GLUCOSE, r, c, previous)!!

    @Test fun newResultPreservesPriorContextButDoesNotReuseItForCurrentResult() {
        val old = reading("6.3", now - 1000); val next = reading("5.4")
        val before = assess(listOf(old), c = context(old))
        val after = assess(listOf(next, old), before, context(old))
        assertEquals(context(old), after.comparison!!.previousContext)
        val data = HealthCareComparisonPolicy.handoff(after, context(old))!!
        assertTrue(data.isNull("current_confirmed_context"))
        assertEquals("-0.9", data.getJSONArray("arithmetic_changes_only").getJSONObject(0).getString("delta"))
        assertFalse(data.getBoolean("clinical_direction_verified"))
        assertTrue(HealthCareComparisonGap.CONTEXT_UNCONFIRMED in HealthCareComparisonPolicy.gaps(after, context(old)))
        val concern = HealthCarePolicy.reconcile(null, HealthMetric.GLUCOSE, before, "first", now)!!
        val updated = HealthCarePolicy.reconcile(concern, HealthMetric.GLUCOSE, after, "second", now + 1)!!
        assertEquals(HealthCareStage.REASSESS, updated.stage); assertNull(updated.context); assertNull(updated.target)
        val snapshot = JSONObject(HealthCareDiscussionPolicy.snapshot(updated))
        assertEquals("6.3", snapshot.getJSONObject("result_comparison").getJSONObject("before").getJSONObject("values").getString("glucose"))
        assertEquals("5.4", snapshot.getJSONObject("result_comparison").getJSONObject("after").getJSONObject("values").getString("glucose"))
    }
    @Test fun arithmeticDoesNotClassifyRisingStableOrFallingValuesClinically() {
        val old = reading("6.3", now - 1000)
        for ((number, delta) in listOf("6.8" to "0.5", "6.3" to "0.0", "5.4" to "-0.9")) {
            val next = reading(number)
            val result = assess(listOf(old, next), assess(listOf(old)), context(old))
            val data = HealthCareComparisonPolicy.handoff(result, context(next))!!
            assertEquals(delta, data.getJSONArray("arithmetic_changes_only").getJSONObject(0).getString("delta"))
            assertFalse(data.getBoolean("clinical_direction_verified"))
        }
    }
    @Test fun unitChangesDoNotSubtractOrSilentlyConvert() {
        val old = reading("6.3", now - 1000); val next = reading("100", unit = "mg/dL")
        val after = assess(listOf(old, next), assess(listOf(old)))
        assertTrue(HealthCareComparisonGap.UNITS_DIFFER in HealthCareComparisonPolicy.gaps(after, null))
        assertEquals(0, HealthCareComparisonPolicy.handoff(after, null)!!.getJSONArray("arithmetic_changes_only").length())
    }
    @Test fun sourceConditionReferenceAndUnknownContextAreExplicit() {
        val old = reading("6.3", now - 1000)
        val next = reading("5.4", condition = "after_meal").let { it.copy(draft = it.draft.copy(reference = "4-7"), source = "import") }
        val gaps = HealthCareComparisonPolicy.gaps(assess(listOf(old, next), assess(listOf(old))), null)
        assertTrue(gaps.containsAll(setOf(HealthCareComparisonGap.SOURCE_DIFFERS, HealthCareComparisonGap.CONDITIONS_DIFFER,
            HealthCareComparisonGap.REFERENCE_DIFFERS, HealthCareComparisonGap.CONTEXT_UNCONFIRMED, HealthCareComparisonGap.METHOD_UNVERIFIED)))
    }
    @Test fun rangesAndBoundsNeverBecomeExactChanges() {
        val old = reading("6.3", now - 1000)
        listOf("<5.4", "5-6").forEach { number ->
            val after = assess(listOf(old, reading(number)), assess(listOf(old)))
            assertTrue(HealthCareComparisonGap.NON_EXACT_RESULT in HealthCareComparisonPolicy.gaps(after, null))
            assertEquals(0, HealthCareComparisonPolicy.handoff(after, null)!!.getJSONArray("arithmetic_changes_only").length())
        }
    }
    @Test fun correctionIsNotPresentedAsFollowupImprovement() {
        val old = reading("6.3")
        val corrected = old.copy(revision = 2, draft = old.draft.copy(values = mapOf("glucose" to "5.4")))
        val after = assess(listOf(corrected), assess(listOf(old)), context(old))
        assertEquals(HealthCareComparisonKind.RECORD_CORRECTION, after.comparison!!.kind)
        assertEquals(0, HealthCareComparisonPolicy.handoff(after, null)!!.getJSONArray("arithmetic_changes_only").length())
        assertEquals(after.comparison, assess(listOf(corrected), after, context(corrected)).comparison)
    }
    @Test fun duplicateAndContextRefreshPreserveTheComparisonAnchor() {
        val old = reading("6.3", now - 1000); val next = reading("5.4")
        val after = assess(listOf(old, next), assess(listOf(old)), context(old))
        val refreshed = assess(listOf(old, next), after, context(next))
        assertEquals(after.comparison, refreshed.comparison)
        assertFalse(HealthCareComparisonGap.CONTEXT_UNCONFIRMED in HealthCareComparisonPolicy.gaps(refreshed, context(next)))
        assertEquals(refreshed, HealthCareAssessment.from(JSONObject(refreshed.json().toString())))
    }
    @Test fun deletingOrCorrectingThePreviousSourceRemovesObsoleteEvidence() {
        val old = reading("6.3", now - 1000); val next = reading("5.4")
        val after = assess(listOf(old, next), assess(listOf(old)))
        assertNull(assess(listOf(next), after).comparison)
        assertNull(assess(listOf(next, old.copy(revision = 2)), after).comparison)
    }
    @Test fun olderSourceBecomingLatestIsNotANewCollection() {
        val older = reading("6.0", now - 3000); val prior = reading("6.3", now - 2000); val latest = reading("6.8", now)
        val before = assess(listOf(latest, prior, older))
        val after = assess(listOf(prior, older), before)
        assertEquals(HealthCareComparisonKind.HISTORY_CHANGED, after.comparison!!.kind)
    }
    @Test fun missingLegacyMetadataRemainsReadableAndDoesNotInventContext() {
        val old = reading("6.3", now - 1000); val next = reading("5.4")
        val legacy = assess(listOf(old)).json().apply { remove("sample"); remove("comparison") }
        val restored = HealthCareAssessment.from(legacy)
        assertNull(restored.sample)
        val after = assess(listOf(next, old), restored, context(old))
        assertEquals(HealthCareRecordRef(old.id, 1), after.comparison!!.before.record)
        assertEquals(context(old), after.comparison.previousContext)
    }
    @Test fun noOtherProfileOrMetricEntersComparison() {
        val next = reading("6.3")
        assertNull(assess(listOf(next, reading("5.4", now - 1000).copy(profileId = "other"))).comparison)
        assertNull(HealthCarePolicy.assess(HealthMetric.HBA1C, listOf(next), null))
    }
    @Test fun legacyCorrectionAndMetadataBackfillDoNotInventANewFollowup() {
        val old = reading("6.3", now - 1000); val next = reading("5.4")
        val legacy = assess(listOf(next)).copy(sample = null)
        assertEquals(HealthCareComparisonKind.HISTORY_CHANGED, assess(listOf(next, old), legacy).comparison!!.kind)
        assertNull(assess(listOf(next.copy(revision = 2), old), legacy).comparison)
    }
    @Test fun bloodPressureComponentsKeepTheirOwnUnits() {
        fun bp(systolic: String, diastolic: String, pulse: String, at: Long) = HealthObservation(UUID.randomUUID().toString(), 1,
            HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to systolic, "diastolic" to diastolic, "pulse" to pulse),
                "mmHg", at, condition = "resting"), at)
        val old = bp("130", "85", "70", now - 1000); val next = bp("120", "80", "71", now)
        val previous = HealthCarePolicy.assess(HealthMetric.BLOOD_PRESSURE, listOf(old), null)!!
        val after = HealthCarePolicy.assess(HealthMetric.BLOOD_PRESSURE, listOf(next, old), null, previous)!!
        val changes = HealthCareComparisonPolicy.handoff(after, null)!!.getJSONArray("arithmetic_changes_only")
        assertEquals(3, changes.length())
        val byField = (0 until changes.length()).map { changes.getJSONObject(it) }.associateBy { it.getString("field") }
        assertEquals("-10", byField.getValue("systolic").getString("delta"))
        assertEquals("mmHg", byField.getValue("diastolic").getString("unit"))
        assertEquals("bpm", byField.getValue("pulse").getString("unit"))
    }
    @Test fun sourceIdentityIsLocalOnlyButChangesRemainVisibleToTheModel() {
        val old = reading("6.3", now - 1000).copy(platformOrigin = "private-origin-before")
        val next = reading("5.4").copy(platformOrigin = "private-origin-after")
        val after = assess(listOf(next, old), assess(listOf(old)))
        assertTrue(after.json().toString().contains("private-origin-before"))
        val handoff = HealthCareComparisonPolicy.handoff(after, null)!!.toString()
        assertFalse(handoff.contains("private-origin")); assertFalse(handoff.contains("device_group"))
        assertTrue(handoff.contains("SOURCE_DIFFERS"))
        val concern = HealthCarePolicy.reconcile(null, HealthMetric.GLUCOSE, assess(listOf(old)), "v", now)!!
        assertFalse(HealthCareDiscussionPolicy.snapshot(concern).contains("private-origin"))
    }
}
