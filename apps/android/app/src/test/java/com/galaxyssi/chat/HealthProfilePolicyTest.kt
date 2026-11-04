package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthProfilePolicyTest {
    private val today = LocalDate.of(2026, 11, 4)
    private fun normalize(field: HealthProfileField, text: String, unit: String = "") = HealthProfilePolicy.normalize(field, HealthProfileInput(text, unit), today)
    private fun entry(kind: HealthBackgroundKind = HealthBackgroundKind.HISTORY) = HealthBackgroundEntry(UUID.randomUUID().toString(), kind, "Self-reported history")
    @Test fun omittedFieldsHaveNoInferredDefaults() { HealthProfileField.entries.forEach { assertNull(normalize(it, "  ")) } }
    @Test fun namesPreserveUserLanguageAndTrimOnlyOuterSpace() { assertEquals("\u6797 \u4e88\u5b89", normalize(HealthProfileField.NAME, "  \u6797 \u4e88\u5b89  ")!!.text) }
    @Test fun namesRejectNewlinesAndControlCharacters() { for (s in listOf("name\nother", "name\u0000", "x".repeat(81))) assertTrue(runCatching { normalize(HealthProfileField.NAME, s) }.isFailure) }
    @Test fun realLeapDatesAndTodayAreAcceptedWithoutInventingAnAge() {
        assertEquals("2000-02-29", normalize(HealthProfileField.BIRTH_DATE, "2000-02-29")!!.text)
        assertEquals(today.toString(), normalize(HealthProfileField.BIRTH_DATE, today.toString())!!.text)
    }
    @Test fun futureNonLeapAndMalformedBirthDatesAreRejected() {
        for (s in listOf("2026-11-05", "1900-02-29", "2026-02-30", "2026-1-1", "2026-11-04T00:00:00", "0000-01-01"))
            assertTrue(s, runCatching { normalize(HealthProfileField.BIRTH_DATE, s) }.isFailure)
    }
    @Test fun sexIsExplicitAndDecliningIsDifferentFromAnEmptyField() {
        HealthReferenceSex.entries.forEach { assertEquals(it.name, normalize(HealthProfileField.REFERENCE_SEX, it.name)!!.text) }
        assertNull(normalize(HealthProfileField.REFERENCE_SEX, "")); assertTrue(runCatching { normalize(HealthProfileField.REFERENCE_SEX, "default male") }.isFailure)
    }
    @Test fun heightConversionUsesExactDecimalArithmetic() {
        assertEquals(BigDecimal("172.72"), HealthProfilePolicy.centimeters(HealthProfileInput("68", "in")))
        assertEquals("172.5", normalize(HealthProfileField.HEIGHT, "0172,50", "cm")!!.text)
    }
    @Test fun heightsRejectBoundsZeroNegativeNanAndUnknownUnits() {
        for (s in listOf("<170", "170-180", "0", "-1", "NaN", "Infinity", "1e3")) assertTrue(runCatching { normalize(HealthProfileField.HEIGHT, s, "cm") }.isFailure)
        assertTrue(runCatching { normalize(HealthProfileField.HEIGHT, "170", "kg") }.isFailure)
    }
    @Test fun physiologicalContextIsOptionalSelfReportNotAnAutomaticallyInferredStage() {
        assertEquals("User supplied\ncontext", normalize(HealthProfileField.PHYSIOLOGICAL_CONTEXT, "User supplied\ncontext")!!.text)
        assertNull(normalize(HealthProfileField.PHYSIOLOGICAL_CONTEXT, ""))
    }
    @Test fun nonHeightFieldsCannotSmuggleMeasurementUnits() { assertTrue(runCatching { normalize(HealthProfileField.NAME, "Name", "kg") }.isFailure) }
    @Test fun aPartiallyTypedDateMayBeDraftedButNotCommitted() {
        val d = HealthProfileDraft("", mapOf(HealthProfileField.BIRTH_DATE to HealthProfileInput("2026-")), mapOf(HealthProfileField.BIRTH_DATE to ""))
        HealthProfilePolicy.validateDraft(d); assertTrue(runCatching { normalize(HealthProfileField.BIRTH_DATE, "2026-") }.isFailure)
    }
    @Test fun draftsRequireMatchingChangeAndExpectedVersionKeys() {
        assertTrue(runCatching { HealthProfileDraft("", mapOf(HealthProfileField.NAME to HealthProfileInput("Name")), emptyMap()) }.isFailure)
    }
    @Test fun basicDraftsRoundTripTheirOriginalOptimisticVersions() {
        val d = HealthProfileDraft("generation", mapOf(HealthProfileField.HEIGHT to HealthProfileInput("17", "cm")), mapOf(HealthProfileField.HEIGHT to "token"))
        assertEquals(d, HealthProfileDraft.from(d.json()))
    }
    @Test fun selfReportedEntrySerializationNeverRelabelsItAsAMeasurement() {
        val e = entry(); assertEquals("self_reported", e.json().getString("source")); assertEquals("self", e.json().getString("profile")); assertEquals(e, HealthBackgroundEntry.from(e.json()))
    }
    @Test fun anotherOwnerOrForgedSourceIsRejected() {
        assertTrue(runCatching { HealthBackgroundEntry.from(entry().json().put("profile", "family-member")) }.isFailure)
        assertTrue(runCatching { HealthBackgroundEntry.from(entry().json().put("source", "laboratory")) }.isFailure)
    }
    @Test fun medicationDoseAndTimingRemainTextRatherThanCalculatedAdvice() {
        val e = entry(HealthBackgroundKind.MEDICATION).copy(dose = "0.5 tablet as prescribed", timing = "after breakfast")
        assertEquals(e, HealthProfilePolicy.entry(e)); assertEquals(e.dose, HealthBackgroundEntry.from(e.json()).dose)
    }
    @Test fun historyAndAllergyEntriesCannotAcquireMedicationOnlyFields() {
        for (kind in listOf(HealthBackgroundKind.HISTORY, HealthBackgroundKind.ALLERGY)) assertTrue(runCatching { HealthProfilePolicy.entry(entry(kind).copy(dose = "dose")) }.isFailure)
    }
    @Test fun blankEntryNamesAreNotSavedAsNoKnownConditions() { assertTrue(runCatching { HealthProfilePolicy.entry(entry().copy(name = "  ")) }.isFailure) }
    @Test fun entryNamesRejectPathLikeIdsAndHiddenControls() {
        assertTrue(runCatching { HealthProfilePolicy.entry(entry().copy(id = "../self")) }.isFailure)
        assertTrue(runCatching { HealthProfilePolicy.entry(entry().copy(name = "Name\nother")) }.isFailure)
    }
    @Test fun longBackgroundNotesAreBoundedPerEntryNotByTotalEntryCount() {
        HealthProfilePolicy.entry(entry().copy(detail = "x".repeat(4000)))
        assertTrue(runCatching { HealthProfilePolicy.entry(entry().copy(detail = "x".repeat(4001))) }.isFailure)
    }
    @Test fun backgroundDraftsMayRemainIncompleteAndRecoverTheirExpectedToken() {
        val d = HealthBackgroundDraft("generation", entry().copy(name = ""), "token")
        HealthProfilePolicy.validateDraft(d); assertEquals(d, HealthBackgroundDraft.from(d.json())); assertTrue(d.key.startsWith("edit:"))
    }
    @Test fun newDraftsAreSeparatedByBackgroundCategory() {
        assertNotEquals(HealthBackgroundDraft("", entry()).key, HealthBackgroundDraft("", entry(HealthBackgroundKind.ALLERGY)).key)
    }
    @Test fun dependencyStampsContainOpaqueVersionsNotPatientFacts() {
        val s = HealthProfileStamp("generation", mapOf("field:HEIGHT" to "token", "category:ALLERGY" to "category-token"))
        assertEquals(s, HealthProfileStamp.from(s.json())); assertFalse(s.json().has("values")); assertFalse(s.json().has("name"))
    }
    @Test fun anEmptyExplicitContextDoesNotSelectEveryField() {
        val c = HealthProfileContext(emptyMap(), emptyList(), HealthProfileStamp("", emptyMap()))
        assertTrue(c.fields.isEmpty()); assertTrue(c.entries.isEmpty()); assertEquals("self_reported", c.source); assertEquals("self", c.profileId)
    }
}
