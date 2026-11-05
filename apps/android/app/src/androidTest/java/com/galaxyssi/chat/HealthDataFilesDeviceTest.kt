package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ScrollView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthDataFilesDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun countingCrossesPageBoundaryAndDoesNotIncludePrivateReviewOrCrop() = fixture { names ->
        val base = System.currentTimeMillis()
        val expected = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
            val retained = (0 until 34).map { index -> archive(store, "sample-$index", if (index % 2 == 0) "camera" else "file") }
            val crop = archive(store, "derived", "crop:${retained.first().id}")
            val draft = UUID.randomUUID().toString()
            store.createJob(HealthImportJob(draft, "content://test/document", base, keepOriginal = false))
            val review = store.importOriginal(draft, "private".byteInputStream(), "private.pdf", "application/pdf", "file")
            assertTrue(review.reviewOnly)
            (retained + crop).sortedWith(compareByDescending<HealthOriginal> { it.importedAt }.thenByDescending { it.id }).take(4).map { it.id }
        }
        var recent = emptyList<HealthRecentFile>()
        val repo = HealthDataFilesRepository(context, names)
        assertEquals(HealthDataFileCounts(17, 17), repo.load(CancellationSignal()) { result ->
            val (count, files) = result.getOrThrow()
            assertEquals(0L, count)
            recent = files
        })
        assertEquals(expected, recent.map { it.id })
        val cancelled = CancellationSignal()
        assertThrows(OperationCanceledException::class.java) {
            repo.load(cancelled) { overview -> assertTrue(overview.isSuccess); cancelled.cancel() }
        }
    }

    @Test fun populatedHubUpdatesInPlaceAndClearsFileNamesInBackground() = fixture { names ->
        unlocked()
        val (camera, report, missing) = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
            val photo = archive(store, "Synthetic blood pressure photo.jpg", "camera", "image/jpeg")
            val pdf = archive(store, "Synthetic lab report.pdf", "file")
            val removed = archive(store, "Synthetic missing report.pdf", "file")
            assertTrue(store.removeOriginalBytes(removed))
            Triple(photo, pdf, removed)
        }
        val record = HealthRecordStore(context, names.records).use { store ->
            val evidence = HealthEvidence(report.id, report.id, "fixture", report.sha256, 1, "120/80", confirmed = true)
            (store.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"),
                measuredAt = System.currentTimeMillis() - 10_000, evidence = evidence)) as HealthSaveResult.Saved).record
        }
        launch(names).use { scenario ->
            waitForCounts(scenario, "1", "1", "2")
            assertRow(scenario, camera.id, R.string.health_data_unlinked)
            assertRow(scenario, report.id, R.string.health_data_linked)
            assertRow(scenario, missing.id, R.string.health_data_missing)
            screenshot("overview")
            var y = 0
            scenario.onActivity { activity ->
                val scroll = views(activity.window.decorView).filterIsInstance<ScrollView>().single()
                scroll.scrollTo(0, scroll.getChildAt(0).height)
                y = scroll.scrollY
            }
            assertTrue(y > 0)
            instrumentation.waitForIdleSync()
            screenshot("recent")
            val route = capture(HealthCaptureActivity::class.java) {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>("health-data-original-${report.id}").performClick()) }
            }
            assertEquals(report.id, route.getStringExtra("original"))
            assertEquals(names, route.healthNavigationDatabases())
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                assertNull(activity.window.decorView.findViewWithTag<View>("health-data-original-${report.id}"))
                assertFalse(labels(activity.window.decorView).contains(report.name))
                assertEquals(activity.getString(R.string.health_data_count_pending),
                    activity.window.decorView.findViewWithTag<TextView>("health-data-count-0").text.toString())
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            waitForCounts(scenario, "1", "1", "2")
            await("saved scroll position") {
                var same = false
                scenario.onActivity { same = views(it.window.decorView).filterIsInstance<ScrollView>().single().scrollY == y }
                same
            }
            HealthRecordStore(context, names.records).use { assertTrue(it.delete(record.id, record.revision)) }
            waitForCounts(scenario, "0", "1", "2")
            assertRow(scenario, report.id, R.string.health_data_unlinked)
        }
        ActivityScenario.launch<HealthCaptureActivity>(Intent(context, HealthCaptureActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("original", report.id)).use { detail ->
            await("original detail for the exact file") {
                var shown = false
                detail.onActivity { shown = labels(it.window.decorView).contains(report.name) }
                shown
            }
        }
    }

    @Test fun emptyHubRoutesToSeparateImportExportAndBackupOperations() = fixture { names ->
        unlocked()
        launch(names).use { scenario ->
            waitForCounts(scenario, "0", "0", "0")
            scenario.onActivity { activity ->
                assertTrue(labels(activity.window.decorView).contains(activity.getString(R.string.health_no_originals)))
            }
            assertEquals(names, capture(HealthCatalogActivity::class.java) { click(scenario, R.string.health_data_measurements) }.healthNavigationDatabases())
            assertEquals(names, capture(HealthOriginalLibraryActivity::class.java) { click(scenario, R.string.health_data_view_all) }.healthNavigationDatabases())
            assertTrue(capture(HealthCenterActivity::class.java) {
                menu(scenario, R.string.common_import, R.string.health_first_import_title)
            }.getBooleanExtra("health_import_center", false))
            val originalImport = capture(HealthCaptureActivity::class.java) {
                menu(scenario, R.string.common_import, R.string.health_export_import_originals)
            }
            assertTrue(originalImport.getBooleanExtra("health_original_only", false))
            assertTrue(originalImport.getBooleanExtra("health_pick_files", false))
            assertFalse(capture(HealthRecordExportActivity::class.java) {
                menu(scenario, R.string.common_export, R.string.health_export_records)
            }.getBooleanExtra("export_history", true))
            assertFalse(capture(HealthCaptureActivity::class.java) {
                menu(scenario, R.string.health_data_tasks, R.string.health_import_queue_title)
            }.getBooleanExtra("health_pick_files", false))
            assertTrue(capture(HealthRecordExportActivity::class.java) {
                menu(scenario, R.string.health_data_tasks, R.string.health_export_history)
            }.getBooleanExtra("export_history", false))
            assertEquals(names.fixture, capture(HealthOriginalExportHistoryActivity::class.java) {
                menu(scenario, R.string.health_data_tasks, R.string.health_library_export_history)
            }.getStringExtra("health_original_export_test_id"))
            assertTrue(capture(HealthBackupActivity::class.java) {
                menu(scenario, R.string.health_data_backup, R.string.health_backup_history)
            }.getBooleanExtra("backup_history", false))
            assertTrue(capture(HealthBackupActivity::class.java) {
                menu(scenario, R.string.health_data_backup, R.string.health_backup_verify)
            }.getBooleanExtra("verify_backup", false))
            assertEquals(names.fixture, capture(HealthRestoreActivity::class.java) {
                menu(scenario, R.string.health_data_backup, R.string.health_restore_title)
            }.getStringExtra("health_restore_test_id"))
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }

    private fun unlocked() = assumeFalse("Data and files requires an unlocked display",
        context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)

    private fun archive(store: HealthOriginalStore, name: String, source: String, mime: String = "application/pdf"): HealthOriginal =
        store.importOriginal(UUID.randomUUID().toString(), name.byteInputStream(), name, mime, source)

    private fun launch(names: HealthOverviewDatabases) = ActivityScenario.launch<HealthDataFilesActivity>(
        Intent(context, HealthDataFilesActivity::class.java).putHealthNavigationFixture(names))

    private fun assertRow(scenario: ActivityScenario<HealthDataFilesActivity>, id: String, status: Int) =
        scenario.onActivity { activity ->
            val row = requireNotNull(activity.window.decorView.findViewWithTag<View>("health-data-original-$id"))
            assertTrue(labels(row).contains(activity.getString(status)))
        }

    private fun waitForCounts(scenario: ActivityScenario<HealthDataFilesActivity>, vararg counts: String) =
        await("counts ${counts.toList()}") {
            var same = false
            scenario.onActivity { activity ->
                same = counts.withIndex().all { (i, value) ->
                    activity.window.decorView.findViewWithTag<TextView>("health-data-count-$i").text.toString() == value
                }
            }
            same
        }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun labels(view: View) = views(view).filterIsInstance<TextView>().map { it.text.toString() }
    private fun click(scenario: ActivityScenario<HealthDataFilesActivity>, label: Int) = scenario.onActivity { activity ->
        val text = views(activity.window.decorView).filterIsInstance<TextView>().single { it.text == activity.getString(label) }
        var control: View? = text
        while (control?.isClickable == false) control = control.parent as? View
        assertTrue(requireNotNull(control).performClick())
    }

    private fun menu(scenario: ActivityScenario<HealthDataFilesActivity>, title: Int, item: Int) {
        click(scenario, title)
        val name = context.getString(item)
        await("menu item $name") {
            instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(name).orEmpty()
                .filter { it.text?.toString() == name }.any {
                    it.performAction(AccessibilityNodeInfo.ACTION_CLICK) ||
                        it.parent?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
                }
        }
    }

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

    private fun screenshot(name: String) {
        if (InstrumentationRegistry.getArguments().getString("dataFilesScreenshot") != "true") return
        instrumentation.waitForIdleSync()
        SystemClock.sleep(350)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.cacheDir, "health-data-files-$name.png").outputStream().use {
            check(image.compress(Bitmap.CompressFormat.PNG, 100, it))
        } } finally { image.recycle() }
    }

    private fun await(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do { if (condition()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
