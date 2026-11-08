package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareClarificationContextTest {
    private val now = 1_793_000_000_000L
    private val ref = HealthCareRecordRef(UUID.randomUUID().toString(), 1)
    private val sample = HealthCareSample(ref, HealthMetric.GLUCOSE, now, mapOf("glucose" to "5.8"),
        "mmol/L", "", "fasting", "unspecified", "manual", "", "")
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "fixture",
        HealthCareAssessment(ref, now, "5.8", "mmol/L", "", setOf(HealthCareSignal.GLUCOSE_CONTEXT), sample = sample))
    private val context = HealthCareContext(ref, HealthCareTruth.YES, HealthCareTruth.NO, HealthCareTruth.NO,
        HealthCareSpecimen.HOME_CAPILLARY, 10, HealthCareTruth.NO, now)
    private fun snapshot(value: HealthCareContext? = context) = HealthCareClarificationContext.snapshot(issue.copy(context = value))
    private fun missing(value: JSONObject) = value.getJSONArray("unconfirmed_fields").let { array ->
        (0 until array.length()).map(array::getString).toSet()
    }

    @Test fun completeAnswersAreKnownAndNotARepeatQuestionnaire() {
        val value = snapshot()
        assertEquals("CURRENT_RECORD", value.getString("context_status"))
        val known = value.getJSONObject("known_answers")
        assertEquals(6, known.length()); assertTrue(missing(value).isEmpty())
        assertEquals("YES", known.getString("adult")); assertEquals("NO", known.getString("pregnant"))
        assertEquals("NO", known.getString("diagnosed_diabetes"))
        assertEquals("HOME_CAPILLARY", known.getString("specimen")); assertEquals(10, known.getInt("fasting_hours"))
        assertEquals("NO", known.getString("illness_or_glucose_affecting_medication"))
        assertEquals(ref.json().toString(), value.getJSONObject("record").toString())
        assertEquals(now, value.getLong("confirmed_at"))
    }
    @Test fun partiallyConfirmedAnswersStayKnownWhileOnlyMissingFieldsAreListed() {
        val value = snapshot(context.copy(pregnant = HealthCareTruth.UNKNOWN, fastingHours = null))
        assertEquals(setOf("pregnant", "fasting_hours"), missing(value))
        assertEquals(4, value.getJSONObject("known_answers").length())
        assertEquals("NO", value.getJSONObject("known_answers").getString("diagnosed_diabetes"))
        assertEquals("fasting", value.getString("recorded_condition"))
        assertFalse(value.getBoolean("condition_label_confirms_fasting_hours"))
    }
    @Test fun zeroHoursIsARealAnswerNotMissing() {
        assertEquals(0, snapshot(context.copy(fastingHours = 0)).getJSONObject("known_answers").getInt("fasting_hours"))
        assertFalse("fasting_hours" in missing(snapshot(context.copy(fastingHours = 0))))
        assertEquals(72, snapshot(context.copy(fastingHours = 72)).getJSONObject("known_answers").getInt("fasting_hours"))
    }
    @Test fun missingContextDoesNotInventNegativeAnswers() {
        val value = snapshot(null)
        assertEquals(6, missing(value).size); assertEquals(0, value.getJSONObject("known_answers").length())
        assertEquals("NOT_CONFIRMED", value.getString("context_status")); assertTrue(value.isNull("confirmed_at"))
    }
    @Test fun otherRecordAndOlderRevisionCannotAnswerForTheCurrentMeasurement() {
        listOf(ref.copy(id = UUID.randomUUID().toString()), ref.copy(revision = 2)).forEach {
            val changed = issue.copy(context = context.copy(record = it))
            val value = HealthCareClarificationContext.snapshot(changed)
            assertEquals("OTHER_RECORD_OR_REVISION", value.getString("context_status"))
            assertEquals(0, value.getJSONObject("known_answers").length())
            assertTrue(JSONObject(HealthCareDiscussionPolicy.snapshot(changed)).isNull("confirmed_context"))
        }
    }
    @Test fun otherMetricsDoNotReceiveAGlucoseQuestionnaire() {
        val changed = issue.copy(metric = HealthMetric.HBA1C)
        val value = HealthCareClarificationContext.snapshot(changed)
        assertTrue(missing(value).isEmpty()); assertEquals(0, value.getJSONObject("known_answers").length())
    }
    @Test fun removedSourceCannotBorrowOldContext() {
        val changed = issue.copy(context = context, assessment = HealthCareAssessment(null, now, "", "", "",
            setOf(HealthCareSignal.SOURCE_REMOVED)))
        val value = HealthCareClarificationContext.snapshot(changed)
        assertTrue(value.isNull("record")); assertTrue(missing(value).isEmpty())
        assertEquals(0, value.getJSONObject("known_answers").length())
    }
    @Test fun snapshotDoesNotClaimAccessToSeparateProfileOrCurrentSymptoms() {
        val value = snapshot()
        assertFalse(value.getBoolean("separate_profile_included"))
        assertFalse(value.getBoolean("current_symptoms_assessed"))
        assertFalse(value.getBoolean("unconfirmed_fields_are_mandatory_questions"))
        assertFalse(value.has("profile")); assertFalse(value.has("name"))
    }
    @Test fun commonDiscussionSnapshotIncludesClarificationsForManualAndAutomaticCalls() {
        listOf(null, JSONObject().put("reasons", listOf("authorization_review"))).forEach { followUp ->
            val result = JSONObject(HealthCareDiscussionPolicy.snapshot(issue.copy(context = context), followUp))
            assertEquals(10, result.getJSONObject("clarification_context").getJSONObject("known_answers").getInt("fasting_hours"))
            assertEquals(10, result.getJSONObject("confirmed_context").getInt("fasting"))
        }
    }
}
