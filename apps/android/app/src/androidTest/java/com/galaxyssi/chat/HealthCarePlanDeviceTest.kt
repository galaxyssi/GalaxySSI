package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal object HealthCarePlanTestFixture {
    fun propose(context: android.content.Context, names: HealthOverviewDatabases): HealthCarePlan {
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"),
            "mmol/L", now - 1000, reference = "4-6")) }
        HealthCareStore(context, names.care).use { it.configure(true, it.settings().version) }
        HealthCareEngine.evaluate(context, names)
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        return HealthCareStore(context, names.care).use { store ->
            val concern = store.forMetric(HealthMetric.GLUCOSE)!!
            val bound = store.bindDiscussion(concern.id, concern.revision, UUID.randomUUID().toString())
            val grant = HealthCareDiscussionGrant(bound.conversationId, UUID.randomUUID().toString(), bound.id, bound.revision,
                store.settings().version, privacy.version, "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
            store.approveDiscussion(grant)
            val input = mapOf("uncertainty" to "仅用于隔离测试，尚未确认检测条件。", "sources" to listOf(mapOf(
                "title" to "合成测试依据", "url" to "https://example.test/health", "version" to "fixture-v1",
                "applicability" to "隔离测试，不是医学建议。")), "actions" to listOf(mapOf("kind" to "CONTEXT",
                "description" to "核对报告中的检测条件", "rationale" to "确认资料是否完整，仅用于界面测试。", "source_index" to 0,
                "due_from" to "", "due_until" to ""), mapOf("kind" to "CLINICIAN_DISCUSSION", "description" to "整理下次讨论的问题",
                "rationale" to "记录尚未明确的问题，仅用于界面测试。", "source_index" to 0, "due_from" to "", "due_until" to "")))
            store.proposePlan(HealthCarePlanPolicy.parse(input, grant, bound, now))
        }
    }
}

class HealthCarePlanDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCarePlan) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { val plan = HealthCarePlanTestFixture.propose(context, names); HealthCareStore(context, names.care).use { test(names, it, plan) } }
        finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    private fun accept(names: HealthOverviewDatabases, store: HealthCareStore, plan: HealthCarePlan, selected: Set<String> = setOf(plan.actions.first().id)) =
        store.resolvePlan(plan.id, selected, plan.grant.revision, HealthPrivacyStore(context, names.privacy).use { it.policy() },
            plan.inputVersion, System.currentTimeMillis())

    @Test fun pendingDraftIsEncryptedDurableAndDoesNotChangeConcernOrScheduleAnything(): Unit = fixture { names, store, plan ->
        val prior = store.concern(plan.grant.concernId)!!
        assertEquals(plan.grant.revision, prior.revision); assertTrue(prior.actions.isEmpty()); assertNull(store.nextDue())
        HealthCareStore(context, names.care).use { assertEquals(plan, it.plan(plan.id)); assertEquals(listOf(plan), it.pendingPlans(prior.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM plans", null).use { row ->
                assertTrue(row.moveToFirst()); assertFalse(row.getBlob(0).toString(Charsets.UTF_8).contains(plan.uncertainty))
            }
        }
    }
    @Test fun replayRetainsOneDraftButCannotRewriteItsContent(): Unit = fixture { _, store, plan ->
        repeat(5) { assertEquals(plan, store.proposePlan(plan)) }
        assertEquals(1, store.pendingPlans(plan.grant.concernId).size)
        assertTrue(runCatching { store.proposePlan(plan.copy(requestHash = "b".repeat(64))) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(plan, store.plan(plan.id))
    }
    @Test fun acceptanceIsAtomicSelectiveAndRejectsDuplicateButtonDelivery(): Unit = fixture { names, store, plan ->
        val before = store.history(plan.grant.concernId).size
        val next = accept(names, store, plan)
        assertEquals(1, next.actions.size); assertEquals(plan.actions.first().id, next.actions.single().id)
        assertEquals(HealthCareActionState.CONFIRMED, next.actions.single().state)
        assertEquals(HealthCarePlanState.ACCEPTED, store.plan(plan.id)!!.state); assertTrue(store.pendingPlans(next.id).isEmpty())
        assertEquals(before + 1, store.history(next.id).size)
        assertTrue(runCatching { accept(names, store, plan) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(next, store.concern(next.id)); assertEquals(before + 1, store.history(next.id).size)
    }
    @Test fun invalidSelectionRollsBackBothConcernAndDraft(): Unit = fixture { names, store, plan ->
        val before = store.concern(plan.grant.concernId)
        assertTrue(runCatching { accept(names, store, plan, setOf(UUID.randomUUID().toString())) }.isFailure)
        assertEquals(before, store.concern(plan.grant.concernId)); assertEquals(plan, store.plan(plan.id))
    }
    @Test fun newMeasurementInvalidatesPendingDraftBeforeReconciliation(): Unit = fixture { names, store, plan ->
        HealthRecordStore(context, names.records).use { records ->
            records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.4"), "mmol/L", System.currentTimeMillis(), reference = "4-6"))
            val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
            val version = HealthCareEngine.inputVersion(store.settings().version, privacy.version, records.metricVersion(HealthMetric.GLUCOSE))
            assertTrue(runCatching { store.resolvePlan(plan.id, setOf(plan.actions.first().id), plan.grant.revision, privacy, version,
                System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        }
        assertTrue(store.concern(plan.grant.concernId)!!.actions.isEmpty())
    }
    @Test fun revocationPauseAndContextChangeCannotAcceptStalePlan(): Unit = fixture { names, store, plan ->
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        assertTrue(runCatching { store.resolvePlan(plan.id, setOf(plan.actions.first().id), plan.grant.revision,
            privacy.copy(metrics = false), plan.inputVersion, System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        store.update(plan.grant.concernId, plan.grant.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        assertTrue(runCatching { accept(names, store, plan) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(plan, store.plan(plan.id))
    }
    @Test fun dismissalNeverAddsActionsAndDeletionRemovesPlanPayload(): Unit = fixture { _, store, plan ->
        store.dismissPlan(plan.id, System.currentTimeMillis()); store.dismissPlan(plan.id, System.currentTimeMillis())
        assertEquals(HealthCarePlanState.DISMISSED, store.plan(plan.id)!!.state)
        val issue = store.concern(plan.grant.concernId)!!; assertTrue(issue.actions.isEmpty())
        store.delete(issue.id, issue.revision); assertNull(store.plan(plan.id))
        assertEquals(issue.id, store.discussion(plan.grant.conversationId))
    }
    @Test fun indexedOwnerAndStateCannotBeTampered(): Unit = fixture { names, store, plan ->
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.update("plans", ContentValues().apply { put("state", "ACCEPTED") }, "id=?", arrayOf(plan.id))
        }
        assertTrue(runCatching { store.plan(plan.id) }.isFailure)
    }
    @Test fun schemaTwoUpgradePreservesExistingDiscussionAndConcern(): Unit = fixture { names, store, plan ->
        val issue = store.concern(plan.grant.concernId); store.close()
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.execSQL("DROP TABLE action_reminders"); db.execSQL("DROP TABLE plans"); db.version = 2 }
        HealthCareStore(context, names.care).use {
            assertEquals(issue, it.concern(plan.grant.concernId)); assertEquals(plan.grant, it.discussionGrant(plan.id))
            assertEquals(plan, it.proposePlan(plan))
        }
    }
}
