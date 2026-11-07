package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal object HealthCareTargetTestFixture {
    fun input(base: AgentNativeJsonObject, unresolved: Boolean = false): AgentNativeJsonObject = base + mapOf("target_proposal" to mapOf(
        "field" to "glucose", "low" to "4.0", "high" to "6.0", "unit" to "mmol/L", "low_inclusive" to true, "high_inclusive" to false,
        "rationale" to "合成界面测试范围，不是医学建议；用户确认不代表医生认可。", "source_index" to 0,
        "applicability" to mapOf("mode" to "INDIVIDUALIZED", "checks" to listOf(mapOf("field" to "metric", "operator" to "EQUALS",
            "expected" to "GLUCOSE", "source_index" to 0)), "missing_information" to if (unresolved) listOf("需确认检测背景") else emptyList<String>(),
            "conflicts" to emptyList<String>())))
}

class HealthCareTargetDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCarePlan) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val plan = HealthCarePlanTestFixture.propose(context, names) { HealthCareTargetTestFixture.input(it) }
            HealthCareStore(context, names.care).use { test(names, it, plan) }
        } finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    private fun accept(names: HealthOverviewDatabases, store: HealthCareStore, plan: HealthCarePlan, actions: Set<String> = emptySet()) =
        store.resolvePlan(plan.id, actions, plan.grant.revision, HealthPrivacyStore(context, names.privacy).use { it.policy() },
            plan.inputVersion, System.currentTimeMillis(), acceptTarget = true)

    @Test fun targetOnlyAcceptanceIsEncryptedDurableAndRetainsReceipt(): Unit = fixture { names, store, plan ->
        assertNull(store.concern(plan.grant.concernId)!!.target)
        val saved = accept(names, store, plan)
        assertTrue(saved.actions.isEmpty()); assertTrue(store.plan(plan.id)!!.targetSelected); assertNull(store.nextDue())
        HealthCareStore(context, names.care).use {
            assertEquals(saved, it.concern(saved.id)); assertEquals(plan.sources, it.plan(saved.target!!.planId)!!.sources)
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM concerns", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(saved.target!!.rationale))
        } }
        assertTrue(store.history(saved.id).any { it.target == saved.target })
    }
    @Test fun duplicateAcceptanceDoesNotDuplicateTargetHistory(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan); val history = store.history(saved.id)
        assertTrue(runCatching { accept(names, store, plan) }.exceptionOrNull() is HealthCareConflict)
        assertEquals(saved, store.concern(saved.id)); assertEquals(history, store.history(saved.id))
    }
    @Test fun selectionCanKeepActionsWithoutAdoptingTarget(): Unit = fixture { names, store, plan ->
        val next = store.resolvePlan(plan.id, setOf(plan.actions.first().id), plan.grant.revision,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, plan.inputVersion, System.currentTimeMillis())
        assertNull(next.target); assertFalse(store.plan(plan.id)!!.targetSelected); assertEquals(1, next.actions.size)
    }
    @Test fun revocationCancelsRelatedReminderAndKeepsTargetHistory(): Unit = fixture { names, store, plan ->
        val saved = accept(names, store, plan, setOf(plan.actions.first().id)); val action = saved.actions.single()
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }; val now = System.currentTimeMillis()
        store.scheduleReminder(saved.id, action.id, saved.revision, null, privacy, plan.inputVersion, now + 3600000, now)
        val revoked = store.revokeTarget(saved.id, saved.revision, privacy)
        assertNull(revoked.target); assertEquals(2, revoked.targetRevision)
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(action.id)!!.state)
        assertFalse(HealthCareFollowUpPolicy.eligible(revoked, action, store.settings(), privacy, plan.inputVersion))
        assertTrue(store.history(saved.id).any { it.target == saved.target })
        assertTrue(runCatching { store.revokeTarget(saved.id, saved.revision, privacy) }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun targetReplacementRequiresFreshGrantAndKeepsBothVersions(): Unit = fixture { names, store, plan ->
        val first = accept(names, store, plan)
        val now = System.currentTimeMillis()
        val grant = plan.grant.copy(turnId = UUID.randomUUID().toString(), revision = first.revision, approvedAt = now)
        store.approveDiscussion(grant)
        val evidence = plan.sources.single().evidence!!.copy(id = UUID.randomUUID().toString(), grant = grant, observedAt = now)
        store.recordEvidence(listOf(evidence))
        val nextPlan = plan.copy(grant = grant, createdAt = now, sources = listOf(plan.sources.single().copy(evidenceId = evidence.id, evidence = evidence)),
            target = plan.target!!.copy(high = "5.9"), requestHash = "c".repeat(64))
        store.proposePlan(nextPlan)
        assertEquals(first.target, store.concern(first.id)!!.target)
        val second = accept(names, store, nextPlan)
        assertEquals("5.9", second.target!!.high); assertEquals(2, second.targetRevision)
        assertTrue(store.history(first.id).any { it.target == first.target })
    }
    @Test fun newMeasurementAndPermissionRevocationBlockStaleAcceptance(): Unit = fixture { names, store, plan ->
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        assertTrue(runCatching { store.resolvePlan(plan.id, emptySet(), plan.grant.revision, privacy.copy(profile = false),
            plan.inputVersion, System.currentTimeMillis(), true) }.exceptionOrNull() is HealthCareConflict)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.4"),
            "mmol/L", System.currentTimeMillis(), reference = "4-6")) }
        HealthCareEngine.evaluate(context, names)
        assertTrue(runCatching { accept(names, store, plan) }.exceptionOrNull() is HealthCareConflict)
        assertNull(store.concern(plan.grant.concernId)!!.target)
    }
}
