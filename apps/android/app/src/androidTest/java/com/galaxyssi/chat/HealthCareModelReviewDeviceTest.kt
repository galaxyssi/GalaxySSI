package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareModelReviewDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (HealthOverviewDatabases, HealthCareStore, HealthCareResearchJob, HealthCareDiscussionGrant) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val now = System.currentTimeMillis()
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", now - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names)
                val issue = care.page().items.single()
                val conversation = UUID.randomUUID().toString()
                val bound = care.bindDiscussion(issue.id, issue.revision, conversation)
                val scope = HealthCareDiscussionGrant(conversation, UUID.randomUUID().toString(), issue.id, bound.revision,
                    care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                    "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
                val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
                care.authorizeResearch(authorization, null)
                val job = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
                val grant = scope.copy(turnId = job.turnId, researchAuthorizationId = authorization.id, approvedAt = System.currentTimeMillis())
                care.approveDiscussion(grant)
                block(names, care, job, grant)
            }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun input(care: HealthCareStore, job: HealthCareResearchJob) = HealthCareModelReviewTestFixture.input(care, job.concernId)

    @Test fun assessmentPersistsEncryptedAndIdenticalRetryReturnsOriginalReceipt() = fixture { names, care, job, grant ->
        val request = input(care, job)
        val saved = care.recordModelReview(grant, request, System.currentTimeMillis())
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(saved, reopened.modelReview(job.turnId))
            assertEquals(saved, reopened.recordModelReview(grant, request, System.currentTimeMillis() + 1))
            assertEquals(job, reopened.queueResearch(job.authorizationId, job.concernId, System.currentTimeMillis()))
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM model_reviews", null).use {
                assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(request.summary))
                assertFalse(it.moveToNext())
            }
        }
        assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, request.copy(summary = "different"), System.currentTimeMillis()) }
    }
    @Test fun proseOnlyCompletionIsIncompleteWithoutAutomaticRetry() = fixture { _, care, job, _ ->
        assertTrue(job.reviewRequired)
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        val failed = care.updateResearchJob(running, HealthCareResearchState.COMPLETED)
        assertEquals(HealthCareResearchState.FAILED, failed.state)
        assertEquals(context.getString(R.string.health_model_review_missing), failed.detail)
        assertEquals(failed, care.queueResearch(job.authorizationId, job.concernId, System.currentTimeMillis()))
    }
    @Test fun assessmentDoesNotCompleteRunCloseConcernOrScheduleCare() = fixture { _, care, job, grant ->
        val before = care.concern(job.concernId)!!
        care.recordModelReview(grant, input(care, job), System.currentTimeMillis())
        assertEquals(before, care.concern(job.concernId))
        assertEquals(HealthCareResearchState.QUEUED, care.researchJob(job.turnId)!!.state)
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        assertEquals(HealthCareResearchState.COMPLETED, care.updateResearchJob(running, HealthCareResearchState.COMPLETED).state)
        assertEquals(before, care.concern(job.concernId))
    }
    @Test fun inventedSourcesRecordRevisionOrPlanCannotBeStored() = fixture { _, care, job, grant ->
        val request = input(care, job)
        listOf(request.copy(evidenceIds = listOf(UUID.randomUUID().toString())),
            request.copy(records = request.records.map { it.copy(revision = it.revision + 1) }),
            request.copy(planId = UUID.randomUUID().toString())).forEach {
            assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, it, System.currentTimeMillis()) }
        }
        assertNull(care.modelReview(job.turnId))
    }
    @Test fun manualOrDifferentConversationCannotWriteBackgroundAssessment() = fixture { _, care, job, grant ->
        listOf(grant.copy(conversationId = UUID.randomUUID().toString()), grant.copy(researchAuthorizationId = ""),
            grant.copy(modelId = "another-model"), grant.copy(turnId = UUID.randomUUID().toString())).forEach {
            assertThrows(HealthCareConflict::class.java) { care.recordModelReview(it, input(care, job), System.currentTimeMillis()) }
        }
    }
    @Test fun revokedConsentRejectsLateAssessment() = fixture { _, care, job, grant ->
        care.revokeResearch(job.concernId, job.authorizationId, System.currentTimeMillis())
        assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, input(care, job), System.currentTimeMillis()) }
        assertNull(care.modelReview(job.turnId))
    }
    @Test fun sourceChangeRejectsOldRunWithoutLosingEarlierAssessment() = fixture { names, care, job, grant ->
        val request = input(care, job)
        val saved = care.recordModelReview(grant, request, System.currentTimeMillis())
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to "6.4"), "mmol/L", System.currentTimeMillis(), reference = "4-6")) }
        HealthCareEngine.evaluate(context, names)
        assertThrows(HealthCareConflict::class.java) { care.recordModelReview(grant, request, System.currentTimeMillis()) }
        assertEquals(saved, care.modelReview(job.turnId))
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        assertEquals(HealthCareResearchState.SUPERSEDED, care.updateResearchJob(running, HealthCareResearchState.COMPLETED).state)
    }
    @Test fun deletingConcernPurgesAssessmentButRetainsCancellation() = fixture { names, care, job, _ ->
        HealthCareModelReviewTestFixture.record(care, job)
        care.delete(job.concernId, care.concern(job.concernId)!!.revision)
        HealthCareStore(context, names.care).use {
            assertNull(it.modelReview(job.turnId))
            assertEquals(HealthCareResearchState.CANCELLED, it.researchJob(job.turnId)!!.state)
        }
    }
    @Test fun encryptedPayloadCannotBeRedirectedByEditingIndex() = fixture { names, care, job, _ ->
        HealthCareModelReviewTestFixture.record(care, job)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.update("model_reviews", ContentValues().apply { put("concern_id", UUID.randomUUID().toString()) }, "turn_id=?", arrayOf(job.turnId))
        }
        assertThrows(IllegalStateException::class.java) { care.modelReview(job.turnId) }
    }
    @Test fun version17UpgradeRetainsConcernAndSamePendingTurn() = fixture { names, care, job, _ ->
        val issue = care.concern(job.concernId)
        care.close()
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.execSQL("DROP TABLE model_reviews"); db.version = 17
        }
        HealthCareStore(context, names.care).use {
            assertEquals(issue, it.concern(job.concernId)); assertEquals(job, it.researchJob(job.turnId))
            assertNull(it.modelReview(job.turnId))
        }
        context.openOrCreateDatabase(names.care, 0, null).use { assertEquals(18, it.version) }
    }
    @Test fun ignoredWriteCannotReturnSuccessfulReceiptOrChangeTheConcern() = fixture { names, care, job, grant ->
        val issue = care.concern(job.concernId)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.execSQL("CREATE TRIGGER ignore_model_review BEFORE INSERT ON model_reviews BEGIN SELECT RAISE(IGNORE); END")
        }
        assertThrows(IllegalStateException::class.java) { care.recordModelReview(grant, input(care, job), System.currentTimeMillis()) }
        assertNull(care.modelReview(job.turnId)); assertEquals(issue, care.concern(job.concernId)); assertEquals(job, care.researchJob(job.turnId))
        context.openOrCreateDatabase(names.care, 0, null).use { it.execSQL("DROP TRIGGER ignore_model_review") }
        assertNotNull(care.recordModelReview(grant, input(care, job), System.currentTimeMillis()))
    }
}
