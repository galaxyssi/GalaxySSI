package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import java.io.ByteArrayOutputStream

/** Ephemeral model evidence only; never saved, uploaded as a user attachment or shown as another photo. */
internal object AgentVisionOrientationSheet {
    const val CAPTION = "Orientation reference for source image 1, NOT additional user photos. " +
        "The four panels show the SAME image at 0, 90, 180 and 270 degrees clockwise. " +
        "Compare them before choosing a reading; use the original image for fine detail. " +
        "Read connected content in its natural direction, not isolated strokes. " +
        "Interpret handwriting by the complete expression, spacing and conventional notation; " +
        "a curved numeral is not necessarily a parenthesis. Do not claim cropping or missing " +
        "content when the strokes and surrounding page margins are fully visible. " +
        "If alternatives remain plausible, state the ambiguity rather than inventing a transcription."
    private const val TILE = 640
    private const val HEADER = 32

    fun create(images: List<CloudImagePayload>): ByteArray? {
        val image = images.singleOrNull() ?: return null
        // Preserve animated input semantics. The original always remains the first visual input.
        if (image.mimeType == "image/gif") return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(image.bytes, 0, image.bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var source = BitmapFactory.decodeByteArray(image.bytes, 0, image.bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = AgentImagePipeline.sampleSize(bounds.outWidth, bounds.outHeight, TILE, TILE)
                inMutable = true
            }) ?: return null
        try {
            val orientation = runCatching {
                java.io.ByteArrayInputStream(image.bytes).use {
                    android.media.ExifInterface(it).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)
                }
            }.getOrDefault(1)
            val oriented = AgentImagePipeline.applyOrientation(source, orientation)
            if (oriented !== source) {
                source.eraseColor(Color.TRANSPARENT)
                source.recycle()
                source = oriented
            }
            val sheet = Bitmap.createBitmap(TILE * 2, (TILE + HEADER) * 2, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(sheet)
                canvas.drawColor(Color.WHITE)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                    color = Color.BLACK
                    textSize = 18f
                }
                val scale = minOf(TILE.toFloat() / source.width, TILE.toFloat() / source.height)
                val halfWidth = source.width * scale / 2
                val halfHeight = source.height * scale / 2
                for (index in 0..3) {
                    val x = (index % 2 * TILE).toFloat()
                    val y = (index / 2 * (TILE + HEADER)).toFloat()
                    canvas.drawText("Source 1 / ${index * 90} deg clockwise", x + 12, y + 23, paint)
                    canvas.save()
                    canvas.translate(x + TILE / 2, y + HEADER + TILE / 2)
                    canvas.rotate(index * 90f)
                    canvas.drawBitmap(source, null, RectF(-halfWidth, -halfHeight, halfWidth, halfHeight), paint)
                    canvas.restore()
                }
                for (quality in listOf(80, 60, 40, 25)) {
                    val bytes = ByteArrayOutputStream().use { output ->
                        sheet.compress(Bitmap.CompressFormat.JPEG, quality, output)
                        output.toByteArray()
                    }
                    if (bytes.size <= CloudImagePayload.MAX_BYTES) return bytes
                    bytes.wipeSensitive()
                }
                return null
            } finally {
                sheet.eraseColor(Color.TRANSPARENT)
                sheet.recycle()
            }
        } finally {
            if (source.isMutable) source.eraseColor(Color.TRANSPARENT)
            source.recycle()
        }
    }
}
