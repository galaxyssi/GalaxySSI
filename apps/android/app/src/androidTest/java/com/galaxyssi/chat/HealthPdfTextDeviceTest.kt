package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.EditText
import android.widget.Button
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.lifecycle.Lifecycle
import androidx.test.platform.app.InstrumentationRegistry
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.state.RenderingMode
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthPdfTextDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun mixedReportUsesRealOcrForScansAndResumesAfterTheTextPage() = isolated { names, store ->
        val payload = pdf {
            addTextPage(this)
            addScan(this, header = false)
            addScan(this, header = true)
        }
        val job = import(store, payload)
        val pipeline = HealthImportPipeline(context, names.records)
        assertEquals(HealthImportOutcome.RETRY, pipeline.run(store, job.id) { store.job(job.id)?.nextPage == 1 })
        assertEquals(1, store.job(job.id)!!.nextPage)
        val first = requireNotNull(store.page(job.id, 1))
        assertEquals(HealthRecognition.PDF_TEXT, first.recognition)
        assertTrue(first.lines.any { it.text == "Glucose: 5.6 mmol/L" })
        assertTrue(first.lines.any { it.text == "Hemoglobin: 142 g/L" })
        assertEquals(HealthImportOutcome.COMPLETE, pipeline.run(store, job.id))
        val complete = requireNotNull(store.job(job.id))
        assertEquals(HealthImportState.REVIEW, complete.state)
        assertEquals(3, complete.nextPage)
        assertEquals(first, store.page(job.id, 1))
        val original = requireNotNull(store.original(complete.originalId))
        (2..3).forEach { number ->
            val page = requireNotNull(store.page(job.id, number))
            assertEquals(HealthRecognition.OCR, page.recognition)
            assertTrue(page.lines.any { it.text.contains("Glucose", true) })
        }
        val evidence = HealthOcrCandidates.suggest(complete, original, first).first().evidence!!
        assertTrue(evidence.hasReviewRegion())
        assertEquals(HealthRecognition.PDF_TEXT, HealthEvidence.from(evidence.json()).recognition)
        assertFalse(evidence.confirmed)
        HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
    }

    @Test fun rotatedAndCroppedTextBoundsCoverTheActualRenderedGlyphs() = isolated { _, store ->
        val job = import(store, pdf { addTextPage(this, rotate = true) })
        val original = requireNotNull(store.originalForJob(job.id))
        val page = requireNotNull(HealthPdfTextReader.open(context, store, original) {}).use { requireNotNull(it.page(0)) }
        val line = page.lines.single { it.text.contains("Glucose") }
        val bitmap = HealthReviewRaster.load(store, original, 1)
        try {
            val (left, top, right, bottom) = line.box
            var ink = 0
            var covered = 0
            for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                if (Color.red(bitmap.getPixel(x, y)) < 100) {
                    ink++
                    if (x * 1000 / bitmap.width in left..right && y * 1000 / bitmap.height in top..bottom) covered++
                }
            }
            assertTrue("No PDF text was drawn", ink > 100)
            assertTrue("Text box covers $covered of $ink ink pixels: ${line.box}", covered >= ink * .80)
            assertTrue("Text box unexpectedly covers most of the page", (right - left) * (bottom - top) < 150_000)
        } finally { bitmap.recycle() }
    }

    @Test fun invisibleLayerIsNotUsedAndPasswordFailureStaysExplicit() = isolated { names, store ->
        val hidden = import(store, pdf { addTextPage(this, hidden = true) })
        requireNotNull(HealthPdfTextReader.open(context, store, requireNotNull(store.originalForJob(hidden.id))) {}).use {
            assertNull(it.page(0))
        }
        val encrypted = import(store, pdf {
            addTextPage(this)
            protect(StandardProtectionPolicy("fixture-owner", "fixture-password", AccessPermission()))
        })
        assertEquals(HealthImportOutcome.FAILED, HealthImportPipeline(context, names.records).run(store, encrypted.id))
        assertEquals("pdf_password", store.job(encrypted.id)?.error)
        assertEquals(0, store.job(encrypted.id)?.nextPage)
    }

    @Test fun protectedMixedPdfResumesWithoutStoringPasswordAndKeepsExactOriginal() = isolated { names, store ->
        val bytes = pdf {
            addTextPage(this)
            addScan(this, header = false)
            protect(StandardProtectionPolicy("fixture-owner", "fixture-password", AccessPermission()).apply { encryptionKeyLength = 128; setPreferAES(true) })
        }
        try {
            val job = import(store, bytes)
            val pipeline = HealthImportPipeline(context, names.records)
            assertEquals(HealthImportOutcome.FAILED, pipeline.run(store, job.id))
            val wrong = "incorrect-fixture-password".toCharArray()
            assertEquals(HealthImportOutcome.FAILED, HealthProtectedPdfImport.run(context, store, job.id, wrong, { false }))
            assertTrue(wrong.all { it == '\u0000' })
            assertEquals("pdf_password_wrong", store.job(job.id)?.error)
            assertEquals(0, store.job(job.id)?.nextPage)
            assertTrue(store.pendingJobs().none { it.id == job.id })
            val right = "fixture-password".toCharArray()
            assertEquals(HealthImportOutcome.RETRY, HealthProtectedPdfImport.run(context, store, job.id, right,
                { store.job(job.id)?.nextPage == 1 }))
            assertTrue(right.all { it == '\u0000' })
            assertEquals("pdf_password_interrupted", store.job(job.id)?.error)
            val first = requireNotNull(store.page(job.id, 1))
            assertEquals(HealthRecognition.PDF_TEXT, first.recognition)
            assertTrue(first.lines.any { it.text.contains("Glucose") })
            assertEquals(HealthImportOutcome.FAILED, pipeline.run(store, job.id))
            assertEquals("pdf_password_interrupted", store.job(job.id)?.error)
            val visited = mutableListOf<Int>()
            assertEquals(HealthImportOutcome.COMPLETE, HealthProtectedPdfImport.run(context, store, job.id,
                "fixture-password".toCharArray(), { false }) { page, count -> visited += page; assertEquals(2, count) })
            assertEquals(listOf(2), visited)
            assertEquals(first, store.page(job.id, 1))
            val scan = requireNotNull(store.page(job.id, 2))
            assertEquals(HealthRecognition.OCR, scan.recognition)
            assertTrue(scan.lines.any { it.text.contains("Glucose", true) })
            assertEquals(HealthImportState.REVIEW, store.job(job.id)?.state)
            val original = requireNotNull(store.originalForJob(job.id))
            ByteArrayOutputStream().use { output ->
                store.copyVerified(original, output)
                assertArrayEquals(bytes, output.toByteArray())
            }
            HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
        } finally { bytes.fill(0) }
    }

    @Test fun protectedPdfHonorsExtractionPermissionButAllowsLocalPreview() = isolated { names, store ->
        val job = import(store, pdf {
            addTextPage(this)
            val permission = AccessPermission().apply { setCanExtractContent(false) }
            protect(StandardProtectionPolicy("fixture-owner", "fixture-password", permission).apply { encryptionKeyLength = 256 })
        })
        assertEquals(HealthImportOutcome.FAILED, HealthImportPipeline(context, names.records).run(store, job.id))
        assertEquals(HealthImportOutcome.FAILED, HealthProtectedPdfImport.run(context, store, job.id,
            "fixture-password".toCharArray(), { false }))
        assertEquals("pdf_permission", store.job(job.id)?.error)
        assertEquals(0, store.job(job.id)?.nextPage)
        val original = requireNotNull(store.originalForJob(job.id))
        val password = "fixture-password".toCharArray()
        HealthPdfTextReader.openProtected(context, store, original, password) {}.use { pdf ->
            assertTrue(password.all { it == '\u0000' })
            assertFalse(pdf.canExtract)
            val image = pdf.render(0, 600, 400_000)
            try {
                val pixels = IntArray(image.width * image.height)
                image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
                assertTrue(pixels.count { Color.red(it) < 100 } > 100)
            } finally { image.recycle() }
        }
        assertEquals(HealthImportOutcome.COMPLETE, HealthProtectedPdfImport.run(context, store, job.id,
            "fixture-owner".toCharArray(), { false }))
        assertEquals(HealthImportState.REVIEW, store.job(job.id)?.state)
    }

    @Test fun nativeQueuePasswordDialogCancelsRejectsWrongPasswordAndUnlocksForReview() = isolated { names, store ->
        assumeFalse("Native unlock requires an unlocked Android 10+ display", android.os.Build.VERSION.SDK_INT < 29 ||
            context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = import(store, pdf {
            addTextPage(this)
            protect(StandardProtectionPolicy("fixture-owner", "fixture-password", AccessPermission()))
        })
        assertEquals(HealthImportOutcome.FAILED, HealthImportPipeline(context, names.records).run(store, job.id))
        val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("health_review_test_id", names.fixture)
        ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
            fun clickLabel(id: Int, window: Boolean = false) {
                val deadline = SystemClock.elapsedRealtime() + 12_000
                do {
                    var clicked = false
                    scenario.onActivity {
                        val views = if (window) WindowInspector.getGlobalWindowViews().flatMap(::descendants) else descendants(it.window.decorView)
                        val labels = views.filterIsInstance<TextView>().filter { v -> v.isShown && v.text == context.getString(id) }
                        val label = if (window) labels.filterIsInstance<Button>().lastOrNull() ?: labels.lastOrNull() else labels.lastOrNull()
                        var target: View? = label
                        while (target != null && !target.isClickable) target = target.parent as? View
                        clicked = target?.performClick() == true
                    }
                    if (clicked) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Could not click ${context.getString(id)}")
            }
            fun password(value: String) {
                scenario.onActivity {
                    WindowInspector.getGlobalWindowViews().flatMap(::descendants).filterIsInstance<EditText>()
                        .single { field -> field.isShown && field.tag == "health-pdf-password-input" }.setText(value)
                }
                clickLabel(R.string.health_pdf_unlock, window = true)
            }
            fun await(error: String, state: HealthImportState) {
                val deadline = SystemClock.elapsedRealtime() + 12_000
                do {
                    if (store.job(job.id)?.let { it.state == state && it.error == error } == true) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Expected $state / $error, got ${store.job(job.id)?.state} / ${store.job(job.id)?.error}")
            }
            clickLabel(R.string.health_pdf_unlock)
            clickLabel(R.string.common_cancel, window = true)
            await("pdf_password", HealthImportState.FAILED)
            clickLabel(R.string.health_pdf_unlock)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity {
                assertFalse(WindowInspector.getGlobalWindowViews().flatMap(::descendants).any { v ->
                    v.isShown && v.tag == "health-pdf-password-input"
                })
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            clickLabel(R.string.health_pdf_unlock)
            password("wrong")
            await("pdf_password_wrong", HealthImportState.FAILED)
            clickLabel(R.string.health_pdf_unlock)
            password("fixture-password")
            await("", HealthImportState.REVIEW)
            clickLabel(R.string.health_review_title)
            fun waitForLabel(label: String) {
                val deadline = SystemClock.elapsedRealtime() + 12_000
                do {
                    var ready = false
                    scenario.onActivity {
                        ready = WindowInspector.getGlobalWindowViews().flatMap(::descendants)
                            .filterIsInstance<TextView>().any { v -> v.isShown && v.text == label }
                    }
                    if (ready) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Missing native label: $label")
            }
            waitForLabel(context.getString(R.string.health_review_pdf_text_method, 1))
            clickLabel(R.string.health_view_original)
            clickLabel(R.string.health_open_original)
            clickLabel(R.string.health_pdf_unlock, window = true)
            password("fixture-password")
            waitForLabel(context.getString(R.string.health_preview_page, 1, 1))
        }
    }

    @Test fun nativeReviewLabelsTheActualSourceOfEachPage() = isolated { names, store ->
        assumeFalse("Native review requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val job = import(store, pdf { addTextPage(this); addScan(this, header = false) })
        assertEquals(HealthImportOutcome.COMPLETE, HealthImportPipeline(context, names.records).run(store, job.id))
        val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("health_job", job.id)
            .putExtra("health_review_test_id", names.fixture)
        ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
            fun waitFor(text: String, requireImage: Boolean = false) {
                val deadline = SystemClock.elapsedRealtime() + 12_000
                do {
                    var ready = false
                    scenario.onActivity {
                        val views = descendants(it.window.decorView)
                        ready = views.filterIsInstance<TextView>().any { label -> label.text == text } &&
                            (!requireImage || views.filterIsInstance<HealthReviewSourceView>().any { image -> image.bitmap != null })
                    }
                    if (ready) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Missing actual page recognition label: $text")
            }
            waitFor(context.getString(R.string.health_review_pdf_text_method, 1), requireImage = true)
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try {
                    File(context.getExternalFilesDir(null), "health-pdf-text-source.png").outputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                } finally { bitmap.recycle() }
            }
            scenario.onActivity {
                assertTrue(descendants(it.window.decorView).filterIsInstance<TextView>()
                    .single { view -> view.text == context.getString(R.string.health_next_page) }.performClick())
            }
            waitFor(context.getString(R.string.health_review_source_method, 2))
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun pdf(write: PDDocument.() -> Unit): ByteArray {
        PDFBoxResourceLoader.init(context)
        return ByteArrayOutputStream().use { output ->
            PDDocument().use { it.write(); it.save(output) }
            output.toByteArray()
        }
    }

    private fun addTextPage(pdf: PDDocument, rotate: Boolean = false, hidden: Boolean = false) {
        val page = PDPage(PDRectangle(600f, 400f))
        if (rotate) { page.cropBox = PDRectangle(40f, 40f, 500f, 320f); page.rotation = 90 }
        pdf.addPage(page)
        PDPageContentStream(pdf, page).use { stream ->
            if (hidden) stream.setRenderingMode(RenderingMode.NEITHER)
            text(stream, "Glucose: 5.6 mmol/L", 90f, 270f)
            if (!rotate) text(stream, "Hemoglobin: 142 g/L", 90f, 190f)
        }
    }

    private fun addScan(pdf: PDDocument, header: Boolean) {
        val page = PDPage(PDRectangle(600f, 400f))
        pdf.addPage(page)
        val bitmap = Bitmap.createBitmap(1000, 600, Bitmap.Config.ARGB_8888)
        val image = try {
            bitmap.eraseColor(Color.WHITE)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 74f; color = Color.BLACK }
            Canvas(bitmap).apply { drawText("Glucose: 5.6 mmol/L", 70f, 200f, paint); drawText("Hemoglobin: 142 g/L", 70f, 350f, paint) }
            LosslessFactory.createFromImage(pdf, bitmap)
        } finally { bitmap.recycle() }
        PDPageContentStream(pdf, page).use { stream ->
            stream.drawImage(image, 30f, 25f, 540f, 300f)
            if (header) text(stream, "Synthetic report", 90f, 350f)
        }
    }

    private fun text(stream: PDPageContentStream, value: String, x: Float, y: Float) {
        stream.beginText()
        stream.setFont(PDType1Font.HELVETICA, 26f)
        stream.newLineAtOffset(x, y)
        stream.showText(value)
        stream.endText()
    }

    private fun import(store: HealthOriginalStore, payload: ByteArray): HealthImportJob {
        val job = HealthImportJob(UUID.randomUUID().toString(), "content://fixture/report", System.currentTimeMillis(),
            name = "synthetic.pdf", mime = "application/pdf", totalBytes = payload.size.toLong())
        store.createJob(job)
        store.importOriginal(job.id, payload.inputStream(), job.name, job.mime, "file")
        return job
    }

    private fun isolated(block: (HealthOverviewDatabases, HealthOriginalStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { block(names, it) } }
        finally { clearHealthOverviewFixture(context, names) }
    }
}
