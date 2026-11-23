package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Canvas
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthAtlasFigureFrame(activity: Activity, private val art: View, key: String,
    private val header: View? = null, captionKey: String = "atlas-figure-legend") : FrameLayout(activity) {
    companion object { const val LEGEND_OVERLAP_DP = 28 }
    private val ui = HealthCenterViews(activity)
    private val ground = activity.getColor(R.color.health_atlas_film_ground)
    private val overlap = ui.dp(LEGEND_OVERLAP_DP)
    private val captions = HealthAtlasCaptionSizes()
    val legend: LinearLayout = object : LinearLayout(activity) {
        private val fade = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(ground and 0x00ffffff, ground))
        private val solid = android.graphics.Paint().apply { color = ground }
        override fun onDraw(canvas: Canvas) {
            // Leave the beginning of the legend transparent over the illustration.
            fade.setBounds(0, 0, width, paddingTop)
            fade.draw(canvas)
            canvas.drawRect(0f, paddingTop.toFloat(), width.toFloat(), height.toFloat(), solid)
        }
    }.apply {
        tag = captionKey
        orientation = LinearLayout.VERTICAL
        setWillNotDraw(false)
        setPadding(ui.dp(16), ui.dp(18), ui.dp(16), ui.dp(14))
    }

    init {
        tag = key
        background = ui.background(ground)
        clipToOutline = true
        header?.let { addView(it, LayoutParams(-1, -2)) }
        addView(art, LayoutParams(-1, -2))
        addView(legend, LayoutParams(-1, -2))
    }

    fun reserveCaption(view: TextView, texts: List<String>) {
        captions.add(view, texts, legend.paddingStart + legend.paddingEnd)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val exactWidth = MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        val naturalHeight = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        captions.measure(width)
        legend.measure(exactWidth, naturalHeight)
        header?.measure(exactWidth, naturalHeight)
        val available = (MeasureSpec.getSize(heightMeasureSpec) - (header?.measuredHeight ?: 0) -
            legend.measuredHeight + overlap).coerceAtLeast(0)
        val artHeight = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.EXACTLY)
            MeasureSpec.makeMeasureSpec(available, MeasureSpec.EXACTLY) else naturalHeight
        art.measure(exactWidth, artHeight)
        setMeasuredDimension(width, resolveSize((header?.measuredHeight ?: 0) + art.measuredHeight +
            legend.measuredHeight - sharedHeight(), heightMeasureSpec))
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val artTop = header?.measuredHeight ?: 0
        header?.layout(0, 0, width, artTop)
        art.layout(0, artTop, width, artTop + art.measuredHeight)
        val legendTop = art.bottom - sharedHeight()
        legend.layout(0, legendTop, width, legendTop + legend.measuredHeight)
    }

    private fun sharedHeight(): Int = minOf(overlap, art.measuredHeight, legend.measuredHeight)
}
