package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import java.io.Closeable
import java.util.concurrent.TimeUnit

internal class HealthOcrEngine : Closeable {
    private val recognizer = lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }
    private val pending = mutableSetOf<Bitmap>()
    fun image(store: HealthOriginalStore, original: HealthOriginal): HealthOcrPage {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        store.input(original).use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw HealthImportFailure("image_unsupported")
        var sample = 1
        while (bounds.outWidth.toLong() * bounds.outHeight / sample / sample > 6_000_000L) sample *= 2
        val bitmap = store.input(original).use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            ?: throw HealthImportFailure("image_unsupported")
        try {
        val orientation = store.input(original).use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
        val matrix = Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(270f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(270f)
            }
        }
        val upright = if (matrix.isIdentity) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        return try { recognize(upright, 1) } finally { if (upright !== bitmap) release(upright) }
        } finally { release(bitmap) }
    }
    fun pdf(store: HealthOriginalStore, original: HealthOriginal, firstPage: Int, cancelled: () -> Unit,
        onCount: (Int) -> Unit, onPage: (HealthOcrPage) -> Unit, textSource: HealthPdfTextReader? = null) {
        val descriptor = store.descriptor(original)
        val renderer = try { PdfRenderer(descriptor) } catch (failure: Exception) {
            descriptor.close()
            throw HealthImportFailure(if (failure is SecurityException) "pdf_password" else "pdf_unsupported")
        }
        renderer.use { pdf ->
            onCount(pdf.pageCount)
            val text = textSource?.takeIf { it.pageCount == pdf.pageCount }
            for (index in firstPage until pdf.pageCount) {
                cancelled()
                val extracted = text?.page(index)
                if (extracted != null) {
                    cancelled(); onPage(extracted)
                    continue
                }
                pdf.openPage(index).use { page ->
                    val scale = minOf(3.0, kotlin.math.sqrt(6_000_000.0 / (page.width.toDouble() * page.height)))
                    val bitmap = Bitmap.createBitmap((page.width * scale).toInt().coerceAtLeast(1),
                        (page.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        cancelled(); onPage(recognize(bitmap, index + 1))
                    } finally { release(bitmap) }
                }
            }
        }
    }
    private fun recognize(bitmap: Bitmap, number: Int): HealthOcrPage {
        val task = recognizer.value.process(InputImage.fromBitmap(bitmap, 0))
        val text = try { Tasks.await(task, 90, TimeUnit.SECONDS) }
        catch (failure: Exception) {
            if (!task.isComplete) {
                synchronized(pending) { pending += bitmap }
                // A timed-out native task may still read its bitmap; release only after completion.
                task.addOnCompleteListener(java.util.concurrent.Executor { it.run() }) {
                    synchronized(pending) { pending -= bitmap; if (!bitmap.isRecycled) bitmap.recycle() }
                }
            }
            if (failure is java.util.concurrent.TimeoutException) throw HealthImportFailure("ocr_timeout")
            throw failure
        }
        val lines = text.textBlocks.flatMap { block -> block.lines }.map { line ->
            val box = line.boundingBox
            HealthOcrLine(line.text, if (box == null) emptyList() else listOf(
                box.left * 1000 / bitmap.width, box.top * 1000 / bitmap.height,
                box.right * 1000 / bitmap.width, box.bottom * 1000 / bitmap.height).map { it.coerceIn(0, 1000) })
        }
        if (lines.size > 10_000 || lines.sumOf { it.text.length.toLong() } > 1_000_000) throw HealthImportFailure("page_complexity")
        return HealthOcrPage(number, bitmap.width, bitmap.height, lines, blurry = lines.isEmpty())
    }
    private fun release(bitmap: Bitmap) = synchronized(pending) { if (bitmap !in pending && !bitmap.isRecycled) bitmap.recycle() }
    override fun close() { if (recognizer.isInitialized()) recognizer.value.close() }
}
