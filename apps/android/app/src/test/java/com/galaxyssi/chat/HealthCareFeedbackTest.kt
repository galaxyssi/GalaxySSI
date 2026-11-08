package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareFeedbackTest {
    private val now = 1_793_000_000_000L
    private val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT,
        "Prepare questions", "Synthetic fixture", "https://example.test", HealthCareActionState.CONFIRMED,
        now + 60000, now + 120000, now)
    private val base = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "source",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6",
            setOf(HealthCareSignal.REPORT_HIGH)), actions = listOf(action))
    private val issue = base.copy(actions = listOf(action.copy(basis = HealthCareFollowUpPolicy.basis(base))))
    private fun feedback(kind: HealthCareFeedbackKind = HealthCareFeedbackKind.PARTIAL) = HealthCareFeedback(
        UUID.randomUUID().toString(), kind, "Synthetic execution feedback", now + 1,
        issue.actions.single().basis, HealthCareQuestionPolicy.scope(issue))
    private fun apply(kind: HealthCareFeedbackKind) = HealthCareFeedbackPolicy.apply(issue, action.id, feedback(kind))

    @Test fun partialAndBarrierPreserveActionWindowReminderAnchorAndMeasurement() {
        listOf(HealthCareFeedbackKind.PARTIAL, HealthCareFeedbackKind.BARRIER).forEach { kind ->
            val next = apply(kind)
            assertEquals(HealthCareActionState.CONFIRMED, next.actions.single().state)
            assertEquals("", next.actions.single().outcome)
            assertEquals(action.dueFrom, next.actions.single().dueFrom)
            assertEquals(action.dueUntil, next.actions.single().dueUntil)
            assertEquals(issue.assessment, next.assessment); assertEquals(issue.target, next.target)
            assertEquals(HealthCareStage.REASSESS, next.stage)
            assertEquals(HealthCareFollowUpPolicy.anchor(issue, issue.actions.single()),
                HealthCareFollowUpPolicy.anchor(next, next.actions.single()))
        }
    }
    @Test fun completionRecordsExecutionNotVerifiedImprovement() {
        val next = apply(HealthCareFeedbackKind.COMPLETED)
        assertEquals(HealthCareActionState.DONE, next.actions.single().state)
        assertEquals(next.actions.single().feedback!!.note, next.actions.single().outcome)
        assertEquals(issue.assessment, next.assessment)
        val model = HealthCareFeedbackPolicy.modelAction(next, next.actions.single()).getJSONObject("feedback")
        assertTrue(model.getBoolean("self_reported")); assertFalse(model.getBoolean("health_improvement_verified"))
        assertFalse(model.getBoolean("history_included")); assertTrue(model.getBoolean("plan_basis_current"))
    }
    @Test fun encodingPreservesLegacyActionsAndLatestFeedback() {
        assertFalse(action.json().has("feedback")); assertEquals(action, HealthCareAction.from(action.json()))
        HealthCareFeedbackKind.entries.forEach { kind ->
            val saved = apply(kind).actions.single()
            assertEquals(saved, HealthCareAction.from(saved.json()))
            val receipt = HealthCareFeedbackReceipt(issue.id, action.id, 2, action.description, saved.feedback!!)
            assertEquals(receipt, HealthCareFeedbackReceipt.from(receipt.json()))
        }
    }
    @Test fun staleScopeHidesFeedbackAndCompletionNoteFromModel() {
        val next = apply(HealthCareFeedbackKind.COMPLETED)
        val scoped = next.actions.single().copy(feedback = next.actions.single().feedback!!.copy(scope = "f".repeat(64)))
        val model = HealthCareFeedbackPolicy.modelAction(next, scoped)
        assertFalse(model.has("feedback")); assertFalse(model.has("outcome"))
        assertTrue(model.getBoolean("feedback_outside_current_scope"))
    }
    @Test fun changedSourcesRetainHistoryButDoNotClaimCurrentPlanBasis() {
        val next = apply(HealthCareFeedbackKind.BARRIER).copy(inputVersion = "new-measurement")
        val model = HealthCareFeedbackPolicy.modelAction(next, next.actions.single()).getJSONObject("feedback")
        assertFalse(model.getBoolean("plan_basis_current")); assertEquals(now + 1, model.getLong("recorded_at"))
    }
    @Test fun pausedTrackingIsNotResumedAndClosedOrUnknownActionsAreRejected() {
        assertEquals(HealthCareStage.PAUSED, HealthCareFeedbackPolicy.apply(issue.copy(stage = HealthCareStage.PAUSED), action.id, feedback()).stage)
        assertThrows(HealthCareConflict::class.java) { HealthCareFeedbackPolicy.apply(issue.copy(stage = HealthCareStage.CLOSED,
            reviewNote = "Reviewed", reviewedBy = "user"), action.id, feedback()) }
        assertThrows(HealthCareConflict::class.java) { HealthCareFeedbackPolicy.apply(issue, UUID.randomUUID().toString(), feedback()) }
        assertThrows(HealthCareConflict::class.java) { HealthCareFeedbackPolicy.apply(issue, action.id, feedback().copy(basis = "a".repeat(64))) }
        assertThrows(HealthCareConflict::class.java) { HealthCareFeedbackPolicy.apply(issue, action.id, feedback().copy(scope = "b".repeat(64))) }
    }
    @Test fun invalidNotesAndInconsistentActionStatesCannotBeDecoded() {
        listOf("", " ", "x".repeat(2001)).forEach { text ->
            assertThrows(IllegalArgumentException::class.java) { feedback().copy(note = text) }
        }
        assertThrows(IllegalArgumentException::class.java) { action.copy(feedback = feedback(HealthCareFeedbackKind.COMPLETED)) }
        assertThrows(IllegalArgumentException::class.java) { action.copy(state = HealthCareActionState.PROPOSED, feedback = feedback()) }
    }
    @Test fun feedbackChangesResearchTriggerOnceNotOnEveryClockTick() {
        val next = apply(HealthCareFeedbackKind.BARRIER)
        assertNotEquals(HealthCareResearchPolicy.trigger(issue, now), HealthCareResearchPolicy.trigger(next, now))
        assertEquals(HealthCareResearchPolicy.trigger(next, now), HealthCareResearchPolicy.trigger(next, now + 1000))
    }
}
