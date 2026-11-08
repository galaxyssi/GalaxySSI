package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareAnswerTest {
    private fun id() = UUID.randomUUID().toString()
    private val ref = HealthCareRecordRef(id(), 1)
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 1, 100, 100, "v1",
        HealthCareAssessment(ref, 100, "5.9", "mmol/L", "", setOf(HealthCareSignal.GLUCOSE_CONTEXT)))
    private val grant = HealthCareDiscussionGrant(id(), id(), issue.id, 1, "s1", "p1", "a".repeat(64), 100,
        "fixture", "fixture-model", "high", questionsShared = true, userInputDigest = AgentNativeJsonCodec.sha256("没有，持续了两天。"))
    private val entry = AgentTranscriptEntry(id(), AgentTranscriptRole.USER, "没有，持续了两天。", 100,
        conversationId = grant.conversationId, turnId = grant.turnId)
    private val question = HealthCareQuestion(id(), issue.id, "sample.notes", "Question?", "Decision purpose",
        HealthCareQuestionPolicy.basis(issue), HealthCareQuestionPolicy.scope(issue), ref, 100, id(), 1, 100, 100)
    private val draft = HealthCareAnswerDraft(id(), grant, question.id, 1, question.basis, question.scope,
        entry.id, "没有", "没有", 100)
    private val settings = HealthCareSettings(true, "s1")
    private val privacy = HealthPrivacyPolicy(version = "p1")
    @Test fun exactNegativeUserQuoteIsNotMissing() {
        assertTrue(HealthCareAnswerPolicy.userSource(grant, entry, "没有"))
        assertFalse(HealthCareAnswerPolicy.userSource(grant, entry, "有".repeat(3)))
        assertFalse(HealthCareAnswerPolicy.userSource(grant, entry, ""))
    }
    @Test fun foreignTurnConversationAndModelProseCannotBecomeUserAnswers() {
        listOf(entry.copy(turnId = id()), entry.copy(conversationId = id()), entry.copy(role = AgentTranscriptRole.ASSISTANT),
            entry.copy(role = AgentTranscriptRole.PROCESS), entry.copy(text = "没有，持续了一年。")).forEach {
            assertFalse(HealthCareAnswerPolicy.userSource(grant, it, "没有"))
        }
        assertFalse(HealthCareAnswerPolicy.userSource(grant, null, "没有"))
    }
    @Test fun legacyAndBackgroundGrantsCannotStageHumanAnswers() {
        listOf(grant.copy(userInputDigest = ""), grant.copy(questionsShared = false), grant.copy(researchAuthorizationId = id())).forEach {
            assertFalse(HealthCareAnswerPolicy.userSource(it, entry, "没有"))
            assertFalse(HealthCareAnswerTool.ID in HealthCareDiscussionPolicy.tools(it))
        }
        assertTrue(HealthCareAnswerTool.ID in HealthCareDiscussionPolicy.tools(grant))
        assertEquals("", HealthCareDiscussionGrant.from(grant.json().apply { remove("user_input_digest") }).userInputDigest)
    }
    @Test fun pendingDraftIsPersistedSeparatelyAndRoundTrips() {
        assertEquals(draft, HealthCareAnswerDraft.from(draft.json()))
        assertEquals(HealthCareAnswerState.PENDING, draft.state)
        assertEquals("", draft.reviewedAnswer)
        assertTrue(runCatching { draft.copy(state = HealthCareAnswerState.ACCEPTED) }.isFailure)
        assertEquals(draft.copy(state = HealthCareAnswerState.ACCEPTED, reviewedAt = 101, reviewedAnswer = "edited"),
            HealthCareAnswerDraft.from(draft.copy(state = HealthCareAnswerState.ACCEPTED, reviewedAt = 101, reviewedAnswer = "edited").json()))
    }
    @Test fun permissionAndSourceChangesInvalidateAReview() {
        assertTrue(HealthCareAnswerPolicy.current(draft, issue, question, settings, privacy))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue, question, settings.copy(version = "s2"), privacy))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue, question, settings, privacy.copy(version = "p2")))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue, question, settings, privacy.copy(profile = false)))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue, question.copy(revision = 2), settings, privacy))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue.copy(assessment = issue.assessment.copy(record = ref.copy(revision = 2))), question, settings, privacy))
    }
    @Test fun otherAnswersDoNotInvalidateAnUnrelatedDraftAndPauseDoesNotResumeIt() {
        assertTrue(HealthCareAnswerPolicy.current(draft, issue.copy(revision = 2, questionVersion = id(), stage = HealthCareStage.PAUSED), question, settings, privacy))
        assertFalse(HealthCareAnswerPolicy.current(draft, issue.copy(id = id()), question, settings, privacy))
    }
    @Test fun schemaRejectsConfirmationSourceInjectionAndWrongRevision() {
        val schema = HealthCareAnswerTool.definitions { _, _, _ -> error("Schema only") }.single().descriptor.inputSchema
        val valid = mapOf("question_id" to question.id, "question_revision" to 1, "quote" to "没有", "answer" to "没有")
        assertTrue(AgentNativeJsonSchemaValidator.validate(schema, valid).isValid)
        listOf(valid + ("confirmed" to true), valid + ("source_entry_id" to entry.id), valid + ("question_revision" to 1.5),
            valid + ("answer" to "x".repeat(2001))).forEach { assertFalse(AgentNativeJsonSchemaValidator.validate(schema, it).isValid) }
    }
}
