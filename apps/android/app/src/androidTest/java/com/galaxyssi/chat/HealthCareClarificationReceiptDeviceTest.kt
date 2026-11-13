package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareClarificationReceiptDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(shared: Boolean = true,
        block: (HealthOverviewDatabases, HealthCareStore, HealthCareResearchJob, HealthCareDiscussionGrant) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names)
                val first = care.page().items.single()
                val issue = care.bindDiscussion(first.id, first.revision, UUID.randomUUID().toString())
                val scope = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                    care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                    "a".repeat(64), System.currentTimeMillis(), "fixture-provider", "fixture-model", "high", questionsShared = shared)
                val auth = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
                care.authorizeResearch(auth, null)
                val job = care.queueResearch(auth.id, issue.id, System.currentTimeMillis())
                val grant = scope.copy(turnId = job.turnId, researchAuthorizationId = auth.id, approvedAt = System.currentTimeMillis())
                care.approveDiscussion(grant)
                block(names, care, job, grant)
            }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun ask(care: HealthCareStore, grant: HealthCareDiscussionGrant) = care.proposeQuestion(grant,
        "context.fasting_hours", "这次采血前空腹了多久？", "核对本次测量条件，不作诊断。", System.currentTimeMillis())
    private fun input(care: HealthCareStore, job: HealthCareResearchJob, question: HealthCareQuestion? = null) =
        HealthCareModelReviewTestFixture.input(care, job.concernId).copy(decision = HealthCareReviewDecision.CLARIFY,
            questions = listOfNotNull(question?.let { HealthCareQuestionRef(it.id, it.revision) }))

    @Test fun clarificationPersistsExactEncryptedReferencesAndRetryDoesNotAskAgain() = fixture { names, care, job, grant ->
        val q = ask(care, grant)
        val before = care.concern(job.concernId)!!
        val request = input(care, job, q)
        val saved = care.recordModelReview(grant, request, System.currentTimeMillis())
        HealthCareStore(context, names.care).use {
            assertEquals(saved, it.modelReview(job.turnId))
            assertEquals(saved, it.recordModelReview(grant, request, System.currentTimeMillis()))
            assertEquals(q, it.question(q.id)); assertEquals(before, it.concern(job.concernId))
            assertEquals(1, it.questions(before).items.size)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM model_reviews", null).use {
                assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(q.id))
            }
        }
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        assertEquals(HealthCareResearchState.COMPLETED, care.updateResearchJob(running, HealthCareResearchState.COMPLETED).state)
        assertTrue(before.actions.isEmpty()); assertNull(care.nextReminder())
    }
    @Test fun missingOrInventedQuestionsCanBeCorrectedBeforeCompletion() = fixture { _, care, job, grant ->
        val registry = AgentNativeToolRegistry()
        registry.register(HealthCareModelReviewTool.definition { _, supplied -> care.recordModelReview(grant, supplied, System.currentTimeMillis()) })
        val missing = registry.invoke(HealthCareModelReviewTool.ID, input(care, job).json().toNativeObject())
        assertEquals("invalid_health_review", missing.error?.code)
        val invented = input(care, job).copy(questions = listOf(HealthCareQuestionRef(UUID.randomUUID().toString(), 1)))
        assertEquals("invalid_health_review", registry.invoke(HealthCareModelReviewTool.ID, invented.json().toNativeObject()).error?.code)
        assertNull(care.modelReview(job.turnId)); assertEquals(HealthCareResearchState.QUEUED, care.researchJob(job.turnId)!!.state)
        val q = ask(care, grant)
        assertTrue(registry.invoke(HealthCareModelReviewTool.ID, input(care, job, q).json().toNativeObject()).isSuccess)
        assertEquals(listOf(HealthCareQuestionRef(q.id, q.revision)), care.modelReview(job.turnId)!!.input.questions)
    }
    @Test fun unknownQuestionRevisionCannotBeReportedAsSaved() = fixture { _, care, job, grant ->
        val q = ask(care, grant)
        val changed = input(care, job, q).copy(questions = listOf(HealthCareQuestionRef(q.id, q.revision + 1)))
        assertThrows(IllegalArgumentException::class.java) { care.recordModelReview(grant, changed, System.currentTimeMillis()) }
        assertNull(care.modelReview(job.turnId))
        assertNotNull(care.recordModelReview(grant, input(care, job, q), System.currentTimeMillis()))
    }
    @Test fun clarificationDoesNotExpandAnAuthorizationWithoutQuestionSharing() = fixture(false) { _, care, job, grant ->
        val request = input(care, job).copy(questions = listOf(HealthCareQuestionRef(UUID.randomUUID().toString(), 1)))
        assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, request, System.currentTimeMillis()) }
        assertNull(care.modelReview(job.turnId))
        assertNotNull(care.recordModelReview(grant, request.copy(decision = HealthCareReviewDecision.OBSERVE,
            questions = emptyList()), System.currentTimeMillis()))
    }
    @Test fun aReviewedAnswerInvalidatesTheOldTurnAndIsNotPendingInItsSuccessor() = fixture { _, care, job, grant ->
        val q = ask(care, grant)
        val saved = care.recordModelReview(grant, input(care, job, q), System.currentTimeMillis())
        val issue = care.concern(job.concernId)!!
        val answer = care.reviewQuestion(issue.id, issue.revision, q.id, q.revision, HealthCareQuestionState.ANSWERED,
            "空腹10小时", System.currentTimeMillis())
        assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, input(care, job, q), System.currentTimeMillis()) }
        assertEquals(saved, care.modelReview(job.turnId)); assertEquals(answer, care.question(q.id))
        val current = care.concern(issue.id)!!
        val next = care.queueResearch(job.authorizationId, issue.id, System.currentTimeMillis())
        assertNotEquals(job.turnId, next.turnId)
        val successor = grant.copy(turnId = next.turnId, revision = current.revision,
            approvedAt = System.currentTimeMillis())
        care.approveDiscussion(successor)
        assertThrows(IllegalArgumentException::class.java) { care.recordModelReview(successor, input(care, next, answer), System.currentTimeMillis()) }
        val observed = care.recordModelReview(successor, HealthCareModelReviewTestFixture.input(care, issue.id), System.currentTimeMillis())
        assertTrue(observed.input.questions.isEmpty()); assertEquals(saved, care.modelReview(job.turnId))
        assertEquals(1, care.questions(current).items.size)
    }
    @Test fun unrecordedClarificationCannotCompleteAnAutomaticReview() = fixture { _, care, job, grant ->
        assertThrows(IllegalArgumentException::class.java) { care.recordModelReview(grant, input(care, job), System.currentTimeMillis()) }
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        assertEquals(HealthCareResearchState.FAILED, care.updateResearchJob(running, HealthCareResearchState.COMPLETED).state)
        assertTrue(care.questions(care.concern(job.concernId)!!).items.isEmpty())
    }
}
