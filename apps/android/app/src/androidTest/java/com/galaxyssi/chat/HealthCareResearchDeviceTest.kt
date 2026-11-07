package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class HealthCareResearchDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now get() = System.currentTimeMillis()
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareResearchAuthorization) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"),
                "mmol/L", now - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names)
                val issue = care.page().items.single()
                val conversation = UUID.randomUUID().toString()
                val bound = care.bindDiscussion(issue.id, issue.revision, conversation)
                val grant = HealthCareDiscussionGrant(conversation, UUID.randomUUID().toString(), issue.id, bound.revision,
                    care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                    "a".repeat(64), now, "synthetic-private-provider", "synthetic-model", "high")
                test(names, care, HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, "b".repeat(64)))
            }
        } finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    private fun authorize(care: HealthCareStore, value: HealthCareResearchAuthorization) = care.authorizeResearch(value, null)
    private fun queue(care: HealthCareStore, value: HealthCareResearchAuthorization) = care.queueResearch(value.id, value.scope.concernId, now)
    private fun grant(value: HealthCareResearchAuthorization, job: HealthCareResearchJob) = value.scope.copy(
        turnId = job.turnId, revision = job.revision, researchAuthorizationId = value.id, approvedAt = now)

    @Test fun localCareAndManualDiscussionDoNotGrantBackgroundResearch(): Unit = fixture { _, care, value ->
        assertNull(care.researchAuthorization(value.scope.concernId))
        care.approveDiscussion(value.scope)
        assertThrows(HealthCareConflict::class.java) { queue(care, value) }
        assertTrue(care.researchJobs(value.scope.concernId).isEmpty())
    }
    @Test fun authorizationAndQueueSurviveReopenWithoutPlaintextPayloads(): Unit = fixture { names, care, value ->
        authorize(care, value); val job = queue(care, value)
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(value, reopened.researchAuthorization(value.scope.concernId))
            assertEquals(job, queue(reopened, value)); assertEquals(job, reopened.researchJob(job.turnId))
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM research_authorizations", null).use { row ->
                assertTrue(row.moveToFirst()); assertFalse(row.getBlob(0).toString(Charsets.ISO_8859_1).contains("synthetic-private-provider"))
            }
        }
    }
    @Test fun repeatedEventsAndConcurrentStoreInstancesAdmitOneTurn(): Unit = fixture { names, care, value ->
        authorize(care, value)
        val pool = Executors.newFixedThreadPool(4)
        try {
            val futures = (1..12).map { pool.submit<String> { HealthCareStore(context, names.care).use { queue(it, value).turnId } } }
            assertEquals(1, futures.map { it.get(20, TimeUnit.SECONDS) }.toSet().size)
            assertEquals(1, care.researchJobs(value.scope.concernId).size)
        } finally { pool.shutdown(); assertTrue(pool.awaitTermination(20, TimeUnit.SECONDS)) }
    }
    @Test fun revocationRejectsAlreadyPreparedTurnAndCancelsDurableQueue(): Unit = fixture { _, care, value ->
        authorize(care, value); val job = queue(care, value); val grant = grant(value, job)
        care.approveDiscussion(grant); assertTrue(care.researchGrantCurrent(grant))
        care.revokeResearch(value.scope.concernId, value.id, now)
        assertFalse(care.researchGrantCurrent(grant))
        assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(job.turnId)!!.state)
        assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(grant.copy(turnId = UUID.randomUUID().toString())) }
        assertThrows(HealthCareConflict::class.java) { queue(care, value) }
    }
    @Test fun changedProviderOrConversationCannotBorrowConsent(): Unit = fixture { _, care, value ->
        authorize(care, value); val grant = grant(value, queue(care, value))
        listOf(grant.copy(destination = "c".repeat(64)), grant.copy(modelId = "another-model"),
            grant.copy(conversationId = UUID.randomUUID().toString()), grant.copy(effort = "low"),
            grant.copy(privacyVersion = "new"), grant.copy(researchAuthorizationId = UUID.randomUUID().toString()))
            .forEach { assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(it) } }
    }
    @Test fun pauseAndResumeDoNotSilentlyReauthorizeResearch(): Unit = fixture { _, care, value ->
        authorize(care, value); val job = queue(care, value)
        val paused = care.update(value.scope.concernId, value.scope.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        care.update(paused.id, paused.revision, "fixture_resume") { it.copy(stage = HealthCareStage.REASSESS) }
        assertFalse(care.researchAuthorization(paused.id)!!.active)
        assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(job.turnId)!!.state)
        assertThrows(HealthCareConflict::class.java) { queue(care, value) }
    }
    @Test fun disablingCareRevokesAndReenablingCannotReuseConsent(): Unit = fixture { _, care, value ->
        authorize(care, value); val job = queue(care, value)
        val disabled = care.configure(false, care.settings().version)
        care.configure(true, disabled.version)
        assertFalse(care.researchAuthorization(value.scope.concernId)!!.active)
        assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(job.turnId)!!.state)
    }
    @Test fun newEvidenceCreatesAnotherTurnButDisplayRevisionDoesNot(): Unit = fixture { names, care, value ->
        authorize(care, value); val first = queue(care, value)
        care.update(value.scope.concernId, value.scope.revision, "fixture_display") { it.copy(reviewNote = "Opened") }
        val refreshed = queue(care, value)
        assertEquals(first.turnId, refreshed.turnId)
        assertEquals(care.concern(value.scope.concernId)!!.revision, refreshed.revision)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.4"), "mmol/L", now, reference = "4-6")) }
        HealthCareEngine.evaluate(context, names)
        val second = queue(care, value)
        assertNotEquals(first.turnId, second.turnId); assertNotEquals(first.trigger, second.trigger)
        assertFalse(care.researchGrantCurrent(grant(value, first)))
        assertEquals(2, care.researchJobs(value.scope.concernId).size)
    }
    @Test fun failedTurnIsNotRetriedByObserverOrReopen(): Unit = fixture { names, care, value ->
        authorize(care, value); val queued = queue(care, value)
        val dispatched = care.updateResearchJob(queued, HealthCareResearchState.DISPATCHED)
        val failed = care.updateResearchJob(dispatched, HealthCareResearchState.FAILED, "Synthetic provider failure")
        HealthCareStore(context, names.care).use { assertEquals(failed, queue(it, value)) }
        assertThrows(HealthCareConflict::class.java) { care.updateResearchJob(failed, HealthCareResearchState.QUEUED) }
        assertThrows(HealthCareConflict::class.java) { care.updateResearchJob(queued, HealthCareResearchState.DISPATCHED) }
    }
    @Test fun renewalInvalidatesPriorQueueAndRequiresCompareAndSet(): Unit = fixture { _, care, value ->
        authorize(care, value); val prior = queue(care, value)
        val next = value.copy(id = UUID.randomUUID().toString())
        assertThrows(HealthCareConflict::class.java) { care.authorizeResearch(next, null) }
        care.authorizeResearch(next, value.id)
        assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(prior.turnId)!!.state)
        assertNotEquals(prior.turnId, queue(care, next).turnId)
        assertThrows(HealthCareConflict::class.java) { care.revokeResearch(value.scope.concernId, value.id, now) }
    }
    @Test fun deletingIssueRetainsCancellationButDeletesAuthorizationAndHealthDetail(): Unit = fixture { names, care, value ->
        authorize(care, value); val job = queue(care, value)
        care.delete(value.scope.concernId, value.scope.revision)
        assertNull(care.researchAuthorization(value.scope.concernId)); assertNull(care.concern(value.scope.concernId))
        HealthCareStore(context, names.care).use { reopened ->
            val cancelled = reopened.researchJob(job.turnId)!!
            assertEquals(HealthCareResearchState.CANCELLED, cancelled.state)
            assertEquals("", cancelled.detail)
            assertEquals(listOf(cancelled), reopened.pendingResearchCancellations())
            reopened.acknowledgeResearchCancellation(cancelled)
            assertTrue(reopened.pendingResearchCancellations().isEmpty())
        }
        assertFalse(care.researchGrantCurrent(grant(value, job)))
    }
    @Test fun indexedStateTamperingCannotReviveOrRedirectJob(): Unit = fixture { names, care, value ->
        authorize(care, value); val job = queue(care, value)
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.update("research_jobs", ContentValues().apply { put("state", "COMPLETED") }, "turn_id=?", arrayOf(job.turnId))
        }
        assertThrows(IllegalStateException::class.java) { care.researchJob(job.turnId) }
    }
    @Test fun cancellationOutboxSurvivesReopenAndRejectsStaleAcknowledgement(): Unit = fixture { names, care, value ->
        authorize(care, value); val queued = queue(care, value)
        val running = care.updateResearchJob(queued, HealthCareResearchState.DISPATCHED)
        care.revokeResearch(value.scope.concernId, value.id, now)
        HealthCareStore(context, names.care).use { reopened ->
            val cancelled = reopened.pendingResearchCancellations().single()
            assertEquals(running.turnId, cancelled.turnId)
            assertThrows(HealthCareConflict::class.java) { reopened.acknowledgeResearchCancellation(running) }
            reopened.acknowledgeResearchCancellation(cancelled)
            assertFalse(reopened.researchJob(cancelled.turnId)!!.cancellationPending)
            assertFalse(reopened.researchGrantCurrent(grant(value, running)))
        }
    }
    @Test fun sameTurnGrantApprovalIsIdempotentButCannotBeRebound(): Unit = fixture { _, care, value ->
        authorize(care, value); val job = queue(care, value); val approved = grant(value, job)
        care.approveDiscussion(approved); care.approveDiscussion(approved)
        assertEquals(approved, care.discussionGrant(job.turnId))
        assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(approved.copy(approvedAt = approved.approvedAt + 1)) }
    }
    @Test fun terminalOutcomeAndFailureReasonCannotBeOverwritten(): Unit = fixture { _, care, value ->
        authorize(care, value); val job = queue(care, value)
        val failed = care.updateResearchJob(job, HealthCareResearchState.FAILED, "Synthetic interruption")
        assertThrows(HealthCareConflict::class.java) { care.updateResearchJob(failed, HealthCareResearchState.FAILED, "Hidden failure") }
        assertEquals(failed, care.researchJob(job.turnId))
    }
    @Test fun pendingCancellationPagesDoNotLetAnOlderUnsentTurnHideOtherJobs(): Unit = fixture { _, care, value ->
        var authorization = value
        authorize(care, authorization)
        repeat(65) {
            queue(care, authorization)
            val next = authorization.copy(id = UUID.randomUUID().toString())
            care.authorizeResearch(next, authorization.id)
            authorization = next
        }
        val seen = mutableListOf<String>()
        var after = ""
        do {
            val page = care.pendingResearchCancellations(after)
            if (page.isEmpty()) break
            assertTrue(page.size <= 30)
            seen += page.map { it.turnId }
            after = page.last().turnId
        } while (true)
        assertEquals(65, seen.size); assertEquals(65, seen.toSet().size)
        assertEquals(seen.sorted(), seen)
    }
    @Test fun schemaSixMigrationPreservesManualGrantAndNeverInventsConsent(): Unit = fixture { names, care, value ->
        val issue = care.concern(value.scope.concernId)
        care.approveDiscussion(value.scope); care.close()
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.execSQL("DROP TABLE research_jobs"); db.execSQL("DROP TABLE research_authorizations"); db.version = 6
        }
        HealthCareStore(context, names.care).use {
            assertEquals(issue, it.concern(value.scope.concernId)); assertEquals(value.scope, it.discussionGrant(value.scope.turnId))
            assertTrue(it.researchAuthorizations().isEmpty()); assertTrue(it.researchJobs(value.scope.concernId).isEmpty())
        }
    }
}
