package com.galaxyssi.chat

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal object HealthCareMaintenanceTestFixture {
    fun propose(context: Context, names: HealthOverviewDatabases): HealthCarePlan {
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { records ->
            listOf("61", "60").forEachIndexed { i, value -> records.save(HealthDraft(HealthMetric.WEIGHT,
                mapOf("weight" to value), "kg", now - (i + 1L) * 86400000, "resting", reference = "40-50")) }
        }
        HealthCareStore(context, names.care).use { it.configure(true, it.settings().version) }
        HealthCareEngine.evaluate(context, names)
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        return HealthCareStore(context, names.care).use { store ->
            val original = store.forMetric(HealthMetric.WEIGHT)!!
            val issue = store.bindDiscussion(original.id, original.revision, UUID.randomUUID().toString())
            val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                store.settings().version, privacy.version, "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
            store.approveDiscussion(grant)
            val quote = "Synthetic maintenance fixture with a follow-up window; this is not medical advice."
            val url = "https://example.test/maintenance"
            val hash = AgentNativeJsonCodec.sha256(quote)
            val receipt = HealthCareEvidence(UUID.randomUUID().toString(), grant, UUID.randomUUID().toString(), url,
                "Synthetic maintenance source", AgentWebIntelligenceText.citationId(url, hash), hash, quote, now, now)
            store.recordEvidence(listOf(receipt))
            val applicability = mapOf("mode" to "INDIVIDUALIZED", "checks" to listOf(mapOf("field" to "metric", "operator" to "EQUALS",
                "expected" to "WEIGHT", "source_index" to 0)), "missing_information" to emptyList<String>(), "conflicts" to emptyList<String>())
            val input: AgentNativeJsonObject = mapOf("uncertainty" to "合成测试，不是实际医学评估或诊疗建议。", "sources" to listOf(mapOf(
                "title" to "合成维护评估依据", "url" to url, "version" to "fixture-v1", "applicability" to "只用于隔离测试，不用于真实健康决策。",
                "evidence_id" to receipt.id, "supporting_quote" to quote)), "actions" to listOf(mapOf("kind" to "RECHECK", "description" to "复核下一阶段结果（合成测试）",
                "rationale" to "测试复评状态恢复，不是推荐复查间隔。", "source_index" to 0, "applicability" to applicability,
                "due_from" to Instant.ofEpochMilli(now + 86400000).toString(), "due_until" to Instant.ofEpochMilli(now + 172800000).toString())),
                "maintenance_review" to mapOf("rationale" to "资料已列入本次合成观察窗口，待用户确认跟进方式；不代表病情稳定。",
                    "records" to issue.assessment.series!!.samples.map { mapOf("id" to it.record.id, "revision" to it.record.revision) },
                    "source_index" to 0, "recheck_index" to 0, "goal_basis" to "RISK_REVIEW", "applicability" to applicability))
            store.proposePlan(HealthCarePlanPolicy.parse(input, grant, issue, now))
        }
    }
}

class HealthCareMaintenanceDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCarePlan) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val plan = HealthCareMaintenanceTestFixture.propose(context, names)
            HealthCareStore(context, names.care).use { test(names, it, plan) }
        } finally { listOf(names.records, names.care, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun accept(names: HealthOverviewDatabases, store: HealthCareStore, plan: HealthCarePlan, maintenance: Boolean = true) =
        store.resolvePlan(plan.id, setOf(plan.actions.single().id), plan.grant.revision,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, plan.inputVersion, System.currentTimeMillis(), acceptMaintenance = maintenance)

    @Test fun acceptanceIsDurableEncryptedAndDoesNotScheduleAnAlert(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan)
        assertEquals(HealthCareStage.MAINTENANCE, saved.stage); assertTrue(store.plan(plan.id)!!.maintenanceSelected)
        assertNull(store.nextReminder()); assertEquals(plan.actions.single().dueFrom, store.nextMaintenanceReview())
        HealthCareStore(context, names.care).use {
            assertEquals(saved, it.concern(saved.id)); assertEquals(plan.sources, it.plan(plan.id)!!.sources)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM concerns", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(saved.reviewNote))
        } }
        assertTrue(runCatching { accept(names, store, plan) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(saved, store.concern(saved.id))
    }
    @Test fun selectingOnlyTheActionNeverSelectsMaintenance(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan, false)
        assertEquals(HealthCareStage.WAITING_RESULTS, saved.stage); assertNull(saved.maintenance)
        assertFalse(store.plan(plan.id)!!.maintenanceSelected); assertNull(store.nextMaintenanceReview())
    }
    @Test fun deadlineReopensEvenWhenSourceEvaluationIsCachedAndSurvivesReopen(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan); val due = plan.actions.single().dueFrom!!
        assertEquals(0, HealthCareEngine.evaluate(context, names, due - 1))
        assertEquals(1, HealthCareEngine.evaluate(context, names, due))
        val reopened = store.concern(saved.id)!!
        assertEquals(HealthCareStage.REASSESS, reopened.stage); assertEquals(saved.maintenance, reopened.maintenance)
        assertEquals(0, HealthCareEngine.evaluate(context, names, due + 1)); assertNull(store.nextMaintenanceReview())
        HealthCareStore(context, names.care).use { assertEquals(reopened, it.concern(saved.id)) }
    }
    @Test fun newSourceInvalidatesMaintenanceAndRetainsAcceptedEvidence(): Unit = fixture { names, store, plan ->
        val evidence = store.revision(plan.grant.concernId, plan.grant.revision)!!
        val saved = accept(names, store, plan)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "62"),
            "kg", System.currentTimeMillis(), "resting", reference = "40-50")) }
        HealthCareEngine.evaluate(context, names)
        assertEquals(HealthCareStage.REASSESS, store.concern(saved.id)!!.stage)
        assertEquals(saved.maintenance, store.concern(saved.id)!!.maintenance)
        assertTrue(store.plan(plan.id)!!.maintenanceSelected)
        assertEquals(evidence, store.revision(saved.id, plan.grant.revision))
        assertNotEquals(evidence.assessment, store.concern(saved.id)!!.assessment)
    }
    @Test fun privacyPauseAndSourceClockRejectStaleReviewWithoutPartialWrites(): Unit = fixture { names, store, plan ->
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        val before = store.concern(plan.grant.concernId)
        assertTrue(runCatching { store.resolvePlan(plan.id, setOf(plan.actions.single().id), plan.grant.revision,
            privacy.copy(metrics = false), plan.inputVersion, System.currentTimeMillis(), acceptMaintenance = true) }.isFailure)
        assertTrue(runCatching { store.resolvePlan(plan.id, setOf(plan.actions.single().id), plan.grant.revision,
            privacy, "changed-clock", System.currentTimeMillis(), acceptMaintenance = true) }.isFailure)
        assertEquals(before, store.concern(plan.grant.concernId)); assertEquals(plan, store.plan(plan.id))
        val saved = accept(names, store, plan)
        val paused = store.update(saved.id, saved.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        HealthCareEngine.evaluate(context, names, plan.actions.single().dueUntil!!)
        assertEquals(paused, store.concern(saved.id)); assertNull(store.nextMaintenanceReview())
    }
    @Test fun schedulerReopensWithoutPostingUnapprovedNotifications(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan); val due = plan.actions.single().dueFrom!!
        val next = HealthCareReminderRuntime.reconcile(context, HealthReminderSettings(), due - 1000,
            java.time.ZoneId.of("UTC"), false, emptySet(), { error("No alert was authorized") }, {}, names)
        assertEquals(due, next)
        HealthCareReminderRuntime.reconcile(context, HealthReminderSettings(), due,
            java.time.ZoneId.of("UTC"), false, emptySet(), { error("No alert was authorized") }, {}, names)
        assertEquals(HealthCareStage.REASSESS, store.concern(saved.id)!!.stage); assertNull(store.nextReminder())
    }
    @Test fun earlierAcceptedActionCannotCauseRepeatedMaintenanceWakeups(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan)
        val now = System.currentTimeMillis()
        val due = now + 5000
        store.update(saved.id, saved.revision, "fixture_earlier_action") {
            it.copy(actions = it.actions + it.actions.single().copy(id = UUID.randomUUID().toString(),
                kind = HealthCareActionKind.CONTEXT, dueFrom = due, dueUntil = due + 5000))
        }
        assertEquals(due, store.nextMaintenanceReview())
        val next = HealthCareReminderRuntime.reconcile(context, HealthReminderSettings(), due,
            java.time.ZoneId.of("UTC"), false, emptySet(), { error("No alert was authorized") }, {}, names)
        assertNull(next); assertNull(store.nextMaintenanceReview())
        val reopened = store.concern(saved.id)!!
        assertEquals(HealthCareStage.REASSESS, reopened.stage)
        assertEquals(0, HealthCareEngine.evaluate(context, names, due + 1000))
        assertEquals(reopened, store.concern(saved.id))
    }
}
