package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitFollowUpAgentTest {
    private fun id() = UUID.randomUUID().toString()
    private val scope = HealthCareVisitFollowUpScope(id(), id(), 4, 2)
    private val grant = HealthCareDiscussionGrant(id(), id(), id(), 5, "settings", "privacy", "a".repeat(64), 100,
        "fixture", "model", "high", visitFollowUp = scope)
    @Test fun scopeRoundTripsWithoutEnablingOtherHealthAccess() {
        assertEquals(grant, HealthCareDiscussionGrant.from(grant.json()))
        assertEquals(scope, HealthCareVisitFollowUpScope.from(scope.json()))
        assertEquals(HealthCareDiscussionPolicy.researchTools - AgentConversationRecallTool.ID + HealthCareVisitFollowUpTool.ID,
            HealthCareDiscussionPolicy.tools(grant))
        listOf(HealthCarePlanTool.ID, HealthCareFeedbackTool.ID, HealthCareInstructionTool.ID, HealthCareHistoryTool.ID).forEach {
            assertFalse(it in HealthCareDiscussionPolicy.tools(grant))
        }
        assertThrows(IllegalArgumentException::class.java) { grant.copy(questionsShared = true) }
        assertThrows(IllegalArgumentException::class.java) { grant.copy(feedbackHistoryShared = true) }
        assertThrows(IllegalArgumentException::class.java) { grant.copy(researchAuthorizationId = id()) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareResearchAuthorization(id(), grant, "b".repeat(64)) }
        assertNull(HealthCareDiscussionGrant.from(grant.json().apply { remove("visit_followup_scope") }).visitFollowUp)
    }
    @Test fun noJournalHistoryLeaksIntoOrdinaryDiscussionOrSummary() {
        val entry = AgentTranscriptEntry(id(), AgentTranscriptRole.ASSISTANT, "private journal", 100,
            conversationId = grant.conversationId, turnId = grant.turnId)
        val other = entry.copy(id = id(), turnId = id(), text = "ordinary")
        val history = AgentConversationContext(grant.conversationId, entry.text, listOf(entry, other), true, globalContext = entry.text, trackingPaused = true)
        val scoped = HealthCareDiscussionPolicy.historyForGrant(history, grant.copy(turnId = id())) { if (it == grant.turnId) grant else null }
        assertEquals(listOf(entry), scoped.turns); assertEquals("", scoped.summary); assertEquals("", scoped.globalContext)
        listOf(grant.copy(destination = "b".repeat(64)), grant.copy(privacyVersion = "changed"),
            grant.copy(visitFollowUp = scope.copy(revision = scope.revision + 1))).forEach { changed ->
            assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, changed.copy(turnId = id())) { grant }.turns.isEmpty())
        }
        val ordinary = grant.copy(turnId = other.turnId, visitFollowUp = null, feedbackHistoryShared = true)
        val broad = HealthCareDiscussionPolicy.historyForGrant(history, ordinary.copy(turnId = id())) {
            if (it == grant.turnId) grant else ordinary
        }
        assertEquals(listOf(other), broad.turns); assertEquals("", broad.summary)
        assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, ordinary.copy(turnId = id())) { null }.turns.isEmpty())
    }
    @Test fun onlyExactPositiveCursorsAndSelectedEntryFieldsAreAccepted() {
        assertNull(HealthCareVisitFollowUpTool.cursor(mapOf("revision" to 5)))
        assertEquals(4, HealthCareVisitFollowUpTool.cursor(mapOf("revision" to 5, "before_revision" to 4)))
        listOf<Any>(0, -1, 1.5, Double.NaN, Double.POSITIVE_INFINITY, "4", true).forEach {
            assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpTool.cursor(mapOf("revision" to it)) }
        }
        listOf(mapOf("journal" to id()), mapOf("field" to "note"), mapOf("entry_revision" to 4, "field" to "dose"),
            mapOf("entry_revision" to 4, "field" to "note", "offset" to -1),
            mapOf("entry_revision" to 4, "field" to "note", "before_revision" to 3)).forEach {
            assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpTool.cursor(mapOf("revision" to 5) + it) }
        }
    }
    private fun row(revision: Int, note: String) = JSONObject().put("revision", revision).put("kind", "CHECK_IN")
        .put("note", note).put("needs_review", true).put("decision", JSONObject.NULL).put("source_review_required", true).put("resulting_state", "REVIEW")
    private fun page(vararg rows: JSONObject) = JSONObject().put("protocol", HealthCareVisitFollowUpTool.PROTOCOL)
        .put("revision", 10).put("journal_revision", 9).put("page_start", JSONObject.NULL).put("items", JSONArray(rows.toList()))
        .put("next", JSONObject.NULL).put("done", true)
    @Test fun compactionAdvancesOnlyAfterCompleteRows() {
        val data = page(row(9, "small"), row(8, "x".repeat(2000)))
        val compact = JSONObject(HealthCareHistoryObservation.compact(data.toString(), 1100)!!)
        assertEquals(1, compact.getJSONArray("items").length()); assertEquals(9, compact.getInt("next")); assertFalse(compact.getBoolean("done"))
    }
    @Test fun longEntryOffersExactChunkRecoveryWithoutSkippingIt() {
        val compact = JSONObject(HealthCareHistoryObservation.compact(page(row(9, "x".repeat(2000))).toString(), 1200)!!)
        assertEquals("followup_entry_requires_chunks", compact.getString("error")); assertEquals(9, compact.getInt("entry_revision"))
        assertEquals("note", compact.getJSONArray("fields").getString(0)); assertTrue(compact.isNull("next")); assertFalse(compact.getBoolean("done"))
        assertTrue(compact.getBoolean("needs_review")); assertTrue(compact.getBoolean("source_review_required"))
    }
    @Test fun tinyBudgetsNeverReturnBrokenJsonOrPretendCompletion() {
        val data = page(row(9, "x".repeat(2000)))
        listOf(2, 100, 300, 800, 1200).forEach {
            val compact = HealthCareHistoryObservation.compact(data.toString(), it)!!
            assertTrue(compact.length <= it); assertFalse(JSONObject(compact).optBoolean("done"))
        }
    }
    @Test fun promptRoutesAsHealthButDoesNotInventClinicalAuthority() {
        val snapshot = JSONObject().put("selected_visit_followup", JSONObject().put("revision", 5).put("journal_revision", 4).put("goal", "test")).toString()
        val prompt = HealthCareDiscussionPolicy.prompt("review", snapshot)
        assertTrue(HealthCareDiscussionPolicy.hasStructuredContext(prompt)); assertTrue(prompt.contains(HealthCareVisitFollowUpTool.ID))
        assertTrue(prompt.contains("read-only authority")); assertTrue(prompt.contains("No background sharing"))
    }
}
