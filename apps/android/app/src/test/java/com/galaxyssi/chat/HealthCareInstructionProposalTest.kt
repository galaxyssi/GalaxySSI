package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareInstructionProposalTest {
    private fun id() = UUID.randomUUID().toString()
    private fun objectMap(j: JSONObject): AgentNativeJsonObject = j.keys().asSequence().associateWith {
        j.get(it).let { v -> if (v is JSONObject) objectMap(v) else v }
    }
    private val source = HealthCareInstructionSource(id(), HealthCareDocumentRef(id(), "a".repeat(64), 1000, "application/pdf", 2, 3),
        HealthRecognition.PDF_TEXT, "合成医嘱：复查记录\n检查既往结果；日期未定", listOf(0, 1), emptyList(), false)
    private val value = HealthCareInstruction(id(), id(), id(), 4, source, HealthCareInstructionDraft(), 100, 100)
    private val grant = HealthCareDiscussionGrant(id(), id(), value.concernId, 4, "settings", "privacy", "b".repeat(64),
        100, "fixture", "fixture", "high", instruction = HealthCareInstructionScope.of(value))
    private fun input(kind: HealthCareInstructionKind = HealthCareInstructionKind.FOLLOW_UP): AgentNativeJsonObject = mapOf(
        "kind" to kind.name, "fields" to HealthCareInstructionDraft(kind).required.associate { field -> field.name to when (field) {
            HealthCareInstructionField.NAME -> mapOf("quote" to "复查记录", "certainty" to "QUOTED")
            HealthCareInstructionField.DETAILS -> mapOf("quote" to "检查既往结果", "certainty" to "UNCERTAIN")
            else -> mapOf("quote" to "", "certainty" to "NOT_FOUND")
        } })
    private fun parse(input: AgentNativeJsonObject = input(), selected: HealthCareInstruction = value,
        scope: HealthCareDiscussionGrant = grant) = HealthCareInstructionProposal.parse(scope, selected, input, 101)
    @Test fun exactExcerptsRoundTripButEveryFieldStaysUnreviewed() {
        val proposal = parse()
        assertEquals(proposal, HealthCareInstructionProposal.from(proposal.json()))
        assertTrue(proposal.draft.fields.values.all { it.review == HealthCareFieldReview.UNREVIEWED })
        assertFalse(proposal.draft.reviewed); assertFalse(HealthCareInstructionActionPolicy.eligible(value.copy(draft = proposal.draft)))
        assertEquals(HealthCareExtractionCertainty.NOT_FOUND, proposal.fields.getValue(HealthCareInstructionField.START).certainty)
    }
    @Test fun missingFieldsAndInventedDoseOrDateCannotEnterProposal() {
        val raw = JSONObject(input())
        raw.getJSONObject("fields").remove("START")
        assertThrows(IllegalArgumentException::class.java) { parse(objectMap(raw)) }
        listOf("Tomorrow", "5 mg", "转译而非原文").forEach { invented ->
            val changed = JSONObject(input())
            changed.getJSONObject("fields").getJSONObject("START").put("quote", invented).put("certainty", "QUOTED")
            assertThrows(IllegalArgumentException::class.java) { parse(objectMap(changed)) }
        }
    }
    @Test fun modelCannotSubmitReviewedOrScheduledFlags() {
        assertThrows(IllegalArgumentException::class.java) { parse(input() + ("confirmed" to true)) }
        val raw = JSONObject(input()); raw.getJSONObject("fields").getJSONObject("NAME").put("review", "TRANSCRIBED")
        assertThrows(IllegalArgumentException::class.java) { parse(objectMap(raw)) }
    }
    @Test fun blurrySourceForcesUncertaintyAndDoesNotHideMissingFields() {
        val blurry = value.copy(source = source.copy(blurry = true))
        val result = parse(selected = blurry, scope = grant.copy(instruction = HealthCareInstructionScope.of(blurry)))
        assertEquals(HealthCareExtractionCertainty.UNCERTAIN, result.fields.getValue(HealthCareInstructionField.NAME).certainty)
        assertEquals(HealthCareExtractionCertainty.NOT_FOUND, result.fields.getValue(HealthCareInstructionField.START).certainty)
    }
    @Test fun sourceRevisionOwnerAndReviewedFieldsCannotBeReplaced() {
        listOf(value.copy(revision = 5), value.copy(concernId = id()), value.copy(source = source.copy(quote = "Changed")),
            value.copy(draft = HealthCareInstructionDraft(fields = mapOf(HealthCareInstructionField.NAME to
                HealthCareInstructionValue("复查记录", HealthCareFieldReview.TRANSCRIBED))))).forEach {
            assertThrows(HealthCareConflict::class.java) { parse(selected = it) }
        }
    }
    @Test fun sourceConsentCannotEscalateIntoStandingResearchOrArchiveAccess() {
        assertEquals(grant, HealthCareDiscussionGrant.from(grant.json()))
        assertEquals(setOf(AgentToolDiscoveryTools.ID, AgentToolInspectionTools.DESCRIBE, HealthCareInstructionTool.ID), HealthCareDiscussionPolicy.tools(grant))
        assertThrows(IllegalArgumentException::class.java) { grant.copy(feedbackHistoryShared = true) }
        assertThrows(IllegalArgumentException::class.java) { grant.copy(questionsShared = true) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareResearchAuthorization(id(), grant, "c".repeat(64)) }
    }
    @Test fun payloadContainsOnlySelectedSourceAndTransportRecognizesIt() {
        val snapshot = HealthCareInstructionTool.snapshot(value)
        assertEquals(setOf("selected_instruction"), JSONObject(snapshot).keys().asSequence().toSet())
        val prompt = HealthCareDiscussionPolicy.prompt("整理", snapshot)
        assertTrue(HealthCareDiscussionPolicy.hasStructuredContext(prompt))
        assertTrue(prompt.contains(HealthCareInstructionTool.ID)); assertFalse(prompt.contains(value.id))
        assertFalse(snapshot.contains(source.original.sha256)); assertFalse(snapshot.contains("profile"))
    }
    @Test fun medicationRequiresAllFieldsAndNeverNormalizesUnits() {
        val result = parse(input(HealthCareInstructionKind.MEDICATION))
        assertEquals(8, result.fields.size)
        assertFalse(result.draft.reviewed)
        assertFalse(HealthCareInstructionActionPolicy.eligible(value.copy(draft = result.draft)))
    }
    @Test fun certaintyAndQuoteMustAgree() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareExtractedField("", HealthCareExtractionCertainty.QUOTED) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareExtractedField("present", HealthCareExtractionCertainty.NOT_FOUND) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareExtractedField(" leading", HealthCareExtractionCertainty.UNCERTAIN) }
    }
    @Test fun modelAssistedProvenanceRemainsDistinctFromUserAndClinician() {
        val edited = value.copy(draft = parse().draft, modelProposalId = grant.turnId)
        assertEquals(edited, HealthCareInstruction.from(edited.json()))
        assertEquals("model_assisted_transcription", edited.json().getString("provenance"))
        assertThrows(IllegalArgumentException::class.java) { HealthCareInstruction.from(edited.json().put("provenance", "clinician_verified")) }
    }
    @Test fun sourceTurnsCannotBeRecalledThroughBroaderHistoryOrCompactedSummaries() {
        val original = AgentTranscriptEntry(id(), AgentTranscriptRole.ASSISTANT, source.quote, 100,
            conversationId = grant.conversationId, turnId = grant.turnId)
        val plain = original.copy(id = id(), turnId = id(), text = "Ordinary authorized feedback")
        val history = AgentConversationContext(grant.conversationId, source.quote, listOf(original, plain), true,
            globalContext = source.quote, trackingPaused = true)
        val extract = grant.copy(turnId = id())
        assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, extract) { grant }.turns.isEmpty())
        val broad = grant.copy(turnId = id(), instruction = null, feedbackHistoryShared = true)
        val filtered = HealthCareDiscussionPolicy.historyForGrant(history, broad) { if (it == grant.turnId) grant else null }
        assertEquals(listOf(plain), filtered.turns); assertEquals("", filtered.summary); assertEquals("", filtered.globalContext)
        assertEquals("", HealthCareDiscussionPolicy.historyForGrant(history.copy(turns = listOf(plain)), broad) { null }.summary)
    }
}
