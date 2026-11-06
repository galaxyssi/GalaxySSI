package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.EditText
import android.widget.ImageView
import android.widget.RadioButton
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOriginalLibrarySearchDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val zone = ZoneId.of("Asia/Shanghai")
    private val reportDate = LocalDate.of(2024, 2, 29).atTime(8, 0).atZone(zone).toInstant().toEpochMilli()

    @Test fun searchesAuthenticatedNamesAndBothSourceLinksByMetricAndReportDate() = fixture { names ->
        openOriginals(names).use { originals ->
            val main = archive(originals, "Lab_main.csv")
            val alternate = archive(originals, "Other-sheet.csv")
            val unknown = archive(originals, "Unlinked-file.csv")
            HealthRecordStore(context, names.records).use { records ->
                val draft = glucose(main, reportDate)
                val record = (records.save(draft) as HealthSaveResult.Saved).record
                val database = records.tableDatabase
                database.beginTransaction()
                try {
                    assertTrue(records.linkDuplicateTableSource(glucose(alternate, reportDate), record.id))
                    database.setTransactionSuccessful()
                } finally { database.endTransaction() }
                fun ids(query: String, filter: HealthLibraryFilter = HealthLibraryFilter()): Set<String> {
                    val search = HealthOriginalLibrarySearch(query, zone)
                    val signal = CancellationSignal()
                    return originals.library(filter, signal = signal) { search.matches(it, records, signal) }.originals.map { it.id }.toSet()
                }
                assertEquals(setOf(main.id), ids("\uff2c\uff21\uff22 main"))
                assertEquals(setOf(main.id, alternate.id), ids("GLU"))
                assertEquals(setOf(main.id, alternate.id), ids("\u8840\u7cd6"))
                assertEquals(setOf(main.id, alternate.id), ids("2024/02/29"))
                assertEquals(setOf(main.id, alternate.id), ids("2024\u5e742\u670829\u65e5"))
                assertEquals(setOf(main.id, alternate.id), ids("2024-02"))
                assertTrue(ids("2024-02-30").isEmpty())
                assertTrue(ids("2024-02-28").isEmpty())
                assertTrue(ids("GLU", HealthLibraryFilter(HealthOriginalKind.IMAGE)).isEmpty())
                assertFalse(unknown.id in ids("GLU"))
                assertTrue(records.delete(record.id, record.revision))
                assertTrue(ids("GLU").isEmpty())
                assertTrue(ids("2024/02/29").isEmpty())
                assertEquals(setOf(main.id), ids("lab main"))
            }
        }
    }

    @Test fun filteredSearchScansBeyondEmptyChunksAndPaginatesWithoutGaps() = fixture { names ->
        openOriginals(names).use { originals ->
            val older = (1..34).map { archive(originals, "archived-match-$it.csv") }
            repeat(35) { archive(originals, "later-irrelevant-$it.csv") }
            val hidden = UUID.randomUUID().toString()
            originals.createJob(HealthImportJob(hidden, "content://fixture/review", System.currentTimeMillis(), keepOriginal = false))
            val privateReview = originals.importOriginal(hidden, "draft".byteInputStream(), "archived-match-private.csv", "text/csv", "file")
            assertTrue(privateReview.reviewOnly)
            HealthRecordStore(context, names.records).use { records ->
                val search = HealthOriginalLibrarySearch("archived match", zone)
                val filter = HealthLibraryFilter(filesOnly = true)
                val signal = CancellationSignal()
                fun page(after: Pair<Long, String>? = null) =
                    originals.library(filter, after, signal) { search.matches(it, records, signal) }
                val first = page()
                assertEquals(30, first.originals.size)
                val second = page(requireNotNull(first.next))
                assertNull(second.next)
                val expected = older.sortedWith(compareByDescending<HealthOriginal> { it.importedAt }.thenByDescending { it.id })
                assertEquals(expected.map { it.id }, (first.originals + second.originals).map { it.id })
                assertEquals(69L, originals.libraryCounts(filter, signal).values.sum())
                signal.cancel()
                assertThrows(OperationCanceledException::class.java) { page() }
            }
        }
    }

    @Suppress("DEPRECATION")
    @Test fun nativeSearchKeepsSelectionAndReturnsFromDetailAndExport() = fixture { names ->
        assumeFalse("Visible library tests need an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val (photo, file) = openOriginals(names).use { originals ->
            val photo = jpeg(originals)
            val file = archive(originals, "Synthetic measurements.csv")
            photo to file
        }
        HealthRecordStore(context, names.records).use { records ->
            assertTrue(records.save(glucose(photo, reportDate)) is HealthSaveResult.Saved)
            assertTrue(records.save(glucose(file, reportDate + 60_000)) is HealthSaveResult.Saved)
        }
        ActivityScenario.launch<HealthOriginalLibraryActivity>(Intent(context, HealthOriginalLibraryActivity::class.java)
            .putHealthNavigationFixture(names)).use { scenario ->
            awaitCard(scenario, photo.id)
            awaitCard(scenario, file.id)
            scenario.onActivity { activity ->
                val photos = activity.window.decorView.findViewWithTag<RadioButton>("health-library-tab-1")
                assertEquals(activity.getString(R.string.health_library_tab_count, activity.getString(R.string.health_library_tab_photos), 1),
                    photos.text.toString())
                assertTrue(activity.window.decorView.findViewWithTag<RadioButton>("health-library-tab-0").isChecked)
            }
            query(scenario, "\u8840\u7cd6")
            awaitCard(scenario, photo.id)
            awaitCard(scenario, file.id)
            click(scenario, "health-library-tab-1")
            awaitCard(scenario, photo.id)
            var before: View? = null
            scenario.onActivity { activity ->
                before = activity.window.decorView.findViewWithTag("health-library-original-${photo.id}")
                assertNull(activity.window.decorView.findViewWithTag<View>("health-library-original-${file.id}"))
                assertTrue(activity.window.decorView.findViewWithTag<RadioButton>("health-library-tab-1").isChecked)
            }
            click(scenario, "health-library-check-${photo.id}")
            awaitCount(scenario, 1)
            scenario.onActivity { activity ->
                assertSame(before, activity.window.decorView.findViewWithTag<View>("health-library-original-${photo.id}"))
                assertTrue(activity.window.decorView.findViewWithTag<CheckBox>("health-library-check-${photo.id}").isChecked)
            }
            val detail = open(HealthCaptureActivity::class.java) { click(scenario, "health-library-original-${photo.id}") }
            assertEquals(photo.id, detail.intent.getStringExtra("original"))
            await("exact original title") { fromActivity(detail) { views(it).filterIsInstance<TextView>().any { label -> label.text == photo.name } } }
            instrumentation.runOnMainSync { detail.finish() }
            awaitForeground(scenario)
            awaitCard(scenario, photo.id)
            assertQuery(scenario, "\u8840\u7cd6")
            awaitCount(scenario, 1)
            click(scenario, "health-library-tab-2")
            awaitCard(scenario, file.id)
            click(scenario, "health-library-check-${file.id}")
            awaitCount(scenario, 2)
            click(scenario, "health-library-tab-0")
            awaitCard(scenario, photo.id)
            awaitCard(scenario, file.id)
            await("decrypted synthetic thumbnail") {
                var ready = false
                scenario.onActivity {
                    val card = it.window.decorView.findViewWithTag<View>("health-library-original-${photo.id}")
                    ready = card != null && views(card).filterIsInstance<ImageView>().any { image ->
                        image.drawable is android.graphics.drawable.BitmapDrawable
                    }
                }
                ready
            }
            screenshot()
            val preview = open(HealthOriginalExportActivity::class.java) { click(scenario, "health-library-export") }
            await("frozen original manifest") { fromActivity(preview) { root ->
                val labels = views(root).filterIsInstance<TextView>().map { it.text.toString() }
                labels.containsAll(listOf(photo.name, file.name, context.getString(R.string.health_library_confirm)))
            } }
            instrumentation.runOnMainSync { preview.onBackPressed() }
            await("export confirmation closed") { fromActivity(preview) { preview.isFinishing } }
            awaitForeground(scenario)
            awaitCard(scenario, photo.id)
            awaitCount(scenario, 2)
            assertQuery(scenario, "\u8840\u7cd6")
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { activity ->
                assertNull(activity.window.decorView.findViewWithTag<View>("health-library-original-${photo.id}"))
                assertNull(activity.window.decorView.findViewWithTag<View>("health-library-search"))
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            awaitCard(scenario, photo.id)
            assertQuery(scenario, "")
            awaitCount(scenario, 2)
            query(scenario, "not present in the archive")
            await("empty search results") {
                var shown = false
                scenario.onActivity {
                    shown = it.window.decorView.findViewWithTag<TextView>("health-library-empty")?.text.toString() ==
                        it.getString(R.string.health_library_no_matches)
                }
                shown
            }
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally {
            clearHealthOverviewFixture(context, names)
            File(context.cacheDir, "health-original-export-test-${names.fixture}").deleteRecursively()
        }
    }
    private fun openOriginals(names: HealthOverviewDatabases) = HealthExportShare.openOriginals(context, names.fixture)
    private fun archive(store: HealthOriginalStore, name: String) =
        store.importOriginal(UUID.randomUUID().toString(), name.byteInputStream(), name, "text/csv", "file")
    private fun jpeg(store: HealthOriginalStore): HealthOriginal {
        val bitmap = Bitmap.createBitmap(180, 120, Bitmap.Config.ARGB_8888)
        val output = ByteArrayOutputStream()
        try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.rgb(229, 243, 236))
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(45, 106, 77); textSize = 22f }
            canvas.drawText("SAMPLE", 35f, 65f, paint)
            check(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output))
            return store.importOriginal(UUID.randomUUID().toString(), output.toByteArray().inputStream(),
                "Synthetic report.jpg", "image/jpeg", "camera")
        } finally { bitmap.recycle() }
    }
    private fun glucose(file: HealthOriginal, time: Long) = HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.4"), "mmol/L", time,
        evidence = HealthEvidence(file.id, file.id, "fixture", file.sha256, 1, "5.4", confirmed = true, kind = "table", tableRow = 1))

    private fun query(scenario: ActivityScenario<HealthOriginalLibraryActivity>, value: String) =
        scenario.onActivity { it.window.decorView.findViewWithTag<EditText>("health-library-search").setText(value) }
    private fun assertQuery(scenario: ActivityScenario<HealthOriginalLibraryActivity>, value: String) =
        scenario.onActivity { assertEquals(value, it.window.decorView.findViewWithTag<EditText>("health-library-search").text.toString()) }
    private fun click(scenario: ActivityScenario<HealthOriginalLibraryActivity>, tag: String) =
        scenario.onActivity { assertTrue(requireNotNull(it.window.decorView.findViewWithTag<View>(tag)).performClick()) }
    private fun awaitCard(scenario: ActivityScenario<HealthOriginalLibraryActivity>, id: String) = await("original $id") {
        var found = false
        scenario.onActivity { found = it.window.decorView.findViewWithTag<View>("health-library-original-$id") != null }
        found
    }
    private fun awaitCount(scenario: ActivityScenario<HealthOriginalLibraryActivity>, count: Int) = await("selection count $count") {
        var found = false
        scenario.onActivity { activity ->
            found = activity.window.decorView.findViewWithTag<TextView>("health-library-count")?.text.toString() ==
                activity.getString(R.string.health_library_selected, count)
        }
        found
    }
    private fun awaitForeground(scenario: ActivityScenario<HealthOriginalLibraryActivity>) = await("original library foreground") {
        if (scenario.state != Lifecycle.State.RESUMED) return@await false
        var ready = false
        scenario.onActivity { ready = it.hasWindowFocus() }
        ready
    }
    private fun open(type: Class<out Activity>, action: () -> Unit): Activity {
        val monitor = instrumentation.addMonitor(type.name, null, false)
        try {
            action()
            return requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000)) { "Did not open ${type.simpleName}" }
        } finally { instrumentation.removeMonitor(monitor) }
    }
    private fun fromActivity(activity: Activity, predicate: (View) -> Boolean): Boolean {
        var found = false
        instrumentation.runOnMainSync { found = predicate(activity.window.decorView) }
        return found
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun screenshot() {
        if (InstrumentationRegistry.getArguments().getString("originalSearchScreenshot") != "true") return
        instrumentation.waitForIdleSync()
        SystemClock.sleep(350)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.cacheDir, "health-original-library-search.png").outputStream().use {
            check(image.compress(Bitmap.CompressFormat.PNG, 100, it))
        } } finally { image.recycle() }
    }
    private fun await(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do { if (condition()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
