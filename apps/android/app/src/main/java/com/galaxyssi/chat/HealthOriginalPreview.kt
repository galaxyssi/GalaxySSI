package com.galaxyssi.chat

import android.app.Activity
import android.app.Dialog
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Executors

/** Uses the existing pinch/drag viewport; PDF seeks decrypt authenticated segments on demand. */
internal class HealthOriginalPreview(
    private val activity: Activity, private val original: HealthOriginal, private val onSave: () -> Unit
) : Dialog(activity, android.R.style.Theme_Black_NoTitleBar) {
    private val ui = HealthCenterViews(activity)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val image = ImageView(activity).apply { scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = original.name }
    private val status = ui.text(activity.getString(R.string.health_import_preparing), 14f).apply { gravity = Gravity.CENTER; setTextColor(Color.LTGRAY) }
    private val count = ui.text("", 14f).apply { gravity = Gravity.CENTER; setTextColor(Color.WHITE) }
    private var bitmap: Bitmap? = null
    private var page = 0
    private var pages = 1
    private var revision = 0
    private var released = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setOwnerActivity(activity)
        val root = ui.column().apply { setBackgroundColor(Color.BLACK) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { dismiss() }.apply { imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE) })
            addView(ui.text(original.name, 15f).apply { maxLines = 2; setTextColor(Color.WHITE); gravity = Gravity.CENTER }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_rich_download, R.string.health_save_original) { onSave() }.apply { imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE) })
        }, LinearLayout.LayoutParams(-1, ui.dp(56)))
        val viewport = GalaxySSIPinchZoomViewport(activity).apply { attach(image) }
        root.addView(FrameLayout(activity).apply {
            addView(viewport, FrameLayout.LayoutParams(-1, -1)); addView(status, FrameLayout.LayoutParams(-1, -1))
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        if (original.mime == "application/pdf") root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_previous_page) { if (page > 0) { page--; load() } }.apply { imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE) })
            addView(count, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_next_page) { if (page + 1 < pages) { page++; load() } }.apply {
                rotation = 180f; imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
            })
        })
        setContentView(root)
        window?.setLayout(-1, -1)
        setOnDismissListener {
            released = true; revision++; image.setImageDrawable(null); bitmap?.recycle(); bitmap = null
            worker.shutdownNow()
        }
        load()
    }
    private fun load() {
        val token = ++revision
        val selected = page
        status.visibility = View.VISIBLE
        worker.execute {
            val result = runCatching {
                if (original.mime.startsWith("image/")) {
                    AgentImagePipeline.loadPreview(activity.applicationContext, HealthOriginalContentProvider.uri(activity, original.id), 1600, 1600)
                        ?: throw HealthImportFailure("image_unsupported")
                } else if (original.mime == "application/pdf") {
                    HealthOriginalStore(activity.applicationContext).use { store ->
                        val descriptor = store.descriptor(original)
                        val renderer = try { PdfRenderer(descriptor) } catch (error: Exception) { descriptor.close(); throw error }
                        renderer.use {
                            pages = it.pageCount
                            it.openPage(selected.coerceIn(0, pages - 1)).use { pdf ->
                                val scale = minOf(2.5, kotlin.math.sqrt(2_000_000.0 / (pdf.width.toDouble() * pdf.height)))
                                val target = Bitmap.createBitmap((pdf.width * scale).toInt().coerceAtLeast(1), (pdf.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                                try { target.eraseColor(Color.WHITE); pdf.render(target, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY); target }
                                catch (error: Throwable) { target.recycle(); throw error }
                            }
                        }
                    }
                } else throw HealthImportFailure("preview_unsupported")
            }
            main.post {
                if (released || token != revision) { result.getOrNull()?.recycle(); return@post }
                result.fold({ next ->
                    image.setImageBitmap(next); bitmap?.recycle(); bitmap = next
                    status.visibility = View.GONE; count.text = activity.getString(R.string.health_preview_page, page + 1, pages)
                }, {
                    status.text = activity.getString(R.string.health_original_preview_failed)
                })
            }
        }
    }
}
