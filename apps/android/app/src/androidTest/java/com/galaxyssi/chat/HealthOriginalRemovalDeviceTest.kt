package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.text.format.Formatter
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOriginalRemovalDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val now = System.currentTimeMillis()

    @Test fun sharedDatabaseRevalidatesPagedLinksAndRetainsTheArchiveWhenRemovingAReviewCopy() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            HealthOriginalStore(context, names.originals, names.originalRoot(context), sharedRecords = records).use { originals ->
                val job = UUID.randomUUID().toString()
                originals.createJob(HealthImportJob(job, "content://fixture/archive", now))
                val archive = originals.importOriginal(job, "original report".byteInputStream(), "report.pdf", "application/pdf", "file")
                val reviewJob = UUID.randomUUID().toString()
                originals.createJob(HealthImportJob(reviewJob, "content://fixture/review", now, keepOriginal = false))
                val review = originals.importOriginal(reviewJob, "original report".byteInputStream(), "review.pdf", "application/pdf", "file")
                assertTrue(review.reviewOnly)
                repeat(34) { addRecord(records, review, reviewJob, it) }
                val preview = HealthOriginalRemoval.preview(originals, records, review)
                assertEquals(34L, preview.linkedMeasurements)
                addRecord(records, review, reviewJob, 34)
                assertTrue(runCatching { HealthOriginalRemoval.confirm(originals, records, preview) }.exceptionOrNull() is HealthOriginalRemovalChanged)
                assertTrue(originals.present(review))
                val refreshed = HealthOriginalRemoval.preview(originals, records, review)
                assertEquals(35L, refreshed.linkedMeasurements)
                HealthOriginalRemoval.confirm(originals, records, refreshed)
                assertFalse(originals.present(review))
                assertTrue(originals.reviewOriginalIds("").isEmpty())
                assertTrue(originals.present(archive))
                assertEquals(review, originals.originalForJob(reviewJob))
                assertEquals(35L, records.count())
            }
        }
    }

    @Test fun originalDetailShowsExactScopeAndLeavesRecordsAfterConfirmedRemoval() = fixture { names ->
        assumeFalse("Original removal UI requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val (job, original) = overviewOcrJob(context, names, now - 60_000)
        val saved = HealthRecordStore(context, names.records).use { addRecord(it, original, job.id, 0) }
        val intent = Intent(context, HealthCaptureActivity::class.java).putHealthNavigationFixture(names).putExtra("original", original.id)
        ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
            val tag = "health-original-remove"
            await("remove action") {
                var clicked = false
                scenario.onActivity {
                    clicked = it.hasWindowFocus() && it.window.decorView.findViewWithTag<View>(tag)?.performClick() == true
                }
                clicked
            }
            val expected = context.getString(R.string.health_remove_original_preview, original.name,
                Formatter.formatShortFileSize(context, original.size), 1L)
            await("scoped confirmation") { onMain {
                WindowInspector.getGlobalWindowViews().any {
                    it.findViewById<TextView>(android.R.id.message)?.text?.toString() == expected
                }
            } }
            clickDialog(android.R.id.button2)
            assertTrue(present(names, original))
            await("remove action after cancel") {
                var clicked = false
                scenario.onActivity {
                    clicked = it.hasWindowFocus() && it.window.decorView.findViewWithTag<View>(tag)?.performClick() == true
                }
                clicked
            }
            clickDialog(android.R.id.button1)
            await("file deletion") { !present(names, original) }
            await("original no longer opens") {
                var gone = false
                scenario.onActivity { gone = it.window.decorView.findViewWithTag<View>("health-open-original") == null }
                gone
            }
        }
        HealthRecordStore(context, names.records).use {
            assertEquals(saved, it.record(saved.id))
            assertEquals(original.id, it.originalPage(original.id).records.single().draft.evidence?.originalId)
        }
        HealthPrivacyStore(context, names.privacy).use {
            val row = it.page().entries.single { event -> event.scope.purpose == HealthAccessPurpose.DELETE_ORIGINAL_BYTES }
            assertEquals(HealthAccessOutcome.COMPLETE, row.outcome)
            assertFalse(row.scope.json().toString().contains(original.name))
            assertFalse(row.scope.json().toString().contains(original.id))
        }
    }

    private fun addRecord(records: HealthRecordStore, original: HealthOriginal, job: String, index: Int): HealthObservation {
        val evidence = HealthEvidence(original.id, job, "candidate-$index", original.sha256, 1, "120/80", confirmed = true)
        return (records.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
            measuredAt = now - 120_000 - index * 1000L, evidence = evidence)) as HealthSaveResult.Saved).record
    }
    private fun present(names: HealthOverviewDatabases, original: HealthOriginal) =
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { it.present(original) }
    private fun clickDialog(id: Int) = await("confirmation button") { onMain {
        WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewById<View>(id) }.lastOrNull()?.performClick() == true
    } }
    private fun onMain(block: () -> Boolean): Boolean {
        var found = false
        instrumentation.runOnMainSync { found = block() }
        return found
    }
    private fun await(label: String, ready: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 12_000
        do {
            if (ready()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < end)
        fail("Missing $label")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
}
