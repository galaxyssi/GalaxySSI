package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthReportReviewDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = 1_700_000_000_000L

    private fun fixture(test: (HealthOverviewDatabases, HealthReportReviewRepository) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names, HealthReportReviewRepository(context, names)) }
        finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun reportActionsAreDurableAndNeverConfirmMeasurements() = fixture { names, repo ->
        val (job, original) = overviewOcrJob(context, names, now - 3000)
        val pending = HealthReminderStore(context, names.reminders).use { store ->
            val report = repo.page(store, HealthReminderFilter.PENDING, null, now).rows.single()
            assertEquals(job.id, report.id)
            assertEquals(HealthOverviewReviewKind.OCR, report.kind)
            repo.act(store, report, HealthReminderAction.SNOOZE, now)
            assertTrue(runCatching { repo.act(store, report, HealthReminderAction.COMPLETE, now) }.exceptionOrNull() is HealthReminderConflict)
            report
        }
        val later = now + HealthReminderPolicy.HOUR
        HealthReminderStore(context, names.reminders).use { store ->
            val snoozed = repo.page(store, HealthReminderFilter.PENDING, null, now).rows.single()
            assertEquals(HealthReminderState.SNOOZED, snoozed.state(now))
            assertEquals(HealthReminderState.PENDING, snoozed.state(later))
            repo.act(store, snoozed, HealthReminderAction.COMPLETE, later)
            assertTrue(repo.page(store, HealthReminderFilter.PENDING, null, later).rows.isEmpty())
            assertEquals(pending.id, repo.page(store, HealthReminderFilter.HANDLED, null, later).rows.single().id)
            assertEquals(1, repo.page(store, HealthReminderFilter.ALL, null, later).rows.size)
            store.save(store.settings().copy(reportReviews = false), later)
            assertTrue(runCatching { store.actReport(pending.id, store.reportDisposition(pending.id),
                HealthReminderAction.COMPLETE, later) }.exceptionOrNull() is HealthReminderConflict)
        }
        HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use {
            assertEquals(HealthImportState.REVIEW, it.job(job.id)?.state)
            assertEquals(original, it.originalForJob(job.id))
            assertNotNull(it.page(job.id, 1))
        }
    }

    @Test fun paginationKeepsSeparateJobsWithIdenticalSourceBytesAndTimestamps() = fixture { names, repo ->
        val ids = (0..30).map { overviewOcrJob(context, names, now - 1000).first.id }.sortedDescending()
        HealthReminderStore(context, names.reminders).use { store ->
            val first = repo.page(store, HealthReminderFilter.PENDING, null, now)
            val second = repo.page(store, HealthReminderFilter.PENDING, requireNotNull(first.next), now)
            assertEquals(ids, (first.rows + second.rows).map { it.id })
            assertNull(second.next)
        }
    }

    @Test fun reminderSchemaUpgradePreservesExistingSettings() = fixture { names, _ ->
        val saved = HealthReminderStore(context, names.reminders).use {
            it.save(it.settings().copy(enabled = true, minute = 653, sleepChanges = true), now)
        }
        android.database.sqlite.SQLiteDatabase.openDatabase(context.getDatabasePath(names.reminders).path, null,
            android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use {
            it.execSQL("DROP TABLE report_reviews")
            it.version = 2
        }
        HealthReminderStore(context, names.reminders).use {
            assertEquals(saved, it.settings())
            assertEquals(HealthReportReviewDisposition(), it.reportDisposition(UUID.randomUUID().toString()))
        }
    }

    @Test fun tableReminderIsHandledAfterSaveAndDoesNotReopenOnUndo() = fixture { names, repo ->
        val id = UUID.randomUUID().toString()
        val original = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            originals.createJob(HealthImportJob(id, "content://fixture/table", now))
            originals.importOriginal(id, "synthetic table".byteInputStream(), "fixture.csv", "text/csv", "file").also { source ->
                originals.updateJob(id) { it.copy(state = HealthImportState.TABLE_REVIEW, originalId = source.id) }
            }
        }
        HealthReminderStore(context, names.reminders).use { reminders ->
            HealthTableStore(context, names.records).use { tables ->
                val row = mapOf("time" to "2026-09-01T08:10:00Z", "systolic" to "124", "diastolic" to "82", "unit" to "mmHg")
                tables.begin(id, original, "csv")
                tables.append(id, listOf(HealthTableRow(1L, row)))
                tables.finishReading(id, row.keys.toList())
                val pending = repo.page(reminders, HealthReminderFilter.PENDING, null, now).rows.single()
                assertEquals(id, pending.id)
                assertEquals(HealthOverviewReviewKind.TABLE, pending.kind)
                val mapped = requireNotNull(tables.batch(id))
                tables.mapping(id, mapped.mappingRevision, mapped.mapping.copy(zone = "UTC"), true)
                while (tables.step(id)) Unit
                tables.confirmSave(id, requireNotNull(tables.batch(id)).mappingRevision)
                while (tables.step(id)) Unit
                assertTrue(repo.page(reminders, HealthReminderFilter.PENDING, null, now).rows.isEmpty())
                assertEquals(id, repo.page(reminders, HealthReminderFilter.HANDLED, null, now).rows.single().id)
                tables.undo(id)
                while (tables.step(id)) Unit
                assertTrue(repo.page(reminders, HealthReminderFilter.PENDING, null, now).rows.isEmpty())
                assertEquals(id, repo.page(reminders, HealthReminderFilter.HANDLED, null, now).rows.single().id)
            }
        }
    }

    @Test fun nativeCenterOpensTheExactReportAndShowsThePreference() = fixture { names, _ ->
        assumeFalse("Reminder UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = overviewOcrJob(context, names, now).first
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val capture = instrumentation.addMonitor(HealthCaptureActivity::class.java.name, null, false)
        try {
            val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_test_db", names.reminders)
            ActivityScenario.launch<HealthReminderActivity>(intent).use { scenario ->
                val tag = "health-report-review-${job.id}"
                await(scenario, tag)
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(tag).performClick()) }
                val review = requireNotNull(instrumentation.waitForMonitorWithTimeout(capture, 5000))
                assertEquals(job.id, review.intent.getStringExtra("health_job"))
                assertEquals(names.fixture, review.intent.getStringExtra("health_review_test_id"))
                instrumentation.runOnMainSync { review.finish() }
                await(scenario, "health-reminder-settings")
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>("health-reminder-settings").performClick()) }
                await(scenario, "health-report-review-enabled")
                scenario.onActivity {
                    val toggle = it.window.decorView.findViewWithTag<android.widget.Switch>("health-report-review-enabled")
                    assertTrue(toggle.isChecked)
                    toggle.performClick()
                    assertFalse(toggle.isChecked)
                    assertTrue(it.window.decorView.findViewWithTag<View>("health-reminder-save").performClick())
                }
                await(scenario, "health-reminder-settings")
                scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>(tag)) }
            }
        } finally { instrumentation.removeMonitor(capture) }
    }

    private fun await(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 10_000L
        do {
            var found = false
            scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag) != null }
            if (found) return
            SystemClock.sleep(30)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing view: $tag")
    }
}
