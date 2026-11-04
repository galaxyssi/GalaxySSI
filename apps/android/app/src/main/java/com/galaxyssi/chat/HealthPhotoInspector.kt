package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import androidx.exifinterface.media.ExifInterface
import com.canhub.cropper.CropImageView

internal object HealthPhotoInspector {
    fun decode(store: HealthOriginalStore, original: HealthOriginal, pixels: Long): Bitmap {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        store.input(original).use { BitmapFactory.decodeStream(it, null, options) }
        if (options.outWidth <= 0 || options.outHeight <= 0) throw HealthImportFailure("image_unsupported")
        var sample = 1
        while (options.outWidth.toLong() * options.outHeight / sample / sample > pixels) sample *= 2
        val source = store.input(original).use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            ?: throw HealthImportFailure("image_unsupported")
        try {
            val orientation = orientation(store, original)
            val matrix = Matrix().apply {
                when (orientation) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                    ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(270f)
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(270f); postScale(-1f, 1f) }
                }
            }
            if (matrix.isIdentity) return source
            val upright = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            if (upright !== source) source.recycle()
            return upright
        } catch (failure: Throwable) { source.recycle(); throw failure }
    }
    private fun orientation(store: HealthOriginalStore, original: HealthOriginal) = store.input(original).use {
        ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    }
    fun inspect(store: HealthOriginalStore, original: HealthOriginal, report: Boolean = false): HealthPhotoQuality {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        store.input(original).use { BitmapFactory.decodeStream(it, null, bounds) }
        val rotation = when (orientation(store, original)) {
            ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSPOSE -> 90
            ExifInterface.ORIENTATION_ROTATE_180, ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180
            ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSVERSE -> 270
            else -> 0
        }
        val bitmap = decode(store, original, 1_000_000)
        try {
            if (bitmap.width < 3 || bitmap.height < 3) throw HealthImportFailure("image_unsupported")
            val values = IntArray(bitmap.width * bitmap.height)
            try {
                bitmap.getPixels(values, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                values.indices.forEach { i -> val c = values[i]; values[i] = ((c ushr 16 and 255) * 77 + (c ushr 8 and 255) * 150 + (c and 255) * 29) ushr 8 }
                val score = HealthPhotoQualityPolicy.inspect(values, bitmap.width, bitmap.height)
                val suggestion = if (report && score.second >= 35.0) HealthReportEdges.detect(values, bitmap.width, bitmap.height) else null
                return HealthPhotoQuality(bounds.outWidth, bounds.outHeight, rotation, score.first, score.second, report, suggestion)
            } finally { values.fill(0) }
        } finally { bitmap.recycle() }
    }
}

internal fun CropImageView.applyHealthReportCrop(suggested: HealthReportCrop) {
    val original = wholeImageRect ?: return
    if (original.isEmpty) return
    val sideways = rotatedDegrees % 180 != 0
    val width = if (sideways) original.height() else original.width()
    val height = if (sideways) original.width() else original.height()
    val bounds = suggested.pixels(width, height)
    cropRect = Rect(bounds[0], bounds[1], bounds[2], bounds[3])
}
