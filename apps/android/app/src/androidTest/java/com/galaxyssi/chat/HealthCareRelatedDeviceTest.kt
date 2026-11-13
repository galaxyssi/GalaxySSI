package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareRelatedDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthRecordStore, HealthCareStore, HealthCareDiscussionGrant) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthRecordStore(context, names.records).use { records -> HealthCareStore(context, names.care).use { care ->
            val now = System.currentTimeMillis()
            records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 3000, reference = "4-6"))
            records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 2000))
            records.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "121", "diastolic" to "79"), "mmHg", now - 1000))
            records.save(HealthDraft(HealthMetric.HEART_RATE, mapOf("pulse" to "72"), "bpm", now - 1000))
            care.configure(true, care.settings().version)
            HealthCareEngine.evaluate(context, names)
            val old = care.forMetric(HealthMetric.GLUCOSE)!!
            val issue = care.bindDiscussion(old.id, old.revision, UUID.randomUUID().toString())
            val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                "a".repeat(64), System.currentTimeMillis(), "fixture-provider", "fixture-model", "high",
                related = HealthCareRelatedContext.capture(care, setOf(HealthMetric.WEIGHT, HealthMetric.BLOOD_PRESSURE)))
            care.approveDiscussion(grant)
            test(names, records, care, grant)
        } } } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun read(names: HealthOverviewDatabases, care: HealthCareStore, grant: HealthCareDiscussionGrant, metric: HealthMetric,
        extra: Map<String, Any?> = emptyMap()) = HealthCareHistoryTool.read(context, names,
        AgentNativeToolInvocationContext(conversationId = grant.conversationId, turnId = grant.turnId),
        mapOf("metric" to metric.name, "input_version" to care.relatedMeasurement(metric)!!.inputVersion) + extra)
    private fun authorize(care: HealthCareStore, grant: HealthCareDiscussionGrant): Pair<HealthCareResearchJob, HealthCareDiscussionGrant> {
        val auth = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, "b".repeat(64))
        care.authorizeResearch(auth, null)
        val job = care.queueResearch(auth.id, grant.concernId, System.currentTimeMillis())
        val turn = grant.copy(turnId = job.turnId, researchAuthorizationId = auth.id, approvedAt = System.currentTimeMillis())
        care.approveDiscussion(turn)
        return job to turn
    }
    @Test fun selectedMeasurementsRetainTheirOwnUnitsTimesAndNoOtherScope(): Unit = fixture { names, _, care, grant ->
        val payload = HealthCareRelatedContext.snapshot(care, grant.related)
        val rows = payload.getJSONArray("selected")
        assertEquals(2, rows.length()); assertFalse(payload.getBoolean("complete_health_archive"))
        assertNull(care.forMetric(HealthMetric.WEIGHT)); assertNull(care.forMetric(HealthMetric.BLOOD_PRESSURE))
        val metrics = (0 until rows.length()).map { rows.getJSONObject(it).getString("metric") }.toSet()
        assertEquals(setOf("WEIGHT", "BLOOD_PRESSURE"), metrics)
        assertFalse(payload.toString().contains("device_group")); assertFalse(payload.toString().contains("origin"))
        assertFalse(payload.toString().contains("HEART_RATE")); assertFalse(payload.toString().contains("conversation_id"))
        val weight = read(names, care, grant, HealthMetric.WEIGHT)
        assertEquals("WEIGHT", weight.getString("metric"))
        val sample = weight.getJSONObject("history").getJSONArray("samples").getJSONObject(0)
        assertEquals("kg", sample.getString("unit"))
        assertTrue(sample.has("measured_at"))
        assertTrue(runCatching { read(names, care, grant, HealthMetric.HEART_RATE) }.exceptionOrNull() is HealthCareConflict)
        assertTrue(runCatching { read(names, care, grant, HealthMetric.WEIGHT,
            mapOf("input_version" to care.concern(grant.concernId)!!.inputVersion)) }.exceptionOrNull() is HealthCareConflict)
        HealthCareStore(context, names.care).use { assertEquals(grant, it.discussionGrant(grant.turnId)) }
    }
    @Test fun selectedEditsRejectReadsBeforeReconciliationAndCreateOneNewJob(): Unit = fixture { names, records, care, grant ->
        val (job, turn) = authorize(care, grant)
        read(names, care, turn, HealthMetric.WEIGHT)
        records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "71"), "kg", System.currentTimeMillis() - 100))
        assertFalse(HealthCareRelatedContext.sourceCurrent(context, names, turn))
        assertTrue(runCatching { read(names, care, turn, HealthMetric.GLUCOSE) }.exceptionOrNull() is HealthCareConflict)
        HealthCareEngine.evaluate(context, names)
        assertFalse(care.researchGrantCurrent(turn))
        val next = care.queueResearch(job.authorizationId, grant.concernId, System.currentTimeMillis())
        assertNotEquals(job.turnId, next.turnId); assertNotEquals(job.trigger, next.trigger)
        repeat(3) { assertEquals(next, care.queueResearch(job.authorizationId, grant.concernId, System.currentTimeMillis())) }
        val refreshed = turn.copy(turnId = next.turnId, related = HealthCareRelatedContext.capture(care, grant.related.keys))
        care.approveDiscussion(refreshed)
        assertTrue(HealthCareRelatedContext.sourceCurrent(context, names, refreshed))
        assertTrue(care.researchGrantCurrent(refreshed))
    }
    @Test fun unselectedChangesDoNotRestartOrInvalidateReview(): Unit = fixture { names, records, care, grant ->
        val (job, turn) = authorize(care, grant)
        records.save(HealthDraft(HealthMetric.HEART_RATE, mapOf("pulse" to "73"), "bpm", System.currentTimeMillis() - 100))
        HealthCareEngine.evaluate(context, names)
        assertTrue(HealthCareRelatedContext.sourceCurrent(context, names, turn))
        assertEquals(job, care.queueResearch(job.authorizationId, grant.concernId, System.currentTimeMillis()))
    }
    @Test fun combinedAssessmentRequiresPrimaryAndOnlySelectedRecordReferences(): Unit = fixture { names, records, care, grant ->
        val (job, turn) = authorize(care, grant)
        val input = HealthCareModelReviewTestFixture.input(care, grant.concernId)
        val related = care.relatedMeasurement(HealthMetric.WEIGHT)!!.assessment!!.record!!
        val foreign = care.relatedMeasurement(HealthMetric.HEART_RATE)!!.assessment!!.record!!
        assertTrue(runCatching { care.recordModelReview(turn, input.copy(records = listOf(related)), System.currentTimeMillis()) }.isFailure)
        assertTrue(runCatching { care.recordModelReview(turn, input.copy(records = input.records + foreign), System.currentTimeMillis()) }.isFailure)
        val saved = care.recordModelReview(turn, input.copy(records = input.records + related, attentionRequested = true), System.currentTimeMillis())
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        care.updateResearchJob(running, HealthCareResearchState.COMPLETED)
        val notice = care.modelAttention(grant.concernId)!!
        assertTrue(care.modelAttentionCurrent(notice, System.currentTimeMillis()))
        records.delete(related.id, related.revision)
        HealthCareEngine.evaluate(context, names)
        assertFalse(care.modelAttentionCurrent(notice, System.currentTimeMillis()))
        val snapshot = HealthCareRelatedContext.snapshot(care, HealthCareRelatedContext.capture(care, grant.related.keys))
        assertFalse(snapshot.toString().contains(related.id))
        HealthCareStore(context, names.care).use { assertEquals(saved, it.modelReview(turn.turnId)) }
    }
    @Test fun relatedHistoryUsesContiguousBoundedPages(): Unit = fixture { names, records, care, grant ->
        val now = System.currentTimeMillis()
        repeat(61) { records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 10000 - it)) }
        HealthCareEngine.evaluate(context, names)
        val refreshed = grant.copy(turnId = UUID.randomUUID().toString(), approvedAt = System.currentTimeMillis(),
            related = HealthCareRelatedContext.capture(care, grant.related.keys))
        care.approveDiscussion(refreshed)
        val ids = mutableListOf<String>()
        var cursor = emptyMap<String, Any?>()
        do {
            val page = read(names, care, refreshed, HealthMetric.WEIGHT, cursor)
            val samples = page.getJSONObject("history").getJSONArray("samples")
            assertTrue(samples.length() <= 30)
            repeat(samples.length()) { ids += samples.getJSONObject(it).getJSONObject("record").getString("id") }
            cursor = page.optJSONObject("next")?.let { mapOf("before_time" to it.getLong("before_time"), "before_id" to it.getString("before_id")) }.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(62, ids.size); assertEquals(62, ids.distinct().size)
    }
    @Test fun revocationAndPrimaryMetricInjectionAreRejected(): Unit = fixture { names, _, care, grant ->
        assertTrue(runCatching { care.approveDiscussion(grant.copy(turnId = UUID.randomUUID().toString(),
            related = grant.related + HealthCareRelatedContext.capture(care, setOf(HealthMetric.GLUCOSE)))) }.isFailure)
        val (job, turn) = authorize(care, grant)
        care.revokeResearch(grant.concernId, job.authorizationId, System.currentTimeMillis())
        assertTrue(runCatching { read(names, care, turn, HealthMetric.WEIGHT) }.exceptionOrNull() is HealthCareConflict)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        assertFalse(HealthCareRelatedContext.sourceCurrent(context, names, grant))
    }
    @Test fun withdrawnMeasurementsCannotReturnThroughPersistedQuestions(): Unit = fixture { names, _, care, grant ->
        val shared = grant.copy(turnId = UUID.randomUUID().toString(), questionsShared = true)
        care.approveDiscussion(shared)
        val question = care.proposeQuestion(shared, "context.fixture", "合成测试：体重记录的测量条件是什么？", "核对所选记录", System.currentTimeMillis())
        assertEquals(grant.related.keys, question.related)
        val issue = care.concern(grant.concernId)!!
        assertEquals(listOf(question), care.questionsForGrant(issue, shared).items)
        val narrowed = shared.copy(turnId = UUID.randomUUID().toString(), related = emptyMap())
        care.approveDiscussion(narrowed)
        assertTrue(care.questionsForGrant(issue, narrowed).items.isEmpty())
        assertTrue(runCatching { care.proposeQuestion(narrowed, question.key, "重试", "核对", System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(question, reopened.question(question.id))
            assertTrue(reopened.questionsForGrant(issue, narrowed).items.isEmpty())
            assertEquals(listOf(question), reopened.questions(issue).items)
        }
    }
    @Test fun selectedSourcesCannotSilentlyTurnIntoPlansAfterTheyChange() {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.WEIGHT,
                mapOf("weight" to "70"), "kg", System.currentTimeMillis() - 1000)) }
            val plan = HealthCarePlanTestFixture.propose(context, names, transformGrant = { care, grant ->
                grant.copy(related = HealthCareRelatedContext.capture(care, setOf(HealthMetric.WEIGHT)))
            })
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.WEIGHT,
                mapOf("weight" to "71"), "kg", System.currentTimeMillis() - 100)) }
            assertFalse(HealthCareRelatedContext.sourceCurrent(context, names, plan.grant))
            HealthCareEngine.evaluate(context, names)
            HealthCareStore(context, names.care).use { care ->
                val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
                assertTrue(runCatching { care.resolvePlan(plan.id, setOf(plan.actions.first().id), plan.grant.revision,
                    privacy, plan.inputVersion, System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
                assertTrue(care.concern(plan.grant.concernId)!!.actions.isEmpty())
                assertNull(care.nextReminder()); assertEquals(HealthCarePlanState.PENDING, care.plan(plan.id)!!.state)
            }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
}
