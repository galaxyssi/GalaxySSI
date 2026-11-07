package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal object HealthCareApplicabilityTestFixture {
    fun input(original: AgentNativeJsonObject, conflict: Boolean = false): AgentNativeJsonObject {
        @Suppress("UNCHECKED_CAST") val actions = original.getValue("actions") as List<AgentNativeJsonObject>
        @Suppress("UNCHECKED_CAST") val sources = original.getValue("sources") as List<AgentNativeJsonObject>
        val review = mapOf("mode" to "INDIVIDUALIZED", "checks" to listOf(mapOf("field" to "adult",
            "operator" to "EQUALS", "expected" to "YES", "source_index" to 0)),
            "missing_information" to listOf("仅用于隔离测试：检测条件尚未核对"),
            "conflicts" to if (conflict) listOf(mapOf("source_indices" to listOf(0, 1),
                "detail" to "合成来源对适用条件的描述不同", "next_step" to "核对原文适用人群后再与医生讨论")) else emptyList())
        return original + mapOf("actions" to listOf(actions[0] + mapOf("kind" to "RECHECK", "applicability" to review), actions[1]),
            "sources" to if (conflict) sources + (sources[0] + mapOf("title" to "另一段合成依据",
                "supporting_quote" to "discuss uncertain results with a clinician.")) else sources)
    }
}

class HealthCareApplicabilityDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(conflict: Boolean = false, run: (HealthOverviewDatabases, HealthCarePlan) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { run(names, HealthCarePlanTestFixture.propose(context, names) { HealthCareApplicabilityTestFixture.input(it, conflict) }) }
        finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    @Test fun blockedClinicalActionCannotBeAcceptedAndTransactionLeavesOtherActionsUntouched(): Unit = fixture { names, plan ->
        HealthCareStore(context, names.care).use { store ->
            val issue = store.concern(plan.grant.concernId)!!
            val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
            assertThrows(IllegalArgumentException::class.java) {
                store.resolvePlan(plan.id, plan.actions.map { it.id }.toSet(), issue.revision, privacy, plan.inputVersion, System.currentTimeMillis())
            }
            assertEquals(issue, store.concern(issue.id)); assertEquals(plan, store.plan(plan.id)); assertNull(store.nextDue())
            val accepted = store.resolvePlan(plan.id, setOf(plan.actions[1].id), issue.revision, privacy, plan.inputVersion, System.currentTimeMillis())
            assertEquals(listOf(plan.actions[1].id), accepted.actions.map { it.id }); assertNull(store.nextDue())
        }
    }
    @Test fun sourceConflictsAndConditionsSurviveEncryptedReopen(): Unit = fixture(true) { names, plan ->
        HealthCareStore(context, names.care).use { store ->
            assertEquals(plan, store.plan(plan.id))
            val issue = store.concern(plan.grant.concernId)!!
            assertEquals(HealthCareApplicabilityStatus.CONFLICT, HealthCareApplicabilityPolicy.status(plan.applicability[plan.actions[0].id], issue))
            assertFalse(HealthCareApplicabilityPolicy.canAccept(plan, issue, plan.actions[0]))
        }
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM plans", null).use { row ->
                assertTrue(row.moveToFirst())
                val raw = row.getBlob(0).toString(Charsets.UTF_8)
                assertFalse(raw.contains("INDIVIDUALIZED")); assertFalse(raw.contains("合成来源"))
            }
        }
    }
}
