package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareFeedbackToolTest {
    private val now = 1_793_000_000_000L
    private val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT,
        "Synthetic action", "Fixture", "https://example.test", HealthCareActionState.CONFIRMED, confirmedAt = now)
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 40, now, now, "source",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6",
            setOf(HealthCareSignal.REPORT_HIGH)), actions = listOf(action))
    private fun receipt(revision: Int = 39, note: String = "Synthetic difficulty") = HealthCareFeedbackReceipt(
        issue.id, action.id, revision, action.description, HealthCareFeedback(UUID.randomUUID().toString(),
            HealthCareFeedbackKind.BARRIER, note, now - revision, HealthCareFollowUpPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue)))
    private fun grant() = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id,
        issue.revision, "settings", "privacy", "a".repeat(64), now, "local-llm", "fixture", "high")
    private fun observation(rows: List<JSONObject>) = JSONObject().put("protocol", HealthCareFeedbackObservation.PROTOCOL)
        .put("input_version", issue.inputVersion).put("revision", issue.revision).put("items", JSONArray(rows))
        .put("page_start", JSONObject.NULL).put("next", JSONObject.NULL).put("done", true).put("health_improvement_verified", false)

    @Test fun oldAndResearchGrantsDoNotGainHistoryAuthority() {
        val old = grant()
        assertFalse(HealthCareDiscussionGrant.from(old.json().apply { remove("feedback_history_shared") }).feedbackHistoryShared)
        assertFalse(HealthCareFeedbackTool.ID in HealthCareDiscussionPolicy.tools(old))
        val allowed = old.copy(feedbackHistoryShared = true)
        assertEquals(allowed, HealthCareDiscussionGrant.from(allowed.json()))
        assertTrue(HealthCareFeedbackTool.ID in HealthCareDiscussionPolicy.tools(allowed))
        assertFalse(HealthCareFeedbackTool.ID in HealthCareDiscussionPolicy.tools(allowed.copy(researchAuthorizationId = UUID.randomUUID().toString())))
        assertFalse(JSONObject(HealthCareDiscussionPolicy.snapshot(issue)).getJSONObject("feedback_history").getBoolean("authorized"))
        assertTrue(JSONObject(HealthCareDiscussionPolicy.snapshot(issue, feedbackHistoryShared = true))
            .getJSONObject("feedback_history").getBoolean("authorized"))
    }
    @Test fun cursorRequiresExactIntegersAndCannotSelectOtherPeopleOrActions() {
        val input = mapOf("input_version" to issue.inputVersion, "revision" to issue.revision)
        assertNull(HealthCareFeedbackTool.cursor(input))
        assertEquals(20, HealthCareFeedbackTool.cursor(input + ("before_revision" to 20)))
        listOf<Any?>(null, "20", 0, -1, 1.2, Double.NaN, Double.POSITIVE_INFINITY, Long.MAX_VALUE).forEach { value ->
            assertThrows(IllegalArgumentException::class.java) { HealthCareFeedbackTool.cursor(input + ("before_revision" to value)) }
            assertThrows(IllegalArgumentException::class.java) { HealthCareFeedbackTool.cursor(input + ("revision" to value)) }
        }
        listOf("profile", "concern", "action_id", "filter", "note").forEach { key ->
            assertThrows(IllegalArgumentException::class.java) { HealthCareFeedbackTool.cursor(input + (key to "other")) }
        }
    }
    @Test fun nativeRegistryExposesReadOnlyPhoneToolWithStrictSchema() {
        var called = false
        val definition = HealthCareFeedbackTool.definition { _, input -> HealthCareFeedbackTool.cursor(input); called = true; JSONObject() }
        val registry = AgentNativeToolRegistry().register(definition)
        val input = mapOf("input_version" to issue.inputVersion, "revision" to issue.revision)
        registry.invoke(HealthCareFeedbackTool.ID, input + ("profile" to "other"), AgentNativeToolInvocationContext())
        assertFalse(called)
        registry.invoke(HealthCareFeedbackTool.ID, input, AgentNativeToolInvocationContext())
        assertTrue(called)
        assertEquals(AgentNativeToolEffect.READ_ONLY, definition.descriptor.effect)
        assertEquals(AgentNativeToolLocation.PHONE, definition.descriptor.location)
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(HealthCareFeedbackTool.ID))
    }
    @Test fun feedbackRetainsMeaningWithoutClaimingImprovementOrExecutionDate() {
        val saved = receipt()
        val row = HealthCareFeedbackTool.modelRow(issue, saved)
        assertEquals(saved.feedback.note, row.getString("note"))
        assertEquals(saved.feedback.recordedAt, row.getLong("recorded_at"))
        assertTrue(row.getBoolean("self_reported")); assertFalse(row.getBoolean("health_improvement_verified"))
        assertTrue(row.getBoolean("plan_basis_current")); assertTrue(row.getBoolean("action_in_current_plan"))
        assertFalse(HealthCareFeedbackTool.modelRow(issue.copy(inputVersion = "new"), saved).getBoolean("plan_basis_current"))
        assertFalse(HealthCareFeedbackTool.modelRow(issue.copy(actions = emptyList()), saved).getBoolean("action_in_current_plan"))
        assertThrows(IllegalArgumentException::class.java) { HealthCareFeedbackTool.modelRow(issue, saved.copy(concernId = UUID.randomUUID().toString())) }
    }
    @Test fun withdrawnScopeRedactsTheWholeRowButPreservesPagination() {
        val saved = receipt().let { it.copy(feedback = it.feedback.copy(scope = "b".repeat(64))) }
        val row = HealthCareFeedbackTool.modelRow(issue, saved)
        assertEquals(setOf("revision", "redacted", "reason"), row.keys().asSequence().toSet())
        assertTrue(row.getBoolean("redacted")); assertEquals(saved.revision, row.getInt("revision"))
        assertFalse(row.toString().contains(saved.actionTitle)); assertFalse(row.toString().contains(saved.feedback.note))
    }
    @Test fun invalidatedInstructionRequiresReviewEvenWhenMeasurementBasisIsUnchanged() {
        val ref = HealthCareInstructionActionRef(UUID.randomUUID().toString(), 2, UUID.randomUUID().toString(),
            UUID.randomUUID().toString(), HealthCareDocumentRef(UUID.randomUUID().toString(), "a".repeat(64), 100,
                "application/pdf", 1, 1), invalidated = true)
        val clinical = action.copy(kind = HealthCareActionKind.CLINICAL_INSTRUCTION, instruction = ref)
        val row = HealthCareFeedbackTool.modelRow(issue.copy(actions = listOf(clinical)), receipt())
        assertTrue(row.getBoolean("plan_basis_current")); assertTrue(row.getBoolean("action_requires_review"))
        assertTrue(row.getBoolean("instruction_invalidated")); assertFalse(row.getBoolean("instruction_source_verified"))
        assertFalse(row.toString().contains(ref.original.originalId))
    }
    @Test fun compactedObservationKeepsWholeRowsAndCorrectResumeRevision() {
        val raw = observation((39 downTo 10).map { HealthCareFeedbackTool.modelRow(issue, receipt(it)) }).toString()
        val compact = AgentPlannerObservation.sanitize(AgentSessionPersistencePolicy.compactActionText(raw), 1200)!!
        val out = JSONObject(compact); val rows = out.getJSONArray("items")
        assertTrue(compact.length <= 1200); assertTrue(rows.length() in 1..29); assertFalse(out.getBoolean("done"))
        assertEquals(rows.getJSONObject(rows.length() - 1).getInt("revision"), out.getInt("next"))
        assertEquals("Synthetic difficulty", rows.getJSONObject(0).getString("note"))
        assertEquals(compact, HealthCareHistoryObservation.compact(compact, 1200))
    }
    @Test fun oversizedSingleNoteDoesNotAdvanceOrReportCompletion() {
        val raw = observation(listOf(HealthCareFeedbackTool.modelRow(issue, receipt(note = "x".repeat(2000)))))
            .put("page_start", 40).toString()
        val out = JSONObject(HealthCareHistoryObservation.compact(raw, 650)!!)
        assertEquals(40, out.getInt("next")); assertFalse(out.getBoolean("done")); assertFalse(out.has("items"))
        assertTrue(out.getBoolean("read_again")); assertTrue(out.getBoolean("retry_requires_larger_budget"))
    }
    @Test fun completeEmptyPagesReceiptsAndTinyBudgetsRemainWellFormed() {
        val empty = observation(emptyList()).toString()
        assertEquals(empty, HealthCareHistoryObservation.compact(empty, 1200))
        val envelope = JSONObject().put("invocation_id", "fixture").put("tool_id", HealthCareFeedbackTool.ID).put("status", "success")
        val raw = observation((39 downTo 10).map { HealthCareFeedbackTool.modelRow(issue, receipt(it)) })
            .put("_observation_receipt", envelope).toString()
        assertEquals(envelope.toString(), JSONObject(HealthCareHistoryObservation.compact(raw, 1600, true)!!)
            .getJSONObject("_observation_receipt").toString())
        assertEquals("{}", HealthCareHistoryObservation.compact(raw, 2)); assertEquals("", HealthCareHistoryObservation.compact(raw, 0))
    }
}
