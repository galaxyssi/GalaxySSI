package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareQuestionTest {
    private fun id() = UUID.randomUUID().toString()
    private val ref = HealthCareRecordRef(id(), 1)
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 1, 100, 100, "source-v1",
        HealthCareAssessment(ref, 100, "5.9", "mmol/L", "", setOf(HealthCareSignal.GLUCOSE_CONTEXT)))
    private fun question(key: String = "sample.notes") = HealthCareQuestion(id(), issue.id, key, "A necessary question?",
        "Affects the next decision", HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue), ref, 100, id(), 1, 100, 100)
    @Test fun encryptedPayloadRoundTripRetainsPurposeAndRecordIdentity() {
        val q = question().copy(state = HealthCareQuestionState.ANSWERED, answer = "self report")
        assertEquals(q, HealthCareQuestion.from(q.json()))
        assertEquals(issue.copy(questionVersion = ""), HealthCareConcern.from(issue.json()))
    }
    @Test fun unknownNegativeAndZeroRemainDifferent() {
        val complete = issue.copy(context = HealthCareContext(ref, adult = HealthCareTruth.YES,
            pregnant = HealthCareTruth.NO, fastingHours = 0, confirmedAt = 120))
        val facts = HealthCareQuestionPolicy.known(complete, null)
        assertEquals("NO", facts["context.pregnant"]); assertEquals("0", facts["context.fasting_hours"])
        assertFalse(facts.containsKey("context.diagnosed_diabetes"))
        assertTrue(HealthCareQuestionPolicy.known(complete.copy(assessment = issue.assessment.copy(record = ref.copy(revision = 2))), null).isEmpty())
    }
    @Test fun existingSavedFactAnswersTheQuestionWithoutAnotherForm() {
        val q = question("context.pregnant")
        val view = HealthCareQuestionPolicy.view(q, issue, mapOf(q.key to "NO"))
        assertEquals("ANSWERED", view.getString("state")); assertFalse(view.getBoolean("ask_again"))
        assertEquals("NO", view.getString("saved_fact")); assertTrue(view.isNull("reviewed_answer"))
    }
    @Test fun explicitUserReplyIsSeparateFromClinicalOrProfileFacts() {
        val q = question().copy(state = HealthCareQuestionState.ANSWERED, answer = "回答")
        val view = HealthCareQuestionPolicy.view(q, issue, emptyMap())
        assertEquals("回答", view.getString("reviewed_answer")); assertEquals("ANSWERED", view.getString("state"))
        assertFalse(view.getBoolean("ask_again"))
    }
    @Test fun sourceChangeHidesOldAnswerAndExplainsTheNeedToReview() {
        val q = question().copy(state = HealthCareQuestionState.ANSWERED, answer = "obsolete")
        val view = HealthCareQuestionPolicy.view(q, issue.copy(assessment = issue.assessment.copy(record = ref.copy(revision = 2))), emptyMap())
        assertEquals("STALE", view.getString("state")); assertTrue(view.isNull("reviewed_answer"))
        assertFalse(view.toString().contains("obsolete")); assertTrue(view.getString("recheck_reason").isNotBlank())
    }
    @Test fun declinedAndDeferredDoNotReopenAfterSourceChanges() {
        listOf(HealthCareQuestionState.DEFERRED, HealthCareQuestionState.DECLINED).forEach { state ->
            val q = question().copy(state = state)
            listOf(issue, issue.copy(assessment = issue.assessment.copy(record = ref.copy(revision = 2)))).forEach { current ->
                val view = HealthCareQuestionPolicy.view(q, current, emptyMap())
                assertTrue(view.getBoolean("user_reopen_required")); assertFalse(view.getBoolean("ask_again"))
            }
        }
    }
    @Test fun contradictoryReplyDoesNotOverwriteSavedFact() {
        val q = question("context.pregnant").copy(state = HealthCareQuestionState.ANSWERED, answer = "YES")
        val view = HealthCareQuestionPolicy.view(q, issue, mapOf(q.key to "NO"))
        assertEquals("CONFLICT", view.getString("state")); assertEquals("YES", view.getString("reviewed_answer"))
        assertEquals("NO", view.getString("saved_fact")); assertFalse(view.getBoolean("ask_again"))
    }
    @Test fun otherConcernsAndWithdrawnSelectionsCannotSupplyAnswers() {
        val q = question()
        assertThrows(IllegalArgumentException::class.java) { HealthCareQuestionPolicy.view(q, issue.copy(id = id()), emptyMap()) }
        val scope = HealthCareProfileScope("", setOf(HealthProfileField.HEIGHT), emptySet())
        val changed = issue.copy(profileLink = HealthCareProfileLink(scope, HealthProfileStamp("", mapOf("field:HEIGHT" to "v1"))))
        assertThrows(IllegalArgumentException::class.java) { HealthCareQuestionPolicy.view(q, changed, emptyMap()) }
    }
    @Test fun userAnswerInvalidatesActionsButNotOtherQuestionSources() {
        val updated = issue.copy(questionVersion = id())
        assertEquals(HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.basis(updated))
        assertNotEquals(HealthCareFollowUpPolicy.basis(issue), HealthCareFollowUpPolicy.basis(updated))
        assertEquals(updated, HealthCareConcern.from(updated.json()))
    }
    @Test fun permissionOrRefreshClocksDoNotInvalidateUnchangedAnswers() {
        val q = question().copy(state = HealthCareQuestionState.ANSWERED, answer = "still current")
        val refreshed = issue.copy(inputVersion = "permission-clock-changed", revision = 2, updatedAt = 200)
        assertEquals(HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.basis(refreshed))
        assertEquals("ANSWERED", HealthCareQuestionPolicy.view(q, refreshed, emptyMap()).getString("state"))
    }
    @Test fun oldConsentCannotExpandToQuestionAnswersOrQuestionTools() {
        val old = HealthCareDiscussionGrant(id(), id(), issue.id, 1, "settings", "privacy", "a".repeat(64),
            100, "fixture", "fixture-model", "high")
        val legacyJson = old.json().apply { remove("questions_shared") }
        assertFalse(HealthCareDiscussionGrant.from(legacyJson).questionsShared)
        assertTrue(HealthCareDiscussionPolicy.questionScopeCurrent(old, issue))
        assertFalse(HealthCareDiscussionPolicy.questionScopeCurrent(old, issue.copy(questionVersion = id())))
        assertTrue(HealthCareDiscussionPolicy.tools(old).intersect(HealthCareQuestionTools.ids).isEmpty())
        val disclosed = old.copy(questionsShared = true, userInputDigest = AgentNativeJsonCodec.sha256("user input"))
        assertEquals(disclosed, HealthCareDiscussionGrant.from(disclosed.json()))
        assertTrue(HealthCareDiscussionPolicy.tools(disclosed).containsAll(HealthCareQuestionTools.ids))
        val consent = HealthCareResearchAuthorization(id(), old, "b".repeat(64))
        assertFalse(consent.permits(disclosed.copy(researchAuthorizationId = consent.id)))
        assertTrue(consent.copy(scope = disclosed).permits(disclosed.copy(researchAuthorizationId = consent.id)))
    }
    @Test fun incompletePagesAreNeverPresentedAsAllQuestions() {
        val result = HealthCareQuestionPolicy.snapshot(HealthCareQuestionPage(listOf(question()), id()), issue, null)
        assertFalse(result.getBoolean("done")); assertFalse(result.getBoolean("writes_modify_measurements_or_profile"))
        assertEquals(1, result.getJSONArray("items").length())
    }
    @Test fun invalidAnswersKeysAndStatusesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { question().copy(state = HealthCareQuestionState.ANSWERED) }
        assertThrows(IllegalArgumentException::class.java) { question().copy(answer = "hidden answer") }
        assertThrows(IllegalArgumentException::class.java) { question("a key with spaces") }
        assertThrows(IllegalArgumentException::class.java) { question().copy(purpose = "") }
    }
    @Test fun toolSchemaRejectsPatientSelectorsAndModelWrittenAnswers() {
        var calls = 0
        val registry = AgentNativeToolRegistry().registerAll(HealthCareQuestionTools.definitions { _, _, _ -> calls++; JSONObject().put("ok", true) })
        val input = mapOf("key" to "sample.notes", "question" to "Why?", "purpose" to "Decision")
        registry.invoke(HealthCareQuestionTools.PROPOSE, input + ("answer" to "invented"), AgentNativeToolInvocationContext())
        registry.invoke(HealthCareQuestionTools.READ, mapOf("patient" to "other"), AgentNativeToolInvocationContext())
        assertEquals(0, calls)
        registry.invoke(HealthCareQuestionTools.READ, emptyMap(), AgentNativeToolInvocationContext())
        assertEquals(1, calls)
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(HealthCareQuestionTools.PROPOSE))
        assertTrue(HealthCareDiscussionPolicy.discussionTools.containsAll(HealthCareQuestionTools.ids))
    }
    @Test fun compactionRetainsWholeQuestionsAndDoesNotSkipUndeliveredRows() {
        val rows = (1..8).map { question().copy(state = HealthCareQuestionState.ANSWERED, answer = "a".repeat(300)) }
        val source = HealthCareQuestionPolicy.snapshot(HealthCareQuestionPage(rows, null), issue, null)
            .put("protocol", HealthCareQuestionObservation.PROTOCOL).put("page_start", JSONObject.NULL)
        val result = JSONObject(HealthCareHistoryObservation.compact(source.toString(), 2500)!!)
        val shown = result.getJSONArray("items")
        assertTrue(shown.length() in 1 until rows.size); assertFalse(result.getBoolean("done"))
        assertEquals(rows[shown.length() - 1].id, result.getString("next"))
        assertEquals("a".repeat(300), shown.getJSONObject(0).getString("reviewed_answer"))
        val tiny = JSONObject(HealthCareHistoryObservation.compact(source.toString(), 500)!!)
        assertTrue(tiny.getBoolean("read_again")); assertTrue(tiny.isNull("next")); assertFalse(tiny.getBoolean("done"))
    }
}
