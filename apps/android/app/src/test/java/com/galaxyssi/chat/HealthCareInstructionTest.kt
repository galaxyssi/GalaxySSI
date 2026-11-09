package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareInstructionTest {
    private fun id() = UUID.randomUUID().toString()
    private fun link() = HealthCareDocumentLink(id(), id(), id(), 4, 3, 2, HealthCareDocumentRef(id(), "a".repeat(64), 1000, "application/pdf"), 100)
    private val page = HealthOcrPage(2, 200, 300, listOf(HealthOcrLine("Synthetic instruction", listOf(10, 10, 800, 100)),
        HealthOcrLine("Check the original")), recognition = HealthRecognition.PDF_TEXT)
    private fun source() = HealthCareInstructionSource.select(link(), page, 3, setOf(0, 1))
    @Test fun emptyAndPartiallyReviewedDraftsStayPending() {
        assertFalse(HealthCareInstructionDraft().reviewed)
        assertFalse(HealthCareInstructionDraft(fields = mapOf(HealthCareInstructionField.NAME to
            HealthCareInstructionValue("Synthetic item", HealthCareFieldReview.TRANSCRIBED))).reviewed)
    }
    @Test fun explicitlyUnstatedFieldsAreNotFabricatedOrTreatedAsCompleteInstructions() {
        val kind = HealthCareInstructionKind.MEDICATION
        val fields = HealthCareInstructionDraft(kind).required.associateWith { HealthCareInstructionValue(review = HealthCareFieldReview.NOT_STATED) }
        val value = HealthCareInstructionDraft(kind, fields)
        assertTrue(value.reviewed); assertEquals(value.required, value.missing)
        assertTrue(value.fields.values.all { it.text.isEmpty() })
        assertFalse(value.json().has("execute")); assertFalse(value.json().has("reminder"))
    }
    @Test fun checkedValuesMustBeExplicitAndUnstatedCannotCarryText() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionValue("", HealthCareFieldReview.TRANSCRIBED) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionValue("Synthetic", HealthCareFieldReview.NOT_STATED) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionValue(" leading") }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionValue("x".repeat(1001)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionDraft(fields = mapOf(HealthCareInstructionField.DOSE to HealthCareInstructionValue())) }
    }
    @Test fun selectedQuoteKeepsExactTextOrderPageAndRecognitionWithoutInventingConfidence() {
        val source = source()
        assertEquals("Synthetic instruction\nCheck the original", source.quote)
        assertEquals(listOf(0, 1), source.lines); assertEquals(2, source.original.page); assertEquals(3, source.original.pageCount)
        assertEquals(HealthRecognition.PDF_TEXT, source.recognition); assertFalse(source.json().has("confidence"))
        assertEquals(source, HealthCareInstructionSource.from(source.json()))
    }
    @Test fun wrongPageEmptySelectionOversizedQuoteAndInvalidBoxesFailClosed() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionSource.select(link(), page, 3, emptySet()) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionSource.select(link(), page, 3, setOf(2)) }
        val fixed = link().let { it.copy(source = it.source.copy(page = 1, pageCount = 3)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstructionSource.select(fixed, page, 3, setOf(0)) }
        assertThrows(IllegalArgumentException::class.java) { source().copy(quote = "x".repeat(8001)) }
        assertThrows(IllegalArgumentException::class.java) { source().copy(boxes = listOf(listOf(4, 5, 2, 3))) }
    }
    @Test fun sourceAndDraftRemainSeparateAndUserProvenanceCannotBecomeClinicianApproval() {
        val value = HealthCareInstruction(id(), id(), id(), 5, source(), HealthCareInstructionDraft(), 100, 100)
        assertEquals(value, HealthCareInstruction.from(value.json()))
        assertEquals("user_transcribed", value.json().getString("provenance"))
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstruction.from(value.json().put("provenance", "clinician_verified")) }
        val receipt = HealthCareInstructionReceipt(id(), 4, null, value)
        assertEquals(receipt, HealthCareInstructionReceipt.from(receipt.json()))
        assertThrows(IllegalArgumentException::class.java) { receipt.copy(expectedConcern = 5) }
        assertThrows(IllegalArgumentException::class.java) { receipt.copy(expectedInstruction = 5) }
    }
    @Test fun medicationFieldsRoundTripAndEveryFieldMustBeReviewedIndependently() {
        val required = HealthCareInstructionDraft(HealthCareInstructionKind.MEDICATION).required
        val fields = required.associateWith { HealthCareInstructionValue("Synthetic ${it.name}", HealthCareFieldReview.TRANSCRIBED) }
        val draft = HealthCareInstructionDraft(HealthCareInstructionKind.MEDICATION, fields)
        assertTrue(draft.reviewed); assertTrue(draft.missing.isEmpty())
        assertEquals(draft, HealthCareInstructionDraft.from(draft.json()))
        required.forEach { field -> assertFalse(draft.copy(fields = fields + (field to fields.getValue(field).copy(review = HealthCareFieldReview.UNREVIEWED))).reviewed) }
    }
}
