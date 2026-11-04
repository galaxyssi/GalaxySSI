package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthStructuredPreviewDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    private fun fixture(name: String, mime: String, payload: ByteArray,
                        test: (HealthOverviewDatabases, HealthOriginalStore, HealthOriginal) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
                val id = UUID.randomUUID().toString()
                val file = originals.importOriginal(id, payload.inputStream(), name, mime, "file")
                test(names, originals, file)
                assertTrue(originals.jobs().isEmpty())
                assertTrue(names.originalRoot(context).walkTopDown().filter(File::isFile).all { it.extension == "ghealth" })
                HealthTableStore(context, names.records).use { assertNull(it.batch(id)) }
                HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
            }
        } finally { clearHealthOverviewFixture(context, names); payload.fill(0) }
    }

    @Test fun csvKeepsQuotedValuesAndDuplicateHeadersWithBoundedSample() {
        val raw = buildString {
            append("same;same;note\r\n")
            repeat(26) { append("${it + 1};\"1;2\";\"=100+24\"\r\n") }
        }
        val payload = byteArrayOf(0xff.toByte(), 0xfe.toByte()) + raw.toByteArray(Charsets.UTF_16LE)
        fixture("fixture.csv", "text/csv", payload) { _, store, file ->
            val sample = HealthStructuredPreview.read(store, file)
            assertEquals(20, sample.rows.size)
            assertEquals(listOf("same", "same", "note"), sample.rows[0].cells)
            assertEquals(listOf("1", "1;2", "=100+24"), sample.rows[1].cells)
            assertTrue(sample.more)
            assertFalse(sample.columnsClipped)
        }
    }

    @Test fun wideCsvClipsDisplayButKeepsTheEncryptedOriginal() {
        val row = (1..14).joinToString(",") { if (it == 2) "a".repeat(700) else "column$it" }
        fixture("fixture.csv", "text/csv", "$row\n".toByteArray()) { _, store, file ->
            val sample = HealthStructuredPreview.read(store, file)
            assertTrue(sample.columnsClipped)
            assertEquals(12, sample.rows.single().cells.size)
            assertEquals(512, sample.rows.single().cells[1].length)
            assertTrue(store.present(file))
        }
    }

    @Test fun jsonShowsObjectKeysAndSummarizesNestedValuesWithoutMappingThem() {
        fixture("fixture.json", "application/json",
            """{"number":1.24e2,"text":"a\nb","missing":null,"object":{"enabled":true,"nested":[1,2]}}""".toByteArray()) { _, store, file ->
            val sample = HealthStructuredPreview.read(store, file)
            assertTrue(sample.jsonKeys)
            assertEquals(listOf("number", "text", "missing", "object"), sample.rows.map { it.cells[0] })
            assertEquals("1.24e2", sample.rows[0].cells[1])
            assertEquals("null", sample.rows[2].cells[1])
            assertTrue(sample.rows[3].cells[1].contains("\"enabled\": true"))
            assertFalse(sample.more)
        }
    }

    @Test fun jsonArrayShowsOnlyTheRequestedPrefixAndRejectsAnOversizedValue() {
        fixture("array.json", "application/json", (1..25).joinToString(",", "[", "]") { """{"id":$it}""" }.toByteArray()) { _, store, file ->
            val sample = HealthStructuredPreview.read(store, file)
            assertFalse(sample.jsonKeys)
            assertTrue(sample.more)
            assertEquals("{\"id\": 20}", sample.rows.last().cells.single())
        }
        fixture("large.json", "application/json", ("[\"" + "x".repeat(2 * 1024 * 1024) + "\"]").toByteArray()) { _, store, file ->
            val failure = runCatching { HealthStructuredPreview.read(store, file) }.exceptionOrNull()
            assertEquals("structured_preview_limit", (failure as? HealthImportFailure)?.code)
        }
    }

    private fun workbook() = HealthXlsxFixtures.workbook(sheets = listOf(
        "Home" to (HealthXlsxFixtures.headers() + HealthXlsxFixtures.reading(formula = true)),
        "Lab" to ("<row r=\"3\">${HealthXlsxFixtures.text("A3", "Lab report")}</row>" + HealthXlsxFixtures.reading(42, value = "130"))
    ))

    @Test fun xlsxPreviewUsesPhysicalRowsAndDisplaysFormulaLiterally() = fixture("fixture.xlsx", xlsx, workbook()) { _, store, file ->
        val first = HealthStructuredPreview.read(store, file)
        assertEquals(listOf("Home", "Lab"), first.sheets.map { it.name })
        assertEquals(listOf(1L, 2L), first.rows.map { it.number })
        assertEquals("=100+24", first.rows.last().cells[1])
        val lab = HealthStructuredPreview.read(store, file, 1)
        assertEquals(listOf(3L, 42L), lab.rows.map { it.number })
        assertEquals("Lab report", lab.rows.first().cells.single())
        assertEquals("130", lab.rows.last().cells[1])
        assertTrue(runCatching { HealthStructuredPreview.read(store, file) { throw CancellationException() } }
            .exceptionOrNull() is CancellationException)
    }

    @Test fun nativeOriginalDetailOpensProtectedReadOnlyPreviewAndSwitchesSheets() = fixture("fixture.xlsx", xlsx, workbook()) { names, _, file ->
        assumeFalse("Structured preview UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("original", file.id)
            .putExtra("health_review_test_id", names.fixture)
        val previewField = HealthCaptureActivity::class.java.getDeclaredField("preview").apply { isAccessible = true }
        ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
            await { var ready = false; scenario.onActivity { ready = it.findViewById<View>(android.R.id.content)
                .findViewWithTag<View>("health-open-original") != null }; ready }
            scenario.onActivity {
                assertTrue(it.findViewById<View>(android.R.id.content).findViewWithTag<View>("health-open-original").performClick())
            }
            lateinit var preview: HealthStructuredOriginalPreview
            fun cellText(row: Int, column: Int): String? {
                var value: String? = null
                scenario.onActivity {
                    preview = previewField.get(it) as HealthStructuredOriginalPreview
                    value = preview.window?.decorView?.findViewWithTag<TextView>("health-structured-cell-$row-$column")?.text?.toString()
                }
                return value
            }
            await { cellText(1, 1) == "=100+24" }
            scenario.onActivity {
                val window = requireNotNull(preview.window)
                assertTrue(window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
                assertNotNull(window.decorView.findViewWithTag<View>("health-structured-save"))
                assertTrue(window.decorView.findViewWithTag<View>("health-structured-sheets").performClick())
                val picker = HealthStructuredOriginalPreview::class.java.getDeclaredField("subdialog").apply { isAccessible = true }
                    .get(preview) as AlertDialog
                assertTrue(picker.listView.performItemClick(View(it), 1, picker.listView.adapter.getItemId(1)))
            }
            await { cellText(0, 0) == "Lab report" }
            if (InstrumentationRegistry.getArguments().getString("health_structured_screenshot") == "true") {
                var screenshot: Bitmap? = null
                instrumentation.waitForIdleSync()
                scenario.onActivity {
                    val view = requireNotNull(preview.window).decorView
                    screenshot = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
                }
                screenshot?.let { bitmap ->
                    try { File(context.getExternalFilesDir(null), "health-structured-preview.png").outputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    } } finally { bitmap.recycle() }
                }
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            instrumentation.waitForIdleSync()
            scenario.onActivity { assertNull(previewField.get(it)) }
            assertFalse(preview.isShowing)
            assertEquals(0, preview.window?.decorView?.findViewWithTag<ViewGroup>("health-structured-sample")?.childCount)
        }
    }

    private fun await(predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 12_000L
        do {
            if (predicate()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Structured preview did not reach the expected state")
    }
}
