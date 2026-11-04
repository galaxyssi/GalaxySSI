package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthReviewSourceDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun rasterLoadsTheExactPdfPageAndRejectsAStalePageNumber() = isolated { _, store ->
        val output = ByteArrayOutputStream()
        val pdf = PdfDocument()
        try {
            listOf(Color.RED, Color.BLUE).forEachIndexed { index, color ->
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(250, 380, index + 1).create())
                page.canvas.drawColor(color)
                pdf.finishPage(page)
            }
            pdf.writeTo(output)
        } finally { pdf.close() }
        val original = store.importOriginal(id(), output.toByteArray().inputStream(), "fixture.pdf", "application/pdf", "file")
        val second = HealthReviewRaster.load(store, original, 2)
        try {
            assertEquals(Color.BLUE, second.getPixel(second.width / 2, second.height / 2))
            assertTrue(second.width.toLong() * second.height <= 2_000_000)
        } finally { second.recycle() }
        assertTrue(runCatching { HealthReviewRaster.load(store, original, 3) }.isFailure)
        assertTrue(store.removeOriginalBytes(original))
        assertTrue(runCatching { HealthReviewRaster.load(store, original, 2) }.isFailure)
    }

    @Test fun imageOrientationMatchesTheCoordinatesUsedByRecognition() = isolated { _, store ->
        val file = File.createTempFile("health-review-test-", ".jpg", context.cacheDir)
        val raw = Bitmap.createBitmap(80, 40, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(raw)
            val paint = Paint()
            paint.color = Color.RED
            canvas.drawRect(0f, 0f, 40f, 40f, paint)
            paint.color = Color.BLUE
            canvas.drawRect(40f, 0f, 80f, 40f, paint)
            file.outputStream().use { assertTrue(raw.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
            androidx.exifinterface.media.ExifInterface(file).apply {
                setAttribute(androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION, "6")
                saveAttributes()
            }
            val original = file.inputStream().use { store.importOriginal(id(), it, "rotated.jpg", "image/jpeg", "file") }
            val upright = HealthReviewRaster.load(store, original, 1)
            try {
                assertEquals(40, upright.width)
                assertEquals(80, upright.height)
                assertTrue(Color.red(upright.getPixel(20, 20)) > 200)
                assertTrue(Color.blue(upright.getPixel(20, 60)) > 200)
            } finally { upright.recycle() }
        } finally { raw.recycle(); file.delete() }
    }

    @Test fun candidateOpensFocusedSourceAndBackgroundDiscardsItsBitmap() = isolated { names, store ->
        assumeFalse("Native review requires an unlocked display",
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = seed(store)
        val intent = Intent(context, HealthCaptureActivity::class.java)
            .putExtra("health_job", job.id).putExtra("health_review_test_id", names.fixture)
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                var source: Bitmap? = null
                await {
                    scenario.onActivity { activity -> source = views(activity.window.decorView)
                        .filterIsInstance<HealthReviewSourceView>().firstOrNull()?.bitmap }
                    source != null
                }
                screenshot("health-ocr-source-overview.png")
                scenario.onActivity { activity ->
                    worker = HealthCaptureActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(activity) as ExecutorService
                    val root = views(activity.window.decorView)
                    assertTrue(root.filterIsInstance<TextView>().any { it.text == activity.getString(R.string.health_review_unit_unknown) })
                    val inline = root.filterIsInstance<HealthReviewSourceView>().single()
                    val before = frame(inline)
                    try {
                        val cholesterol = root.first { (it.tag as? String)?.startsWith("health-review-mark-cholesterol-") == true }
                        assertTrue(cholesterol.performClick())
                        val after = frame(inline)
                        try { assertFalse(before.sameAs(after)) } finally { after.recycle() }
                    } finally { before.recycle() }
                }
                val fullPage = context.getString(R.string.health_review_full_page)
                await { instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(fullPage)
                    ?.any { it.text?.toString() == fullPage } == true }
                screenshot("health-ocr-source-focused.png")
                scenario.moveToState(Lifecycle.State.CREATED)
                assertTrue(requireNotNull(source).isRecycled)
                scenario.moveToState(Lifecycle.State.RESUMED)
                var refreshed: Bitmap? = null
                await {
                    scenario.onActivity { activity -> refreshed = views(activity.window.decorView)
                        .filterIsInstance<HealthReviewSourceView>().singleOrNull()?.bitmap }
                    refreshed != null
                }
                assertTrue(store.removeOriginalBytes(requireNotNull(store.original(job.originalId))))
                await { requireNotNull(refreshed).isRecycled }
                scenario.onActivity { activity ->
                    assertTrue(views(activity.window.decorView).filterIsInstance<HealthReviewSourceView>().isEmpty())
                    assertTrue(views(activity.window.decorView).filterIsInstance<TextView>()
                        .any { it.text == activity.getString(R.string.health_original_preview_failed) })
                }
                HealthRecordStore(context, names.records).use { assertTrue(it.page().records.isEmpty()) }
            }
        } finally { worker?.awaitTermination(15, TimeUnit.SECONDS) }
    }

    @Test fun batchRejectsChangedDraftAndRollsBackAnEarlierInsertOnDuplicate() = isolated { names, originals ->
        val job = seed(originals)
        val drafts = recognized(originals, job)
        val glucose = approved(drafts.first { it.metric == HealthMetric.GLUCOSE })
        val hemoglobin = approved(drafts.first { it.metric == HealthMetric.HEMOGLOBIN })
        HealthRecordStore(context, names.records).use { store ->
            listOf(glucose, hemoglobin).forEach(store::saveDraft)
            fun selected() = store.prepareOcrReviewPage(listOf(glucose, hemoglobin)).map { requireNotNull(it.selection) }
            val stale = selected()
            store.saveDraft(hemoglobin.copy(note = "Corrected after selection"))
            assertEquals(HealthOcrBatchResult.Stale(stale[1].key), store.saveOcrReviewBatch(job.id, job.originalId, stale))
            assertEquals(0L, store.count())
            val otherSource = hemoglobin.copy(evidence = hemoglobin.evidence!!.copy(originalId = id(), jobId = id()))
            assertTrue(store.save(otherSource) is HealthSaveResult.Saved)
            val valid = selected()
            val clock = store.metricVersion(HealthMetric.GLUCOSE)
            assertEquals(HealthOcrBatchResult.Duplicate(valid[1].key), store.saveOcrReviewBatch(job.id, job.originalId, valid))
            assertEquals(1L, store.count())
            assertEquals(clock, store.metricVersion(HealthMetric.GLUCOSE))
            assertEquals(glucose, store.draft(valid[0].key))
            assertNull(store.recordForEvidence(glucose))
        }
    }

    @Test fun finishingOneItemStagesItWithoutCreatingARecord() = isolated { names, originals ->
        assumeFalse("Native review requires an unlocked display",
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = seed(originals)
        val ready = approved(recognized(originals, job).first { it.metric == HealthMetric.GLUCOSE })
        val key = HealthRecordStore.draftKey(ready)
        HealthRecordStore(context, names.records).use { it.saveDraft(ready.copy(evidence = ready.evidence!!.copy(confirmed = false))) }
        val intent = Intent(context, HealthCenterActivity::class.java).putExtra("review_draft", key)
            .putExtra("health_stage_ocr_review", true).putExtra("health_overview_test_id", names.fixture)
        ActivityScenario.launch<HealthCenterActivity>(intent).use { scenario ->
            await {
                var visible = false
                scenario.onActivity { visible = views(it.window.decorView).any { view -> view.tag == "health-save" } }
                visible
            }
            scenario.onActivity {
                val root = views(it.window.decorView)
                val finish = root.single { view -> view.tag == "health-save" } as TextView
                assertEquals(it.getString(R.string.health_review_finish_item), finish.text)
                assertTrue(finish.performClick())
                assertEquals(View.VISIBLE, root.single { view -> view.tag == "health-validation" }.visibility)
                val approval = root.single { view -> view.tag == "health-confirm-source" } as CheckBox
                approval.performClick()
                assertTrue(approval.isChecked)
                assertTrue(finish.performClick())
            }
            await { scenario.state == Lifecycle.State.DESTROYED }
        }
        HealthRecordStore(context, names.records).use {
            assertEquals(0L, it.count())
            assertTrue(requireNotNull(it.draft(key)).evidence!!.confirmed)
        }
    }

    @Test fun batchUiRequiresFreshConsentAndKeepsUnselectedDrafts() = isolated { names, originals ->
        assumeFalse("Native review requires an unlocked display",
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = seed(originals)
        val drafts = recognized(originals, job)
        val remaining = drafts.single { it.metric == HealthMetric.CHOLESTEROL }
        val toSave = drafts.filter { it.metric != HealthMetric.CHOLESTEROL }.map(::approved)
        HealthRecordStore(context, names.records).use { records ->
            toSave.forEach(records::saveDraft)
            val intent = Intent(context, HealthCaptureActivity::class.java)
                .putExtra("health_job", job.id).putExtra("health_review_test_id", names.fixture)
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                fun awaitRows() = await {
                    var ready = false
                    scenario.onActivity { ready = views(it.window.decorView).count { view ->
                        (view.tag as? String)?.startsWith("health-review-pick-") == true } == 2 }
                    ready
                }
                awaitRows()
                scenario.onActivity {
                    val root = views(it.window.decorView)
                    val checks = root.filter { view -> (view.tag as? String)?.startsWith("health-review-pick-") == true }
                    val consent = root.single { view -> view.tag == "health-review-batch-consent" } as CheckBox
                    val save = root.single { view -> view.tag == "health-review-batch-save" }
                    assertFalse(save.isEnabled)
                    checks.forEach { check -> assertTrue(check.performClick()) }
                    assertFalse(save.isEnabled)
                    consent.performClick()
                    assertTrue(consent.isChecked)
                    assertTrue(save.isEnabled)
                }
                scenario.recreate()
                awaitRows()
                scenario.onActivity {
                    val root = views(it.window.decorView)
                    val checks = root.filterIsInstance<CheckBox>().filter { view -> (view.tag as? String)?.startsWith("health-review-pick-") == true }
                    assertTrue(checks.all { it.isChecked })
                    val consent = root.single { view -> view.tag == "health-review-batch-consent" } as CheckBox
                    val save = root.single { view -> view.tag == "health-review-batch-save" }
                    assertFalse(consent.isChecked)
                    assertFalse(save.isEnabled)
                    consent.performClick()
                    assertTrue(consent.isChecked)
                    assertTrue(save.isEnabled)
                }
                screenshot("health-ocr-batch-confirm.png")
                scenario.onActivity {
                    assertTrue(views(it.window.decorView).single { view -> view.tag == "health-review-batch-save" }.performClick())
                }
                await { records.count() == 2L }
                assertEquals(toSave.map { it.metric }.toSet(), records.page().records.map { it.draft.metric }.toSet())
                assertEquals(remaining, records.draft(HealthRecordStore.draftKey(remaining)))
                assertNull(records.recordForEvidence(remaining))
            }
        }
    }

    @Test fun selectionsAcrossTwoRealPdfPagesCommitInOneBatch() = isolated { names, originals ->
        assumeFalse("Native review requires an unlocked display",
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val id = id()
        val lines = listOf("Glucose: 5.4 mmol/L", "Hemoglobin: 142 g/L")
        originals.createJob(HealthImportJob(id, "content://fixture/report", System.currentTimeMillis()))
        val bytes = ByteArrayOutputStream()
        val pdf = PdfDocument()
        try {
            lines.forEachIndexed { index, line ->
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(250, 350, index + 1).create())
                page.canvas.drawText(line, 10f, 80f, Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 14f })
                pdf.finishPage(page)
                originals.savePage(id, HealthOcrPage(index + 1, 250, 350,
                    listOf(HealthOcrLine(line, listOf(40, 185, 720, 240)))))
            }
            pdf.writeTo(bytes)
        } finally { pdf.close() }
        val original = originals.importOriginal(id, bytes.toByteArray().inputStream(), "synthetic-two-pages.pdf", "application/pdf", "file")
        val job = requireNotNull(originals.updateJob(id) { it.copy(state = HealthImportState.REVIEW, originalId = original.id) })
        HealthRecordStore(context, names.records).use { records ->
            (1..2).forEach { page ->
                records.saveDraft(approved(HealthOcrCandidates.suggest(job, original, requireNotNull(originals.page(id, page))).single()))
            }
            val intent = Intent(context, HealthCaptureActivity::class.java)
                .putExtra("health_job", job.id).putExtra("health_review_test_id", names.fixture)
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                fun row(views: List<View>, metric: String) = views.singleOrNull {
                    (it.tag as? String)?.startsWith("health-review-pick-$metric-") == true
                }
                fun waitFor(metric: String) = await {
                    var visible = false
                    scenario.onActivity { visible = row(views(it.window.decorView), metric) != null }
                    visible
                }
                waitFor("glucose")
                scenario.onActivity {
                    val root = views(it.window.decorView)
                    assertTrue(requireNotNull(row(root, "glucose")).performClick())
                    assertTrue(root.filterIsInstance<TextView>().single { v -> v.text == it.getString(R.string.health_next_page) }.performClick())
                }
                waitFor("hemoglobin")
                scenario.onActivity {
                    val root = views(it.window.decorView)
                    assertTrue(requireNotNull(row(root, "hemoglobin")).performClick())
                    val consent = root.single { view -> view.tag == "health-review-batch-consent" } as CheckBox
                    assertEquals(it.getString(R.string.health_review_batch_consent, 2), consent.text)
                    consent.performClick()
                    assertTrue(consent.isChecked)
                    assertTrue(root.single { view -> view.tag == "health-review-batch-save" }.performClick())
                }
                await { records.count() == 2L }
                assertEquals(setOf(1, 2), records.page().records.map { it.draft.evidence!!.page }.toSet())
            }
        }
    }

    private fun recognized(store: HealthOriginalStore, job: HealthImportJob) =
        HealthOcrCandidates.suggest(job, requireNotNull(store.original(job.originalId)), requireNotNull(store.page(job.id, 1)))

    private fun approved(draft: HealthDraft) = draft.copy(measuredAt = 1_790_000_000_000L, evidence = draft.evidence!!.copy(confirmed = true))

    private fun seed(store: HealthOriginalStore): HealthImportJob {
        val id = id()
        store.createJob(HealthImportJob(id, "content://fixture/report", System.currentTimeMillis()))
        val report = Bitmap.createBitmap(720, 480, Bitmap.Config.ARGB_8888)
        val output = ByteArrayOutputStream()
        val lines = listOf("Glucose: 5.4 mmol/L", "Total cholesterol: 4.6", "Hemoglobin: 142 g/L")
        try {
            val canvas = Canvas(report)
            canvas.drawColor(Color.WHITE)
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 36f }
            canvas.drawText("Synthetic report", 42f, 80f, text)
            lines.forEachIndexed { index, value -> canvas.drawText(value, 42f, 160f + 90 * index, text) }
            assertTrue(report.compress(Bitmap.CompressFormat.PNG, 100, output))
        } finally { report.recycle() }
        val original = store.importOriginal(id, output.toByteArray().inputStream(), "synthetic-report.png", "image/png", "file")
        val recognized = lines.mapIndexed { index, value ->
            val y = 160 + 90 * index
            HealthOcrLine(value, listOf(55, (y - 33) * 1000 / 480, 650, (y + 6) * 1000 / 480))
        }
        store.savePage(id, HealthOcrPage(1, 720, 480, recognized))
        return requireNotNull(store.updateJob(id) { it.copy(state = HealthImportState.REVIEW, originalId = original.id) })
    }

    private fun frame(view: View) = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888).also { view.draw(Canvas(it)) }
    private fun id() = UUID.randomUUID().toString()
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun await(condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do {
            if (condition()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("The native source preview did not reach the expected state")
    }
    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            try {
                File(context.getExternalFilesDir(null), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() }
        }
    }
    private fun isolated(block: (HealthOverviewDatabases, HealthOriginalStore) -> Unit) {
        val names = HealthOverviewDatabases(id())
        try { HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { block(names, it) } }
        finally { clearHealthOverviewFixture(context, names) }
    }
}
