package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.widget.CheckBox
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOcrSourceContextDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val expected = Instant.parse("2025-11-03T00:15:00Z").toEpochMilli()
    private val sample = "Sample collected at: 2025-11-03T08:15:00+08:00"
    private val owner = "Synthetic Test Owner"

    @Test fun explicitSourceTimeDoesNotConfirmOwnershipOrWriteAnyUnselectedMeasurement() = fixture { names ->
        val (job, drafts) = report(names, sample, "Weight: 62")
        val glucose = drafts.single { it.metric == HealthMetric.GLUCOSE }
        val weight = drafts.single { it.metric == HealthMetric.WEIGHT }
        val glucoseId = requireNotNull(glucose.evidence).candidateId
        val weightId = requireNotNull(weight.evidence).candidateId
        openReport(names, job).use { review ->
            val label = "health-ocr-source-owner"
            await("report source metadata") {
                var shown = false
                review.onActivity { shown = it.window.decorView.findViewWithTag<TextView>(label)?.text?.contains(owner) == true }
                shown
            }
            review.onActivity { activity ->
                assertTrue(activity.window.decorView.findViewWithTag<TextView>("health-ocr-source-time").text.contains("08:15:00+08:00"))
                assertNull(activity.window.decorView.findViewWithTag<View>("health-review-pick-$weightId"))
            }
            val editor = edit(review, glucoseId)
            awaitEditor(editor)
            instrumentation.runOnMainSync {
                val root = editor.window.decorView
                val source = requireNotNull(root.findViewWithTag<View>("health-ocr-use-source-time"))
                val consent = root.findViewWithTag<CheckBox>("health-confirm-source")
                assertEquals(0L, editor.editor?.snapshot()?.measuredAt)
                assertFalse(consent.isChecked)
                consent.isChecked = true
                assertTrue(source.performClick())
                assertEquals(expected, editor.editor?.snapshot()?.measuredAt)
                assertFalse(consent.isChecked)
                val save = root.findViewWithTag<View>("health-save")
                assertTrue(save.performClick())
                assertTrue(root.findViewWithTag<TextView>("health-validation").isShown)
                consent.isChecked = true
                assertNull("Verified editor draft should be valid", HealthObservationPolicy.validate(requireNotNull(editor.editor).snapshot()))
                assertTrue(save.performClick())
            }
            await("verified draft stored") {
                HealthRecordStore(context, names.records).use { records ->
                    val stored = records.draft(HealthRecordStore.draftKey(glucose))
                    stored?.measuredAt == expected && stored.evidence?.confirmed == true
                }
            }
            val tag = "health-review-pick-$glucoseId"
            await("validated item without a committed measurement") {
                var shown = false
                review.onActivity { shown = it.window.decorView.findViewWithTag<View>(tag) != null }
                shown
            }
            HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
            review.onActivity {
                val root = it.window.decorView
                assertTrue(root.findViewWithTag<CheckBox>(tag).performClick())
                val save = root.findViewWithTag<View>("health-review-batch-save")
                assertFalse(save.isEnabled)
                root.findViewWithTag<CheckBox>("health-review-batch-consent").isChecked = true
                assertTrue(save.isEnabled)
                assertTrue(save.performClick())
            }
            await("one verified measurement") { HealthRecordStore(context, names.records).use { it.count() == 1L } }
            HealthRecordStore(context, names.records).use { records ->
                val saved = records.page().records.single()
                assertEquals(HealthMetric.GLUCOSE, saved.draft.metric)
                assertEquals(expected, saved.draft.measuredAt)
                assertTrue(requireNotNull(saved.draft.evidence).confirmed)
                assertFalse(saved.draft.evidence!!.rawText.contains(owner))
                assertEquals("", saved.draft.note)
                assertEquals(1L, records.count())
            }
        }
    }

    @Test fun conflictingTimesAreVisibleButCannotBeAppliedOrSavedWithoutManualTime() = fixture { names ->
        val (job, drafts) = report(names, sample, "Measured at: 2025-11-04 09:00")
        val candidate = requireNotNull(drafts.single().evidence).candidateId
        openReport(names, job).use { review ->
            val editor = edit(review, candidate)
            try {
                awaitEditor(editor)
                instrumentation.runOnMainSync {
                    val root = editor.window.decorView
                    val time = root.findViewWithTag<TextView>("health-ocr-source-time").text
                    assertTrue(time.contains("2025-11-03"))
                    assertTrue(time.contains("2025-11-04"))
                    assertNull(root.findViewWithTag<View>("health-ocr-use-source-time"))
                    root.findViewWithTag<CheckBox>("health-confirm-source").isChecked = true
                    assertTrue(root.findViewWithTag<View>("health-save").performClick())
                    val validation = root.findViewWithTag<TextView>("health-validation")
                    assertTrue(validation.isShown)
                    assertEquals(editor.getString(R.string.health_invalid_time), validation.text.toString())
                    assertEquals(0L, editor.editor?.snapshot()?.measuredAt)
                }
                HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
            } finally { instrumentation.runOnMainSync { editor.finish() } }
        }
    }

    private fun report(names: HealthOverviewDatabases, vararg extra: String): Pair<String, List<HealthDraft>> {
        val id = UUID.randomUUID().toString()
        val bytes = ByteArrayOutputStream().use { output ->
            val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
            try { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)); output.toByteArray() }
            finally { bitmap.recycle() }
        }
        return HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
            store.createJob(HealthImportJob(id, "content://fixture/ocr-context", System.currentTimeMillis()))
            val original = store.importOriginal(id, bytes.inputStream(), "synthetic.png", "image/png", "file")
            val lines = listOf("Patient name: $owner", "Glucose: 5.6 mmol/L") + extra
            val page = HealthOcrPage(1, 100, 100,
                lines.mapIndexed { index, value -> HealthOcrLine(value, listOf(1, index * 14, 95, index * 14 + 12)) })
            store.savePage(id, page)
            val job = requireNotNull(store.updateJob(id) { it.copy(state = HealthImportState.REVIEW, originalId = original.id) })
            id to HealthOcrCandidates.suggest(job, original, page)
        }
    }
    private fun openReport(names: HealthOverviewDatabases, job: String) =
        ActivityScenario.launch<HealthCaptureActivity>(Intent(context, HealthCaptureActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_job", job))

    private fun edit(review: ActivityScenario<HealthCaptureActivity>, candidate: String): HealthCenterActivity {
        val monitor = instrumentation.addMonitor(HealthCenterActivity::class.java.name, null, false)
        try {
            await("edit candidate $candidate") {
                var clicked = false
                review.onActivity {
                    clicked = it.window.decorView.findViewWithTag<View>("health-review-edit-$candidate")?.performClick() == true
                }
                clicked
            }
            return requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000)) as HealthCenterActivity
        } finally { instrumentation.removeMonitor(monitor) }
    }
    private fun awaitEditor(editor: HealthCenterActivity) = await("source editor") {
        var ready = false
        instrumentation.runOnMainSync {
            val consent = editor.window.decorView.findViewWithTag<View>("health-confirm-source")
            ready = consent?.isLaidOut == true && editor.editor?.snapshot()?.unit == "mmol/L"
        }
        ready
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse("OCR source review requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun await(label: String, condition: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 12_000
        do { if (condition()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < end)
        fail("Missing $label")
    }
}
