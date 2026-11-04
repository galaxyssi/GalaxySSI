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
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
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
