package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthRecordCenterDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun firstUseAndFunctionMenuLeadToFourNativeEntryPointsAndBack() = fixture { names ->
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS, false, it.policy().version) }
        ActivityScenario.launch<HealthCenterActivity>(intent(names)).use { scenario ->
            click(scenario, "health-first-add")
            awaitTag(scenario, "health-record-center-no-review")
            awaitTag(scenario, "health-record-center-no-records")
            scenario.onActivity { activity ->
                val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup
                assertEquals(2, root.childCount)
                val buttons = listOf("camera", "manual", "import", "sources").map {
                    requireNotNull(activity.body.findViewWithTag<View>("health-record-center-$it"))
                }
                assertTrue(buttons.all { it.isClickable && it.isFocusable })
                assertNotSame(buttons[0].parent, buttons[2].parent)
                val configuration = activity.resources.configuration
                if (configuration.screenWidthDp >= 600 && configuration.fontScale <= 1.7f) {
                    assertSame(buttons[0].parent, buttons[1].parent)
                    assertSame(buttons[2].parent, buttons[3].parent)
                }
            }
            click(scenario, "health-record-center-manual")
            awaitTag(scenario, "health-field-systolic")
            back(scenario)
            click(scenario, "health-record-center-import")
            awaitTag(scenario, "health-import-center")
            back(scenario)
            val camera = capture(HealthCameraActivity::class.java) { click(scenario, "health-record-center-camera") }
            assertEquals("report", camera.getStringExtra("capture_mode"))
            assertFalse(camera.getBooleanExtra(HEALTH_KEEP_ORIGINAL, true))
            awaitTag(scenario, "health-record-center")
            val sources = capture(HealthSourcesActivity::class.java) { click(scenario, "health-record-center-sources") }
            assertEquals(names.fixture, sources.getStringExtra("health_sources_test_id"))
            capture(HealthDataFilesActivity::class.java) { click(scenario, "health-record-center-data") }
            capture(HealthCaptureActivity::class.java) { click(scenario, "health-record-center-tasks") }.also {
                assertNull(it.getStringExtra("health_capture_entry"))
            }
            back(scenario)
            awaitTag(scenario, "health-first-add")
            click(scenario, "health-functions")
            click(scenario, "health-functions-record-center")
            awaitTag(scenario, "health-record-center")
            scenario.recreate()
            awaitTag(scenario, "health-record-center")
            back(scenario)
            awaitTag(scenario, "health-functions-record-center")
        }
    }

    @Test fun pendingImportsAreSeparateFromBoundedCurrentMeasurementsAndOpenExactSources() = fixture { names ->
        val now = System.currentTimeMillis()
        val (ocr, original) = overviewOcrJob(context, names, now - 20_000L)
        val table = pendingTable(names, now - 10_000L)
        val measurements = HealthRecordStore(context, names.records).use { records ->
            (1..7).map { index ->
                val draft = HealthDraft(values = mapOf("systolic" to "124", "diastolic" to "82"), measuredAt = now - index * 60_000L)
                (records.save(draft) as HealthSaveResult.Saved).record
            }.also { assertTrue(records.delete(it.first().id, it.first().revision)) }
        }
        ActivityScenario.launch<HealthCenterActivity>(intent(names)).use { scenario ->
            click(scenario, "health-functions")
            click(scenario, "health-functions-record-center")
            val ocrTag = "health-record-center-review-${ocr.id}"
            val tableTag = "health-record-center-review-$table"
            val latest = "health-record-center-record-${measurements[1].id}"
            awaitTag(scenario, latest)
            scenario.onActivity {
                val tags = descendants(it.body).mapNotNull { view -> view.tag?.toString() }
                assertEquals(listOf(tableTag, ocrTag), tags.filter { tag -> tag.startsWith("health-record-center-review-") })
                assertEquals(measurements.subList(1, 6).map { record -> "health-record-center-record-${record.id}" },
                    tags.filter { tag -> tag.startsWith("health-record-center-record-") })
                val ocrView = requireNotNull(it.body.findViewWithTag<View>(ocrTag))
                assertTrue(descendants(ocrView).filterIsInstance<TextView>().any { label -> label.text.toString() == original.name })
            }
            if (InstrumentationRegistry.getArguments().getString("recordCenterScreenshot") == "true") {
                instrumentation.waitForIdleSync()
                SystemClock.sleep(350)
                awaitTag(scenario, latest)
                val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
                try {
                    File(context.cacheDir, "health-record-center-fixture.png").outputStream().use {
                        check(screenshot.compress(Bitmap.CompressFormat.PNG, 100, it))
                    }
                } finally { screenshot.recycle() }
            }
            val review = capture(HealthCaptureActivity::class.java) { click(scenario, ocrTag) }
            assertEquals(ocr.id, review.getStringExtra("health_job"))
            assertEquals(table, capture(HealthTableActivity::class.java) { click(scenario, tableTag) }.getStringExtra("health_table"))
            click(scenario, latest)
            awaitTag(scenario, "health-edit-record")
            back(scenario)
            awaitTag(scenario, latest)
            HealthRecordStore(context, names.records).use {
                assertTrue(it.delete(measurements[1].id, measurements[1].revision))
                val evidence = HealthEvidence(original.id, ocr.id, "candidate", original.sha256, 1, "120/80", confirmed = true)
                assertTrue(it.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
                    measuredAt = now - 1_000L, evidence = evidence)) is HealthSaveResult.Saved)
            }
            await("record and import updates") {
                var updated = false
                scenario.onActivity { activity ->
                    updated = activity.body.findViewWithTag<View>(tableTag) != null &&
                        activity.body.findViewWithTag<View>(ocrTag) == null &&
                        activity.body.findViewWithTag<View>(latest) == null
                }
                updated
            }
        }
    }

    private fun pendingTable(names: HealthOverviewDatabases, now: Long): String {
        val id = UUID.randomUUID().toString()
        val original = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            originals.createJob(HealthImportJob(id, "content://fixture/table", now))
            originals.importOriginal(id, "time,steps".byteInputStream(), "steps.csv", "text/csv", "file").also {
                originals.updateJob(id) { job -> job.copy(state = HealthImportState.TABLE_REVIEW, originalId = it.id) }
            }
        }
        HealthTableStore(context, names.records).use { tables ->
            tables.begin(id, original, "csv")
            tables.append(id, listOf(HealthTableRow(1, mapOf("time" to "2024-11-04T08:00:00Z", "steps" to "1000"))))
            tables.finishReading(id, listOf("time", "steps"))
        }
        return id
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse("Record center requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun intent(names: HealthOverviewDatabases) = Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)
    private fun capture(type: Class<*>, action: () -> Unit): Intent {
        val launched = AtomicReference<Intent>()
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.component?.className != type.name) return null
                launched.set(Intent(intent))
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            action()
            await("launch ${type.simpleName}") { launched.get() != null }
            instrumentation.waitForIdleSync()
            return requireNotNull(launched.get())
        } finally { instrumentation.removeMonitor(monitor) }
    }
    @Suppress("DEPRECATION")
    private fun back(scenario: ActivityScenario<HealthCenterActivity>) = scenario.onActivity { it.onBackPressed() }
    private fun click(scenario: ActivityScenario<HealthCenterActivity>, tag: String) = withTag(scenario, tag, View::performClick)
    private fun awaitTag(scenario: ActivityScenario<HealthCenterActivity>, tag: String) = withTag(scenario, tag) { true }
    private fun withTag(scenario: ActivityScenario<HealthCenterActivity>, tag: String, predicate: (View) -> Boolean) = await(tag) {
        var found = false
        scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag)?.let(predicate) == true }
        found
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun await(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do { if (condition()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
