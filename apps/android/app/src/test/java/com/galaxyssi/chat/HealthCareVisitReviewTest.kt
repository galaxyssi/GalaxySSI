package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitReviewTest {
    private fun id() = UUID.randomUUID().toString()
    private val now = 1_793_000_000_000L
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 10, now, now, "fixture-source",
        HealthCareAssessment(HealthCareRecordRef(id(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val visit = HealthCareEncounter(id(), issue.id, 9, issue.assessment.record, now, now,
        HealthCareEncounterDraft("Synthetic visit", state = HealthCareEncounterState.ATTENDED, attendedAt = now))
    private val journal = HealthCareVisitFollowUpPolicy.apply(issue, visit, null,
        HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.START, goal = "Private synthetic journal goal"), id(), now).value
    private fun action() = HealthCareVisitReviewPolicy.confirm(issue, journal, visit, "Review journal", "User-chosen reminder", now)

    @Test fun referenceRoundTripDoesNotExposeJournalTextToPlanContext() {
        val action = action()
        assertEquals(action, HealthCareAction.from(action.json()))
        assertFalse(action.json().toString().contains(journal.goal))
        assertEquals(HealthCareActionState.CONFIRMED, action.state)
        assertNull(action.dueFrom); assertNull(action.instruction)
        assertEquals(HealthCareFollowUpPolicy.basis(issue), action.basis)
    }
    @Test fun checkinsDoNotInvalidateButGoalAndSourceRevisionsDo() {
        val ref = action().visitReview!!
        assertTrue(ref.matches(journal.copy(revision = journal.revision + 1, updatedAt = now + 1), visit))
        assertFalse(ref.matches(journal.copy(goal = "Changed goal"), visit))
        assertFalse(ref.matches(journal, visit.copy(revision = visit.revision + 1)))
        assertFalse(ref.copy(invalidated = true).matches(journal, visit))
    }
    @Test fun pausedArchivedOrUnacknowledgedJournalsCannotBeScheduled() {
        listOf(HealthCareVisitFollowUpState.PAUSED, HealthCareVisitFollowUpState.ARCHIVED).forEach { state ->
            assertThrows(HealthCareConflict::class.java) { HealthCareVisitReviewPolicy.confirm(issue, journal.copy(state = state), visit, "Review", "Chosen", now) }
        }
        assertThrows(HealthCareConflict::class.java) { HealthCareVisitReviewPolicy.confirm(issue, journal,
            visit.copy(revision = visit.revision + 1), "Review", "Chosen", now) }
        assertThrows(HealthCareConflict::class.java) { HealthCareVisitReviewPolicy.confirm(issue.copy(stage = HealthCareStage.PAUSED), journal, visit, "Review", "Chosen", now) }
    }
    @Test fun ownershipIsCheckedAndActionsHaveStableJournalScopedIds() {
        assertEquals(action().id, action().id)
        assertNotEquals(action().id, HealthCareVisitReviewPolicy.actionId(id()))
        assertThrows(HealthCareConflict::class.java) { HealthCareVisitReviewPolicy.confirm(issue.copy(id = id()), journal, visit, "Review", "Chosen", now) }
        assertThrows(HealthCareConflict::class.java) { HealthCareVisitReviewPolicy.confirm(issue, journal.copy(encounterId = id()), visit, "Review", "Chosen", now) }
    }
    @Test fun invalidationIsIdempotentAndPreservesHistory() {
        val action = action(); val before = issue.copy(actions = listOf(action))
        val after = HealthCareVisitReviewPolicy.invalidate(before) { it.journal == journal.id }
        assertTrue(after.actions.single().sourceInvalidated)
        assertEquals(action.state, after.actions.single().state)
        assertEquals(after, HealthCareVisitReviewPolicy.invalidate(after) { true })
        assertEquals(before, HealthCareVisitReviewPolicy.invalidate(before) { false })
    }
    @Test fun malformedOrClinicalIntervalReferencesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { action().copy(visitReview = null) }
        assertThrows(IllegalArgumentException::class.java) { action().copy(dueFrom = now, dueUntil = now + 1) }
        assertThrows(IllegalArgumentException::class.java) { action().visitReview!!.copy(goalDigest = "raw goal") }
        assertThrows(IllegalArgumentException::class.java) { action().copy(kind = HealthCareActionKind.LIFESTYLE) }
    }
}
