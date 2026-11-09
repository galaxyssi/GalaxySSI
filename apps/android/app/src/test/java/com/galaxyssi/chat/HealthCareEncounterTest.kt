package com.galaxyssi.chat

import java.time.DateTimeException
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareEncounterTest {
    private val now = 1_793_000_000_000L
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "fixture-source",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6",
            setOf(HealthCareSignal.REPORT_HIGH)))
    private val draft = HealthCareEncounterDraft("Discuss the measurement", note = "Synthetic question, not an instruction")
    private fun create(details: HealthCareEncounterDraft = draft, at: Long = now) =
        HealthCareEncounterPolicy.apply(issue, null, UUID.randomUUID().toString(), details, at)

    @Test fun anUnscheduledPlanIsNotAHospitalReceipt() {
        val value = create()
        assertEquals(HealthCareEncounterState.PLANNED, value.details.state)
        assertNull(value.details.plannedAt); assertNull(value.details.attendedAt)
        assertEquals("user_reported", value.json().getString("provenance"))
        assertFalse(value.json().has("booking_verified")); assertFalse(value.json().has("prescription"))
    }
    @Test fun bookedAndAttendedStatesRequireTheirOwnExplicitDates() {
        assertThrows(IllegalArgumentException::class.java) { draft.copy(state = HealthCareEncounterState.BOOKING_RECORDED) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(state = HealthCareEncounterState.ATTENDED) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(attendedAt = now) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(state = HealthCareEncounterState.CANCELLED, attendedAt = now) }
        assertNotNull(create(draft.copy(state = HealthCareEncounterState.BOOKING_RECORDED, plannedAt = now + 60000)))
        assertNotNull(create(draft.copy(state = HealthCareEncounterState.ATTENDED, attendedAt = now - 60000)))
    }
    @Test fun plannedDateAloneDoesNotChangeStateAndFutureAttendanceIsRejected() {
        assertEquals(HealthCareEncounterState.PLANNED, create(draft.copy(plannedAt = now + 60000)).details.state)
        assertThrows(IllegalArgumentException::class.java) {
            create(draft.copy(state = HealthCareEncounterState.ATTENDED, attendedAt = now + 1))
        }
    }
    @Test fun editsPreserveOriginalSourceAndCreationTime() {
        val before = create()
        val changed = issue.copy(revision = 7, assessment = issue.assessment.copy(record = HealthCareRecordRef(UUID.randomUUID().toString(), 2)))
        val after = HealthCareEncounterPolicy.apply(changed, before, before.id, draft.copy(facility = "Synthetic clinic"), now + 2000)
        assertEquals(before.sourceRecord, after.sourceRecord); assertEquals(before.createdAt, after.createdAt)
        assertEquals(8, after.revision); assertEquals(now + 2000, after.updatedAt)
        val unknown = before.copy(sourceRecord = null)
        assertNull(HealthCareEncounterPolicy.apply(changed, unknown, unknown.id, draft, now).sourceRecord)
    }
    @Test fun ownershipCannotBeReassignedByEditing() {
        val before = create()
        assertThrows(HealthCareConflict::class.java) { HealthCareEncounterPolicy.apply(issue, before, UUID.randomUUID().toString(), draft, now) }
        assertThrows(HealthCareConflict::class.java) { HealthCareEncounterPolicy.apply(issue.copy(id = UUID.randomUUID().toString()), before, before.id, draft, now) }
    }
    @Test fun invalidTextDatesAndZonesAreRejectedWithoutTruncation() {
        listOf("", " ", "x".repeat(501), " leading").forEach { text ->
            assertThrows(IllegalArgumentException::class.java) { draft.copy(purpose = text) }
        }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(facility = "x".repeat(501)) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(note = "x".repeat(4001)) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(plannedAt = 0) }
        assertThrows(DateTimeException::class.java) { draft.copy(zone = "Invalid/Zone") }
    }
    @Test fun encodingKeepsUserProvenanceAndNeverPromotesItToClinicianVerification() {
        val value = create(draft.copy(state = HealthCareEncounterState.ATTENDED, attendedAt = now, zone = "America/New_York"))
        assertEquals(value, HealthCareEncounter.from(value.json()))
        val receipt = HealthCareEncounterReceipt(UUID.randomUUID().toString(), issue.revision, null, value)
        assertEquals(receipt, HealthCareEncounterReceipt.from(receipt.json()))
        assertThrows(IllegalArgumentException::class.java) { HealthCareEncounter.from(value.json().put("provenance", "verified_clinician")) }
    }
    @Test fun receiptsBindExpectedRevisionsAndClockSkewNeverReordersRevisionHistory() {
        val before = create(at = now + 1000)
        val updated = HealthCareEncounterPolicy.apply(issue.copy(revision = 3), before, before.id, draft, now)
        assertEquals(before.updatedAt, updated.updatedAt); assertEquals(4, updated.revision)
        assertThrows(IllegalArgumentException::class.java) { HealthCareEncounterReceipt(UUID.randomUUID().toString(), 2, 1, updated) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareEncounterReceipt(UUID.randomUUID().toString(), 3, 4, updated) }
    }
}
