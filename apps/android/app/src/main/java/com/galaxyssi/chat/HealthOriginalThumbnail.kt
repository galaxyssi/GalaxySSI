package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer

internal object HealthOriginalThumbnail {
    const val EDGE = 192
    fun load(store: HealthOriginalStore, original: HealthOriginal): Bitmap? {
        if (!store.present(original)) return null
        val source = when (HealthOriginalKind.of(original)) {
            HealthOriginalKind.IMAGE -> HealthPhotoInspector.decode(store, original, EDGE.toLong() * EDGE)
            HealthOriginalKind.PDF -> {
                val descriptor = store.descriptor(original)
                val renderer = try { PdfRenderer(descriptor) } catch (failure: Throwable) { descriptor.close(); throw failure }
                renderer.use { pdf ->
                    check(pdf.pageCount > 0)
                    pdf.openPage(0).use { page ->
                        val ratio = minOf(EDGE.toDouble() / page.width, EDGE.toDouble() / page.height)
                        Bitmap.createBitmap((page.width * ratio).toInt().coerceAtLeast(1), (page.height * ratio).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888).also {
                            try { it.eraseColor(Color.WHITE); page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) } catch (failure: Throwable) { it.recycle(); throw failure }
                        }
                    }
                }
            }
            else -> return null
        }
        try {
            val ratio = minOf(1.0, EDGE.toDouble() / source.width, EDGE.toDouble() / source.height)
            val target = Bitmap.createBitmap((source.width * ratio).toInt().coerceAtLeast(1), (source.height * ratio).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            return try { Canvas(target).drawBitmap(source, null, Rect(0, 0, target.width, target.height), null); target }
            catch (failure: Throwable) { target.recycle(); throw failure }
        } finally { source.recycle() }
    }
    fun clear(bitmap: Bitmap) { if (!bitmap.isRecycled) { if (bitmap.isMutable) bitmap.eraseColor(Color.TRANSPARENT); bitmap.recycle() } }
}
