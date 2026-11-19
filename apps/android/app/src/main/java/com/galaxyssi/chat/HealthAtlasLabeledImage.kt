package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

internal class HealthAtlasLabeledImage(activity: Activity, plate: HealthAtlasPlate, description: String,
    data: HealthBodyAtlas, currentId: String?, selected: (HealthAtlasItem) -> Unit) : FrameLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val markers = plate.markers.sortedBy { it.y }
    private val controlsInset = if (plate.owner == null) ui.dp(144) else 0
    val image = ImageView(activity).apply {
        setImageResource(plate.drawable); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = description
        tag = "atlas-art-image"
    }
    private val imageRect = RectF()
    private val labels = markers.map { marker ->
        ui.text(data[marker.id]!!.name, 13f, bold = marker.id == currentId).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = ui.dp(48)
            isSelected = marker.id == currentId
            if (isSelected) setTextColor(activity.getColor(R.color.health_overview_green))
            else { isFocusable = true; setOnClickListener { selected(data[marker.id]!!) } }
            tag = "atlas-hotspot-${marker.id}"
            setPadding(ui.dp(6), ui.dp(4), 0, ui.dp(4))
        }
    }
    private val guides = object : View(activity) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas: Canvas) {
            paint.strokeWidth = resources.displayMetrics.density
            markers.forEachIndexed { index, marker ->
                val x = imageRect.left + imageRect.width() * marker.x
                val y = imageRect.top + imageRect.height() * marker.y
                val label = labels[index]
                paint.color = activity.getColor(R.color.text_primary)
                canvas.drawLine(x, y, label.left.toFloat(), label.top + label.height / 2f, paint)
                paint.color = activity.getColor(R.color.health_overview_green)
                canvas.drawCircle(x, y, ui.dp(if (label.isSelected) 5 else 3).toFloat(), paint)
            }
        }
    }
    init { addView(image); addView(guides); labels.forEach(::addView) }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val labelWidth = (w * .28f).toInt()
        labels.forEach { it.measure(MeasureSpec.makeMeasureSpec(labelWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)) }
        val required = labels.sumOf { it.measuredHeight } + ui.dp(8) * (labels.size + 1) + controlsInset
        val h = resolveSize(required.coerceAtLeast(suggestedMinimumHeight), heightMeasureSpec)
        setMeasuredDimension(w, h)
        image.measure(MeasureSpec.makeMeasureSpec(w - labelWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        guides.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        image.layout(0,0,image.measuredWidth,height); guides.layout(0,0,width,height)
        val drawable = image.drawable
        imageRect.set(0f,0f,drawable.intrinsicWidth.toFloat(),drawable.intrinsicHeight.toFloat())
        image.imageMatrix.mapRect(imageRect)
        val gap = ui.dp(8)
        // Pack in visual order, then move overflow upward without collapsing adjacent labels.
        val tops = IntArray(labels.size)
        for (i in labels.indices) {
            val desired = (imageRect.top + imageRect.height() * markers[i].y - labels[i].measuredHeight / 2f).toInt()
            tops[i] = desired.coerceAtLeast(if (i == 0) gap else tops[i - 1] + labels[i - 1].measuredHeight + gap)
        }
        var bottom = height - gap - controlsInset
        for (i in labels.indices.reversed()) {
            tops[i] = tops[i].coerceAtMost(bottom - labels[i].measuredHeight)
            bottom = tops[i] - gap
        }
        labels.forEachIndexed { i, label -> label.layout(image.measuredWidth, tops[i], width, tops[i] + label.measuredHeight) }
        guides.invalidate()
    }
}
