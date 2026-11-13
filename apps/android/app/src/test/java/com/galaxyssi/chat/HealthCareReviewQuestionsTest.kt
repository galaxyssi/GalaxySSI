package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareReviewQuestionsTest {
    private fun id() = UUID.randomUUID().toString()
    private val record = HealthCareRecordRef(id(), 1)
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 1, 100, 100, "source-v1",
        HealthCareAssessment(record, 100, "6.3", "mmol/L", "", setOf(HealthCareSignal.GLUCOSE_CONTEXT)))
    private val grant = HealthCareDiscussionGrant(id(), id(), issue.id, 1, "settings", "privacy", "a".repeat(64),
        100, "fixture", "fixture-model", "high", questionsShared = true)
    private fun question(current: HealthCareConcern = issue, key: String = "sample.notes") = HealthCareQuestion(id(), current.id,
        key, "合成测试：采样条件是什么？", "核对后续资料的适用条件。", HealthCareQuestionPolicy.basis(current),
        HealthCareQuestionPolicy.scope(current), record, 100, grant.turnId, 1, 100, 100)
    private fun input(q: HealthCareQuestion) = HealthCareModelReviewInput("合成评估", "需要补充采样条件", "尚未确认", "核对本次问题",
        HealthCareReviewDecision.CLARIFY, listOf(HealthCareReviewEvent.USER_FEEDBACK), listOf(record), emptyList(), "", false,
        "等待用户核对", listOf(HealthCareQuestionRef(q.id, q.revision)))
    private fun validate(q: HealthCareQuestion, current: HealthCareConcern = issue, scope: HealthCareDiscussionGrant = grant) =
        HealthCareReviewQuestions.validate(current, scope, input(q), null) { q }

    @Test fun retainedOpenQuestionMayComeFromAnEarlierAuthorizedTurn() {
        val q = question().copy(turnId = id())
        validate(q)
        assertEquals(HealthCareQuestionState.OPEN, q.state)
    }
    @Test fun unrelatedConcernScopeOrWithdrawnRelatedMetricIsRejected() {
        listOf(question().copy(concernId = id()), question().copy(scope = "c".repeat(64)),
            question().copy(related = setOf(HealthMetric.WEIGHT))).forEach { q ->
            assertThrows(HealthCareConflict::class.java) { validate(q) }
        }
        assertThrows(HealthCareConflict::class.java) { validate(question(), scope = grant.copy(questionsShared = false)) }
    }
    @Test fun inventedOrOutdatedReferencesAreCorrectableWithinTheTurn() {
        val q = question()
        assertThrows(IllegalArgumentException::class.java) { HealthCareReviewQuestions.validate(issue, grant, input(q), null) { null } }
        assertThrows(IllegalArgumentException::class.java) {
            HealthCareReviewQuestions.validate(issue, grant, input(q), null) { q.copy(revision = 2) }
        }
        validate(q)
    }
    @Test fun answeredDeferredDeclinedAndStaleQuestionsAreNotPendingClarifications() {
        listOf(HealthCareQuestionState.ANSWERED, HealthCareQuestionState.DEFERRED, HealthCareQuestionState.DECLINED).forEach { state ->
            val q = question().copy(state = state, answer = if (state == HealthCareQuestionState.ANSWERED) "已确认" else "")
            assertThrows(IllegalArgumentException::class.java) { validate(q) }
        }
        assertThrows(IllegalArgumentException::class.java) { validate(question().copy(basis = "d".repeat(64))) }
    }
    @Test fun savedFactsAreNotMissingButConflictingSelfReportsRemainReviewable() {
        val known = issue.copy(context = HealthCareContext(record, fastingHours = 10, confirmedAt = 100))
        val q = question(known, "context.fasting_hours")
        assertThrows(IllegalArgumentException::class.java) { validate(q, known) }
        validate(q.copy(state = HealthCareQuestionState.ANSWERED, answer = "8"), known)
        validate(q.copy(state = HealthCareQuestionState.CONFLICT, answer = "需核对"), known)
        assertThrows(IllegalArgumentException::class.java) { validate(q.copy(state = HealthCareQuestionState.ANSWERED, answer = "10"), known) }
    }
    @Test fun selectedProfileCannotBeSkippedWhenResolvingKnownFacts() {
        val scope = HealthCareProfileScope("", setOf(HealthProfileField.HEIGHT), emptySet())
        val link = HealthCareProfileLink(scope, HealthProfileStamp("", mapOf("field:HEIGHT" to "v1")))
        val selected = issue.copy(profileLink = link)
        assertThrows(HealthCareConflict::class.java) { validate(question(selected), selected, grant.copy(profileLink = link)) }
    }
    @Test fun nonClarifyingAssessmentDoesNotRequireQuestionSharing() {
        HealthCareReviewQuestions.validate(issue, grant.copy(questionsShared = false),
            input(question()).copy(decision = HealthCareReviewDecision.OBSERVE, questions = emptyList()), null) {
            error("An observation must not scan the question ledger")
        }
    }
}
