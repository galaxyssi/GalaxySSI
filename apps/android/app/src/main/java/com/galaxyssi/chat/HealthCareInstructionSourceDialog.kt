package com.galaxyssi.chat

import android.app.Activity
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout

internal class HealthCareInstructionSourceDialog(private val activity: Activity, private val raster: Bitmap,
    private val source: HealthCareInstructionSource) : Dialog(activity, android.R.style.Theme_Black_NoTitleBar) {
    private val image = HealthReviewSourceView(activity).apply { bitmap = raster; mark(source.boxes); tag = "instruction-source-image" }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setOwnerActivity(activity)
        val ui = HealthCenterViews(activity)
        val root = ui.column().apply { setBackgroundColor(Color.BLACK) }
        root.addView(ui.line().apply {
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { dismiss() }.apply { imageTintList = ColorStateList.valueOf(Color.WHITE) })
            addView(ui.text(activity.getString(R.string.health_document_page, source.original.page, source.original.pageCount), 15f).apply {
                setTextColor(Color.WHITE); gravity = Gravity.CENTER
            }, LinearLayout.LayoutParams(0, -2, 1f))
        })
        root.addView(GalaxySSIPinchZoomViewport(activity).apply { attach(image) }, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        setOnDismissListener { image.bitmap = null; HealthOriginalThumbnail.clear(raster); root.removeAllViews() }
    }
}
