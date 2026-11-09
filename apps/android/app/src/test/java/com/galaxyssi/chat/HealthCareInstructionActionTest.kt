package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareInstructionActionTest {
    private fun id() = UUID.randomUUID().toString()
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 10, 100, 100, "source",
        HealthCareAssessment(HealthCareRecordRef(id(), 1), 100, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private fun instruction(kind: HealthCareInstructionKind = HealthCareInstructionKind.MEDICATION): HealthCareInstruction {
        val source = HealthCareInstructionSource(id(), HealthCareDocumentRef(id(), "a".repeat(64), 100, "application/pdf", 1, 1),
            HealthRecognition.PDF_TEXT, "Synthetic source only", listOf(0), emptyList(), false)
        return HealthCareInstruction(id(), issue.id, id(), 8, source, HealthCareInstructionDraft(kind,
            HealthCareInstructionDraft(kind).required.associateWith { HealthCareInstructionValue("Synthetic ${it.name}", HealthCareFieldReview.TRANSCRIBED) }), 100, 100)
    }
    @Test fun everyMedicationFieldMustBeExplicitlyCheckedNotMerelyMarkedUnstated() {
        val value = instruction()
        assertTrue(HealthCareInstructionActionPolicy.eligible(value))
        value.draft.required.forEach { field ->
            listOf(HealthCareInstructionValue(), HealthCareInstructionValue(review = HealthCareFieldReview.NOT_STATED)).forEach { item ->
                assertFalse(HealthCareInstructionActionPolicy.eligible(value.copy(draft = value.draft.copy(fields = value.draft.fields + (field to item)))))
            }
        }
    }
    @Test fun otherInstructionsKeepUnknownDatesWithoutInventingSchedules() {
        val value = instruction(HealthCareInstructionKind.REHABILITATION).let { it.copy(draft = it.draft.copy(fields = it.draft.fields +
            listOf(HealthCareInstructionField.START, HealthCareInstructionField.END, HealthCareInstructionField.FREQUENCY)
                .associateWith { HealthCareInstructionValue(review = HealthCareFieldReview.NOT_STATED) })) }
        val action = HealthCareInstructionActionPolicy.confirm(issue, value, 200)
        assertNull(action.dueFrom); assertNull(action.dueUntil)
        assertEquals(value.draft.fields.getValue(HealthCareInstructionField.NAME).text, action.description)
        assertEquals(value.draft.fields.getValue(HealthCareInstructionField.DETAILS).text, action.rationale)
        assertEquals(HealthCareActionState.CONFIRMED, action.state)
    }
    @Test fun actionReferencesRoundTripAndCannotBeInventedByGenericModelActions() {
        val value = instruction()
        val action = HealthCareInstructionActionPolicy.confirm(issue, value, 200)
        assertEquals(action, HealthCareAction.from(action.json()))
        assertEquals(action.id, HealthCareInstructionActionPolicy.confirm(issue, value, 300).id)
        assertThrows(IllegalArgumentException::class.java) { action.copy(instruction = null) }
        assertThrows(IllegalArgumentException::class.java) { action.copy(kind = HealthCareActionKind.LIFESTYLE) }
        assertThrows(IllegalArgumentException::class.java) { action.copy(evidenceId = id()) }
        assertFalse(action.instruction!!.matches(value.copy(revision = 9)))
        assertFalse(action.instruction.matches(value.copy(encounterId = id())))
        assertFalse(action.instruction.matches(value.copy(source = value.source.copy(original = value.source.original.copy(sha256 = "b".repeat(64))))))
    }
    @Test fun invalidationMovesOnlyTheAffectedActionToReviewAndDisarmsReminder() {
        val value = instruction(); val other = instruction()
        val action = HealthCareInstructionActionPolicy.confirm(issue, value, 200)
        val second = HealthCareInstructionActionPolicy.confirm(issue, other, 200)
        val current = issue.copy(actions = listOf(action, second))
        val permission = HealthPrivacyPolicy(version = "permission")
        val settings = HealthCareSettings(true, "settings")
        val reminder = HealthCareFollowUpPolicy.schedule(current, action, settings, permission, current.inputVersion, 1000, 200)
        val changed = HealthCareInstructionActionPolicy.invalidate(current) { it.instructionId == value.id }
        assertTrue(changed.actions.first().instruction!!.invalidated); assertEquals(second, changed.actions.last())
        assertFalse(HealthCareFollowUpPolicy.current(reminder, changed, settings, permission, changed.inputVersion))
        assertEquals(1, HealthCareAgenda.item(changed, changed.actions.first(), reminder).bucket)
        assertEquals(current.assessment, changed.assessment); assertEquals(current.stage, changed.stage)
    }
    @Test fun pausedClosedAndWrongConcernCannotConfirmClinicalActions() {
        val value = instruction()
        assertThrows(HealthCareConflict::class.java) { HealthCareInstructionActionPolicy.confirm(issue.copy(stage = HealthCareStage.PAUSED), value, 200) }
        assertThrows(HealthCareConflict::class.java) { HealthCareInstructionActionPolicy.confirm(issue.copy(stage = HealthCareStage.CLOSED,
            reviewNote = "Synthetic review", reviewedBy = "user"), value, 200) }
        assertThrows(HealthCareConflict::class.java) { HealthCareInstructionActionPolicy.confirm(issue.copy(id = id()), value, 200) }
    }
}
