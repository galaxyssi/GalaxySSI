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

internal class HealthAtlasLabeledImage(private val activity: Activity, drawable: Int, description: String,
    data: HealthBodyAtlas, whole: Boolean, selected: (HealthAtlasItem) -> Unit) : FrameLayout(activity) {
    private data class Marker(val id: String, val x: Float, val y: Float)
    private val ui = HealthCenterViews(activity)
    private val markers = if (whole) listOf(Marker("brain", .50f, .045f), Marker("heart", .54f, .28f),
        Marker("liver", .45f, .34f), Marker("small-intestine", .51f, .44f)) else listOf(
        Marker("atria", .28f, .46f), Marker("coronary-vessels", .57f, .68f), Marker("ventricles", .61f, .84f))
    val image = ImageView(activity).apply {
        setImageResource(drawable); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = description
        tag = "atlas-art-image"
    }
    private val imageRect = RectF()
    private val labels = markers.map { marker ->
        ui.text(data[marker.id]!!.name, 13f).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = ui.dp(44); maxLines = 2
            isFocusable = true; setOnClickListener { selected(data[marker.id]!!) }; tag = "atlas-hotspot-${marker.id}"
            setPadding(ui.dp(4), 0, 0, 0)
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
                canvas.drawCircle(x, y, ui.dp(3).toFloat(), paint)
            }
        }
    }
    init { addView(image); addView(guides); labels.forEach(::addView) }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec); val h = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(w,h)
        image.measure(MeasureSpec.makeMeasureSpec((w * .80f).toInt(), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        guides.measure(MeasureSpec.makeMeasureSpec(w,MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h,MeasureSpec.EXACTLY))
        labels.forEach { it.measure(MeasureSpec.makeMeasureSpec((w * .26f).toInt(),MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(ui.dp(48),MeasureSpec.EXACTLY)) }
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        image.layout(0,0,image.measuredWidth,height); guides.layout(0,0,width,height)
        val drawable = image.drawable
        imageRect.set(0f,0f,drawable.intrinsicWidth.toFloat(),drawable.intrinsicHeight.toFloat())
        image.imageMatrix.mapRect(imageRect)
        var previous = -ui.dp(48)
        markers.forEachIndexed { index, marker ->
            val y = (imageRect.top + imageRect.height() * marker.y - ui.dp(24)).toInt()
                .coerceAtLeast(previous + ui.dp(48)).coerceAtMost(height - ui.dp(48))
            val x = (width * .74f).toInt(); labels[index].layout(x,y,width,y + ui.dp(48)); previous = y
        }
        guides.invalidate()
    }
}
