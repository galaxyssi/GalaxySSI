package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthObservationPolicyTest {
    private val now = 1_790_000_000_000L
    private fun pressure() = HealthDraft(values = mapOf("systolic" to "124", "diastolic" to "82"), measuredAt = now)

    @Test fun pressureComponentsRemainOneMeasurementAndPulseIsOptional() {
        val record = HealthObservationPolicy.observation(pressure(), now)
        assertEquals(mapOf("systolic" to "124", "diastolic" to "82"), record.draft.values)
        assertFalse(record.draft.values.containsKey("pulse"))
        assertEquals(1, record.revision)
        assertEquals(record, HealthObservation.from(JSONObject(record.json().toString())))
    }
    @Test fun everyRequiredFieldMustBeConfirmedRatherThanFilledWithZero() {
        for (metric in HealthMetric.entries) {
            val values = metric.requiredFields.associateWith { "123" }
            for (field in metric.requiredFields) {
                val error = HealthObservationPolicy.validate(HealthDraft(metric, values - field, measuredAt = now), now)
                assertEquals(HealthValidationIssue.MISSING_VALUE, error?.issue)
                assertEquals(field, error?.field)
            }
        }
    }
    @Test fun positiveDecimalsAcceptCommaWithoutChangingUnits() {
        assertEquals("0.5", HealthObservationPolicy.canonicalNumber(".5"))
        for (unit in HealthMetric.GLUCOSE.units) {
            val record = HealthObservationPolicy.observation(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "005,60"), unit, now), now)
            assertEquals("5.6", record.draft.values["glucose"])
            assertEquals(unit, record.draft.unit)
        }
    }
    @Test fun pressureAndOptionalPulseRetainDifferentComponentUnits() {
        val draft = pressure().copy(values = pressure().values + ("pulse" to "68"))
        val json = draft.json()
        assertEquals("mmHg", json.getJSONObject("component_units").getString("systolic"))
        assertEquals("bpm", json.getJSONObject("component_units").getString("pulse"))
        assertEquals(draft, HealthDraft.from(json))
        json.getJSONObject("component_units").put("pulse", "mmHg")
        assertTrue(runCatching { HealthDraft.from(json) }.isFailure)
    }
    @Test fun invalidNumbersNeverProduceObservations() {
        for (raw in listOf("0", "-1", "NaN", "Infinity", "1e3", "1/2", ".", "1.2.3", "1,2.3", "123456789012345678901")) {
            val draft = pressure().copy(values = pressure().values + ("systolic" to raw))
            assertEquals(raw, HealthValidationIssue.INVALID_NUMBER, HealthObservationPolicy.validate(draft, now)?.issue)
            assertTrue(runCatching { HealthObservationPolicy.observation(draft, now) }.isFailure)
        }
    }
    @Test fun optionalPulseCannotContainAnInvalidValue() {
        assertEquals("pulse", HealthObservationPolicy.validate(pressure().copy(values = pressure().values + ("pulse" to "abc")), now)?.field)
    }
    @Test fun invalidUnitAndTimeAreRejected() {
        assertEquals(HealthValidationIssue.INVALID_UNIT, HealthObservationPolicy.validate(pressure().copy(unit = "kg"), now)?.issue)
        assertEquals(HealthValidationIssue.INVALID_TIME, HealthObservationPolicy.validate(pressure().copy(measuredAt = 0), now)?.issue)
        assertEquals(HealthValidationIssue.INVALID_TIME, HealthObservationPolicy.validate(pressure().copy(measuredAt = now + 120_000), now)?.issue)
    }
    @Test fun unknownComponentsAndContextsAreNotSilentlyDropped() {
        for (draft in listOf(pressure().copy(values = pressure().values + ("unknown" to "123")),
            pressure().copy(condition = "invented"), pressure().copy(side = "invented"), pressure().copy(note = "x".repeat(2001)))) {
            assertEquals(HealthValidationIssue.INVALID_CONTEXT, HealthObservationPolicy.validate(draft, now)?.issue)
        }
    }
    @Test fun duplicateIdentityUsesValuesTimeUnitSourceAndConditionsButNotDisplayFormatting() {
        val a = HealthObservationPolicy.observation(pressure(), now)
        val b = HealthObservationPolicy.observation(pressure().copy(values = mapOf("systolic" to "124.0", "diastolic" to "082.00"), note = "note"), now)
        assertEquals(HealthObservationPolicy.duplicateKey(a), HealthObservationPolicy.duplicateKey(b))
        for (different in listOf(a.copy(source = "device"), a.copy(profileId = "another"),
            a.copy(draft = a.draft.copy(measuredAt = now - 1)), a.copy(draft = a.draft.copy(condition = "resting")),
            a.copy(draft = a.draft.copy(side = "left")))) {
            assertNotEquals(HealthObservationPolicy.duplicateKey(a), HealthObservationPolicy.duplicateKey(different))
        }
    }
    @Test fun draftRoundtripDoesNotConvertOrFillMissingValues() {
        val draft = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to ""), "mg/dL", now, note = "verify later")
        assertEquals(draft, HealthDraft.from(JSONObject(draft.json().toString())))
        assertFalse(HealthDraft(measuredAt = now).hasInput())
        assertTrue(draft.hasInput())
    }
    @Test fun editsKeepIdentityAndIncrementRevision() {
        val initial = HealthObservationPolicy.observation(pressure(), now)
        val edit = HealthObservationPolicy.observation(initial.editable().copy(note = "confirmed"), now)
        assertEquals(initial.id, edit.id)
        assertEquals(2, edit.revision)
        assertEquals("", edit.draft.recordId)
    }
    @Test fun unsupportedBackupVersionIsNotAcceptedAsARecord() {
        val json = HealthObservationPolicy.observation(pressure(), now).json().put("format", 2)
        assertTrue(runCatching { HealthObservation.from(json) }.isFailure)
    }
}
