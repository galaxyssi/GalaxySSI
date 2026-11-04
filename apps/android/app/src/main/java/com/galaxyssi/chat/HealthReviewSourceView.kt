package com.galaxyssi.chat

import android.app.Activity
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.pdf.PdfRenderer
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import androidx.exifinterface.media.ExifInterface
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.sqrt

private fun validReviewBox(box: List<Int>) =
    box.size == 4 && box.all { it in 0..1000 } && box[0] < box[2] && box[1] < box[3]

internal fun HealthEvidence.hasReviewRegion() = boxes.any(::validReviewBox)
internal fun HealthRecognition.label() =
    if (this == HealthRecognition.PDF_TEXT) R.string.health_review_pdf_text_method else R.string.health_review_source_method

internal object HealthReviewRaster {
    private const val MAX_EDGE = 1600
    private const val MAX_PIXELS = 2_000_000.0

    fun load(store: HealthOriginalStore, original: HealthOriginal, page: Int): Bitmap {
        require(page > 0)
        if (original.mime == "application/pdf") {
            val descriptor = store.descriptor(original)
            val renderer = try { PdfRenderer(descriptor) } catch (error: Throwable) { descriptor.close(); throw error }
            return renderer.use {
                require(page <= it.pageCount)
                it.openPage(page - 1).use { pdf ->
                    val scale = minOf(3.0, MAX_EDGE.toDouble() / maxOf(pdf.width, pdf.height),
                        sqrt(MAX_PIXELS / (pdf.width.toDouble() * pdf.height)))
                    val bitmap = Bitmap.createBitmap((pdf.width * scale).toInt().coerceAtLeast(1),
                        (pdf.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        pdf.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bitmap
                    } catch (error: Throwable) { bitmap.recycle(); throw error }
                }
            }
        }
        require(page == 1 && original.mime.startsWith("image/"))
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        store.input(original).use { BitmapFactory.decodeStream(it, null, options) }
        require(options.outWidth > 0 && options.outHeight > 0)
        var sample = 1
        while (options.outWidth.toLong() * options.outHeight / sample / sample > MAX_PIXELS ||
            maxOf(options.outWidth, options.outHeight) / sample > MAX_EDGE) sample *= 2
        val orientation = store.input(original).use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }
        val bitmap = store.input(original).use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: throw HealthImportFailure("image_unsupported")
        val upright = try { AgentImagePipeline.applyOrientation(bitmap, orientation) }
        catch (error: Throwable) { bitmap.recycle(); throw error }
        if (upright !== bitmap) bitmap.recycle()
        return upright
    }
}

/** The page and its OCR marks share the same coordinates and pinch/drag transform. */
internal class HealthReviewSourceView(activity: Activity) : View(activity) {
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val shade = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x3022b879 }
    private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xff087248.toInt()
        style = Paint.Style.STROKE
        strokeWidth = resources.displayMetrics.density * 1.7f
    }
    private val from = Rect()
    private val to = RectF()
    private val marker = RectF()
    private var marks = emptyList<RectF>()
    private var focus = false
    var bitmap: Bitmap? = null
        set(value) { field = value; invalidate() }

    fun mark(boxes: List<List<Int>>, focused: Boolean = false) {
        marks = boxes.mapNotNull { box ->
            if (!validReviewBox(box)) null
            else RectF(box[0] / 1000f, box[1] / 1000f, box[2] / 1000f, box[3] / 1000f)
        }
        focus = focused
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val page = bitmap ?: return
        if (page.isRecycled || width == 0 || height == 0) return
        sourceRect(page)
        val scale = minOf(width.toFloat() / from.width(), height.toFloat() / from.height())
        val left = (width - from.width() * scale) / 2f
        val top = (height - from.height() * scale) / 2f
        to.set(left, top, left + from.width() * scale, top + from.height() * scale)
        canvas.drawBitmap(page, from, to, bitmapPaint)
        canvas.save()
        canvas.clipRect(to)
        for (box in marks) {
            marker.set(left + (box.left * page.width - from.left) * scale, top + (box.top * page.height - from.top) * scale,
                left + (box.right * page.width - from.left) * scale, top + (box.bottom * page.height - from.top) * scale)
            canvas.drawRect(marker, shade)
            canvas.drawRect(marker, outline)
        }
        canvas.restore()
    }

    private fun sourceRect(page: Bitmap) {
        from.set(0, 0, page.width, page.height)
        if (!focus || marks.isEmpty()) return
        val union = RectF(marks.first())
        marks.drop(1).forEach(union::union)
        val spanX = (union.width() + .12f).coerceIn(.34f, 1f)
        val spanY = (union.height() + .10f).coerceIn(.20f, 1f)
        val x = (union.centerX() - spanX / 2).coerceIn(0f, 1f - spanX)
        val y = (union.centerY() - spanY / 2).coerceIn(0f, 1f - spanY)
        from.set(floor(x * page.width).toInt(), floor(y * page.height).toInt(),
            ceil((x + spanX) * page.width).toInt().coerceAtMost(page.width),
            ceil((y + spanY) * page.height).toInt().coerceAtMost(page.height))
    }
}

internal class HealthReviewSourceDialog(
    private val activity: Activity,
    bitmap: Bitmap,
    private val evidence: HealthEvidence,
    private val displayedPage: Int
) : Dialog(activity, android.R.style.Theme_Black_NoTitleBar) {
    private val image = HealthReviewSourceView(activity).apply {
        this.bitmap = bitmap
        tag = "health-review-source-zoom"
        contentDescription = activity.getString(R.string.health_review_source_image)
    }
    override fun onCreate(state: android.os.Bundle?) {
        super.onCreate(state)
        setOwnerActivity(activity)
        val ui = HealthCenterViews(activity)
        val viewport = GalaxySSIPinchZoomViewport(activity)
        val root = ui.column().apply { setBackgroundColor(Color.BLACK) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { dismiss() }.apply {
                imageTintList = ColorStateList.valueOf(Color.WHITE)
            })
            addView(ui.text(activity.getString(evidence.recognition.label(), displayedPage), 15f).apply {
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(View(activity), LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)))
        })
        viewport.attach(image)
        root.addView(viewport, LinearLayout.LayoutParams(-1, 0, 1f))
        var focused = evidence.hasReviewRegion()
        image.mark(evidence.boxes, focused)
        if (focused) root.addView(ui.text(activity.getString(R.string.health_review_full_page), 15f, bold = true).apply {
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            minimumHeight = ui.dp(48)
            isFocusable = true
            setOnClickListener {
                focused = !focused
                image.mark(evidence.boxes, focused)
                setText(if (focused) R.string.health_review_full_page else R.string.health_review_focus)
            }
        })
        setContentView(root)
        window?.setLayout(-1, -1)
        setOnDismissListener { image.bitmap = null }
    }
}
