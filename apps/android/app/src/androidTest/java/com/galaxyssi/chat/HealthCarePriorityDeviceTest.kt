package com.galaxyssi.chat

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun restoreHealthCareSchemaFive(db: SQLiteDatabase) {
    // Keep encrypted payloads intact while recreating the real pre-priority table layout.
    val columns = "id,revision,payload,updated_at,metric_key,open,stage,due_at"
    db.execSQL("CREATE TABLE legacy_concerns(id TEXT PRIMARY KEY,revision INTEGER NOT NULL,payload BLOB NOT NULL,updated_at INTEGER NOT NULL," +
        "metric_key TEXT NOT NULL UNIQUE,open INTEGER NOT NULL,stage TEXT NOT NULL,due_at INTEGER)")
    db.execSQL("INSERT INTO legacy_concerns SELECT $columns FROM concerns")
    db.execSQL("DROP TABLE concerns")
    db.execSQL("ALTER TABLE legacy_concerns RENAME TO concerns")
    db.execSQL("CREATE INDEX care_open_pages ON concerns(open,updated_at DESC,id DESC)")
    db.execSQL("CREATE INDEX care_all_pages ON concerns(updated_at DESC,id DESC)")
    db.execSQL("CREATE INDEX care_due ON concerns(open,due_at,id)")
    db.version = 5
}

class HealthCarePriorityDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthCareStore(context, names.care).use { it.configure(true, ""); test(names, it) } }
        finally { listOf(names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    private fun addReading(names: HealthOverviewDatabases) = HealthRecordStore(context, names.records).use {
        it.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "185", "diastolic" to "90"), "mmHg", System.currentTimeMillis() - 60000))
    }
    @Test fun existingEvaluationReplaysNewPolicyOnceWithoutChangingSourceIdentity(): Unit = fixture { names, store ->
        addReading(names)
        val permission = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        val key = HealthRecordStore(context, names.records).use { HealthCareEngine.inputVersion(store.settings().version,
            permission.version, it.metricVersion(HealthMetric.BLOOD_PRESSURE)) }
        store.applyEvaluation(HealthMetric.BLOOD_PRESSURE, key, store.settings().version, null, null, System.currentTimeMillis())
        assertEquals(1, HealthCareEngine.evaluate(context, names))
        val issue = store.forMetric(HealthMetric.BLOOD_PRESSURE)!!
        assertEquals(key, issue.inputVersion); assertEquals(1, HealthCarePriority.rank(issue.assessment))
        assertEquals(0, HealthCareEngine.evaluate(context, names))
        assertEquals(1, store.history(issue.id).size)
    }
    @Test fun priorityPaginationReturnsOlderWarningBeforeNewerRoutineConcerns(): Unit = fixture { names, store ->
        addReading(names); HealthCareEngine.evaluate(context, names)
        val warning = store.forMetric(HealthMetric.BLOOD_PRESSURE)!!
        HealthMetric.entries.filter { it != HealthMetric.BLOOD_PRESSURE }.forEachIndexed { i, metric ->
            val a = HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), System.currentTimeMillis(), "fixture", metric.units.first(),
                "", setOf(HealthCareSignal.REPORT_HIGH))
            store.applyEvaluation(metric, "fixture-$i", store.settings().version, null, a, warning.updatedAt + i + 1000)
        }
        assertEquals(warning.id, store.page(limit = 1).items.single().id)
        var cursor: HealthCareCursor? = null; val ids = mutableListOf<String>()
        do { val page = store.page(cursor, limit = 4); ids += page.items.map { it.id }; cursor = page.next } while (cursor != null)
        assertEquals(HealthMetric.entries.size, ids.size); assertEquals(ids.size, ids.distinct().size)
        assertEquals(warning.id, ids.first())
        store.update(warning.id, warning.revision, "pause_fixture") { it.copy(stage = HealthCareStage.PAUSED) }
        assertFalse(store.page(includePaused = false).items.any { it.id == warning.id })
        context.openOrCreateDatabase(names.care, 0, null).use { db ->
            val plan = db.rawQuery("EXPLAIN QUERY PLAN SELECT id FROM concerns WHERE open=1 ORDER BY priority DESC,updated_at DESC,id DESC LIMIT 4", null)
                .use { rows -> buildList { while (rows.moveToNext()) add(rows.getString(3)) }.joinToString() }
            assertTrue(plan.contains("care_open_pages")); assertFalse(plan.contains("TEMP B-TREE"))
        }
    }
    @Test fun dismissedMeasurementStaysDismissedAcrossRuleRefreshButNewDataIsReviewed(): Unit = fixture { names, store ->
        addReading(names); HealthCareEngine.evaluate(context, names)
        val issue = store.forMetric(HealthMetric.BLOOD_PRESSURE)!!
        store.delete(issue.id, issue.revision)
        assertEquals(issue.inputVersion, store.evaluated(issue.metric, "next-rule"))
        assertNull(store.applyEvaluation(issue.metric, issue.inputVersion, store.settings().version, null, issue.assessment,
            System.currentTimeMillis(), "next-rule"))
        addReading(names)
        assertEquals(1, HealthCareEngine.evaluate(context, names))
        assertNotEquals(issue.id, store.forMetric(issue.metric)!!.id)
    }
    @Test fun priorityIndexIsAuthenticatedAgainstEncryptedSignals(): Unit = fixture { names, store ->
        addReading(names); HealthCareEngine.evaluate(context, names)
        val issue = store.forMetric(HealthMetric.BLOOD_PRESSURE)!!
        context.openOrCreateDatabase(names.care, 0, null).use {
            it.update("concerns", ContentValues().apply { put("priority", 0) }, "id=?", arrayOf(issue.id))
        }
        assertTrue(runCatching { store.concern(issue.id) }.isFailure)
    }
    @Test fun schemaFiveUpgradePreservesConfirmedActionsRemindersAndRevision(): Unit = fixture { names, store ->
        val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
        val now = System.currentTimeMillis()
        val reminder = store.scheduleReminder(issue.id, issue.actions.first().id, issue.revision, null,
            HealthPrivacyStore(context, names.privacy).use { it.policy() }, issue.inputVersion, now + 60000, now)
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use(::restoreHealthCareSchemaFive)
        HealthCareStore(context, names.care).use { upgraded ->
            assertEquals(issue, upgraded.concern(issue.id)); assertEquals(reminder, upgraded.reminder(reminder.actionId))
            assertEquals(0, HealthCareEngine.evaluate(context, names))
            assertEquals(issue, upgraded.concern(issue.id)); assertEquals(reminder, upgraded.reminder(reminder.actionId))
        }
    }
}
