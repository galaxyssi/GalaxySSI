package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.Layout
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.ceil

internal class HealthAtlasLabeledImage(private val activity: Activity, plate: HealthAtlasPlate, description: String,
    data: HealthBodyAtlas, currentId: String?, legendInset: Int = 0,
    selected: (HealthAtlasItem) -> Unit) : FrameLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val features = plate.features.associateBy { it.marker.id }
    private val markers = (plate.markers + plate.features.map { it.marker }).sortedBy { it.y }
    private val split = plate.splitCallouts && markers.any { it.x < .5f } && markers.any { it.x >= .5f }
    private val leftRail = markers.indices.filter { split && markers[it].x < .5f }
    private val rightRail = markers.indices.filterNot { it in leftRail }
    private var featureDialog: android.app.AlertDialog? = null
    private val labelBottomInset = ui.dp(legendInset)
    var labelsShown = true
        private set
    val image = ImageView(activity).apply {
        setImageResource(plate.drawable); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = description
        tag = "atlas-art-image"
    }
    private val imageRect = RectF()
    var leaderPaths: Map<String, List<HealthAtlasLeaderPoint>> = emptyMap()
        private set
    private val labels = markers.mapIndexed { index, marker ->
        val feature = features[marker.id]
        val item = if (feature == null) data[marker.id]!! else null
        val current = item != null && item.id == currentId
        ui.text(item?.name ?: activity.getString(requireNotNull(feature).title), 13f, bold = current).apply {
            val left = index in leftRail
            gravity = Gravity.CENTER_VERTICAL or when {
                left -> Gravity.RIGHT
                split -> Gravity.LEFT
                else -> Gravity.START
            }
            minimumHeight = ui.dp(48)
            isSelected = current
            if (isSelected) setTextColor(activity.getColor(R.color.health_overview_green))
            else {
                isFocusable = true
                setOnClickListener { if (feature != null) showFeature(feature) else selected(requireNotNull(item)) }
            }
            tag = if (feature == null) "atlas-hotspot-${marker.id}" else "atlas-feature-${marker.id}"
            setPadding(if (left) 0 else ui.dp(6), ui.dp(4), if (left) ui.dp(6) else 0, ui.dp(4))
        }
    }
    private val guides = object : View(activity) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas: Canvas) {
            paint.strokeWidth = resources.displayMetrics.density
            paint.color = activity.getColor(R.color.text_primary)
            leaderPaths.values.forEach { path -> path.zipWithNext().forEach { (start, end) ->
                canvas.drawLine(start.x, start.y, end.x, end.y, paint)
            } }
            markers.forEachIndexed { index, marker ->
                val x = imageRect.left + imageRect.width() * marker.x
                val y = imageRect.top + imageRect.height() * marker.y
                val label = labels[index]
                paint.color = activity.getColor(R.color.health_overview_green)
                canvas.drawCircle(x, y, ui.dp(if (label.isSelected) 5 else 3).toFloat(), paint)
            }
        }
    }
    init { addView(image); addView(guides); labels.forEach(::addView) }
    fun showLabels(show: Boolean) {
        if (labelsShown == show) return
        labelsShown = show
        val visibility = if (show) VISIBLE else GONE
        guides.visibility = visibility
        labels.forEach { it.visibility = visibility }
        requestLayout()
    }
    fun showFeature(feature: HealthAtlasFeature) {
        featureDialog?.dismiss()
        featureDialog = android.app.AlertDialog.Builder(activity).setTitle(feature.title).setMessage(feature.explanation)
            .setPositiveButton(android.R.string.ok, null).show()
    }
    override fun onDetachedFromWindow() {
        featureDialog?.dismiss(); featureDialog = null
        super.onDetachedFromWindow()
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        if (!labelsShown) {
            val h = resolveSize(suggestedMinimumHeight, heightMeasureSpec)
            setMeasuredDimension(w, h)
            image.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
            return
        }
        val railLimit = (w * (if (split) .24f else .6f)).toInt()
        fun preferred(indices: List<Int>): Int {
            if (indices.isEmpty()) return 0
            return indices.maxOf { index ->
                val label = labels[index]
                ceil(Layout.getDesiredWidth(label.text, label.paint)).toInt() + label.paddingLeft + label.paddingRight
            }.coerceAtLeast(ui.dp(48)).coerceAtMost(railLimit)
        }
        var leftWidth = preferred(leftRail)
        var rightWidth = if (split) preferred(rightRail) else (w * .28f).toInt()
        fun measureRail(indices: List<Int>, width: Int): Int {
            indices.forEach { labels[it].measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)) }
            return indices.sumOf { labels[it].measuredHeight } + ui.dp(8) * (indices.size + 1)
        }
        fun measureLabels() = maxOf(measureRail(leftRail, leftWidth), measureRail(rightRail, rightWidth)) + labelBottomInset
        var required = measureLabels()
        // A constrained height needs a wider label column before packing large text upward.
        if (MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED) {
            val limit = MeasureSpec.getSize(heightMeasureSpec)
            while (required > limit && (rightWidth < railLimit || (split && leftWidth < railLimit))) {
                if (split) leftWidth = (leftWidth + ui.dp(8)).coerceAtMost(railLimit)
                rightWidth = (rightWidth + ui.dp(8)).coerceAtMost(railLimit)
                required = measureLabels()
            }
        }
        val h = resolveSize(required.coerceAtLeast(suggestedMinimumHeight), heightMeasureSpec)
        setMeasuredDimension(w, h)
        image.measure(MeasureSpec.makeMeasureSpec(w - leftWidth - rightWidth, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        guides.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        if (!labelsShown) {
            image.layout(0, 0, width, height)
            leaderPaths = emptyMap()
            return
        }
        val artLeft = leftRail.firstOrNull()?.let { labels[it].measuredWidth } ?: 0
        image.layout(artLeft, 0, artLeft + image.measuredWidth, height)
        guides.layout(0, 0, width, height)
        val drawable = image.drawable
        imageRect.set(0f,0f,drawable.intrinsicWidth.toFloat(),drawable.intrinsicHeight.toFloat())
        image.imageMatrix.mapRect(imageRect)
        imageRect.offset(artLeft.toFloat(), 0f)
        val gap = ui.dp(8)
        // Pack in visual order, then move overflow upward without collapsing adjacent labels.
        fun layoutRail(indices: List<Int>, left: Int, right: Int) {
            val tops = IntArray(indices.size)
            var nextTop = gap
            for ((order, index) in indices.withIndex()) {
                val y = imageRect.top + imageRect.height() * markers[index].y
                tops[order] = (y - labels[index].measuredHeight / 2f).toInt().coerceAtLeast(nextTop)
                nextTop = tops[order] + labels[index].measuredHeight + gap
            }
            var bottom = height - gap - labelBottomInset
            for (order in indices.indices.reversed()) {
                val label = labels[indices[order]]
                val top = tops[order].coerceAtMost(bottom - label.measuredHeight)
                label.layout(left, top, right, top + label.measuredHeight)
                bottom = top - gap
            }
        }
        layoutRail(leftRail, 0, artLeft)
        layoutRail(rightRail, image.right, width)
        val points = markers.map { HealthAtlasLeaderPoint(imageRect.left + imageRect.width() * it.x,
            imageRect.top + imageRect.height() * it.y) }
        leaderPaths = markers.mapIndexed { i, marker ->
            val label = labels[i]
            val left = i in leftRail
            val edge = if (left) label.right else label.left
            val mid = imageRect.centerX()
            val minX = if (split && !left) mid else Float.NEGATIVE_INFINITY
            val maxX = if (left) mid else Float.POSITIVE_INFINITY
            marker.id to HealthAtlasLeaderRoutes.route(points[i], HealthAtlasLeaderPoint(edge.toFloat(), label.top + label.height / 2f),
                points.filterIndexed { index, _ -> index != i }, ui.dp(8).toFloat(), minX, maxX)
        }.toMap()
        guides.invalidate()
    }
}
