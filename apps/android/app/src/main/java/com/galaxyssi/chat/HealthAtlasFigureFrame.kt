package com.galaxyssi.chat

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthAtlasFigureFrame(activity: Activity, private val art: View, key: String,
    private val header: View? = null, captionKey: String = "atlas-figure-legend",
    private val subject: ImageView? = null, private val subjectPoint: PointF? = null,
    private val activeNode: (() -> View?)? = null,
    private val overlayNote: Boolean = false,
    private val preferSideNote: Boolean = false) : FrameLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val edge = ui.dp(12)
    private val gutter = ui.dp(16)
    private val captions = HealthAtlasCaptionSizes()
    private val leader = Path()
    private val leaderInk = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = activity.getColor(R.color.health_overview_green)
        strokeWidth = ui.dp(1).toFloat()
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val subjectPosition = floatArrayOf(0f, 0f)
    private var sideNote = false
    private val overlap get() = if (overlayNote && !sideNote) minOf(ui.dp(46), legend.measuredHeight / 2) else 0
    var annotationTarget: PointF? = null
        private set
    val legend: LinearLayout = ui.column().apply {
        tag = captionKey
        setPadding(ui.dp(12), ui.dp(8), ui.dp(12), ui.dp(9))
        background = ui.background(activity.getColor(R.color.surface_bg),
            stroke = activity.getColor(R.color.health_overview_green))
    }

    init {
        tag = key
        background = ui.background(activity.getColor(R.color.health_atlas_film_ground))
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
        fun exact(size: Int) = MeasureSpec.makeMeasureSpec(size.coerceAtLeast(0), MeasureSpec.EXACTLY)
        val natural = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        val fixedHeight = MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.EXACTLY
        header?.measure(exact(width), natural)
        val headerHeight = header?.measuredHeight ?: 0
        sideNote = width >= ui.dp(580) || preferSideNote && width >= ui.dp(280)
        val noteWidth = if (sideNote) minOf((width * .40f).toInt(), ui.dp(328))
            else minOf((width * (if (overlayNote) .72f else .83f)).toInt(), width - edge * 2).coerceAtLeast(1)
        captions.measure(noteWidth)
        legend.measure(exact(noteWidth), natural)
        // For short fullscreen windows put the note beside the figure, leaving the drawing scrollable.
        if (fixedHeight && !sideNote &&
            MeasureSpec.getSize(heightMeasureSpec) - headerHeight - legend.measuredHeight < ui.dp(160)) {
            sideNote = true
            val widthBeside = minOf((width * .44f).toInt(), ui.dp(328))
            captions.measure(widthBeside)
            legend.measure(exact(widthBeside), natural)
        }
        val reserved = if (sideNote) edge * 2 else edge * 2 + legend.measuredHeight + gutter - overlap
        val available = (MeasureSpec.getSize(heightMeasureSpec) - headerHeight - reserved).coerceAtLeast(0)
        val artHeight = if (fixedHeight)
            exact(available) else natural
        val artWidth = if (sideNote) width - (legend.measuredWidth + edge * 2 + gutter) else width - edge * 2
        art.measure(exact(artWidth), artHeight)
        val body = if (sideNote) maxOf(legend.measuredHeight, art.measuredHeight) + edge * 2
            else reserved + art.measuredHeight
        setMeasuredDimension(width, resolveSize(headerHeight + body, heightMeasureSpec))
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val inset = (header?.measuredHeight ?: 0) + edge
        header?.layout(0, 0, width, inset - edge)
        if (sideNote) {
            val centerY = (inset + height - edge) / 2
            place(legend, edge, maxOf(inset, centerY - legend.measuredHeight / 2))
            place(art, legend.right + gutter, maxOf(inset, centerY - art.measuredHeight / 2))
        } else {
            place(legend, edge, inset)
            place(art, edge, legend.bottom + gutter - overlap)
        }
    }

    private fun place(view: View, left: Int, top: Int) {
        view.layout(left, top, left + view.measuredWidth, top + view.measuredHeight)
    }

    override fun drawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean {
        if (child === legend) drawLeader(canvas)
        return super.drawChild(canvas, child, drawingTime)
    }

    private fun drawLeader(canvas: Canvas) {
        if (art.width <= 0 || art.height <= 0) return
        val target = activeNode?.invoke()?.takeIf { it.width > 0 }?.let { node ->
            mapPoint(node, node.width / 2f, 0f)
        } ?: subject?.takeIf { it.width > 0 }?.let(::mapSubject)
            ?: PointF(art.left + art.width * (if (sideNote) .20f else .70f),
                if (sideNote) art.top + art.height * .42f else maxOf(legend.bottom + gutter.toFloat(), art.top + art.height * .08f))
        target.x = target.x.coerceIn(art.left.toFloat(), art.right.toFloat())
        target.y = target.y.coerceIn(art.top.toFloat(), art.bottom.toFloat())
        annotationTarget = target
        leader.reset()
        if (sideNote) {
            val stem = legend.right + gutter / 2f
            leader.moveTo(legend.right.toFloat(), legend.top + legend.height / 2f)
            leader.lineTo(stem, legend.top + legend.height / 2f)
            leader.lineTo(stem, target.y)
        } else {
            val x = legend.left + legend.width * .78f
            val stem = legend.bottom + gutter / 2f
            leader.moveTo(x, legend.bottom.toFloat())
            leader.lineTo(x, stem)
            leader.lineTo(target.x, stem)
        }
        leader.lineTo(target.x, target.y)
        leaderInk.style = Paint.Style.STROKE
        canvas.drawPath(leader, leaderInk)
        leaderInk.style = Paint.Style.FILL
        canvas.drawCircle(target.x, target.y, ui.dp(3).toFloat(), leaderInk)
    }

    private fun mapSubject(image: ImageView): PointF? {
        val drawable = image.drawable ?: return null
        subjectPosition[0] = drawable.intrinsicWidth * (subjectPoint?.x ?: if (sideNote) .36f else .54f)
        subjectPosition[1] = drawable.intrinsicHeight * (subjectPoint?.y ?: if (sideNote) .48f else .22f)
        image.imageMatrix.mapPoints(subjectPosition)
        return mapPoint(image, subjectPosition[0] + image.paddingLeft, subjectPosition[1] + image.paddingTop)
    }

    private fun mapPoint(view: View, x: Float, y: Float): PointF? {
        subjectPosition[0] = x
        subjectPosition[1] = y
        var child = view
        while (child !== this) {
            val parent = child.parent as? View ?: return null
            child.matrix.mapPoints(subjectPosition)
            subjectPosition[0] += child.left - parent.scrollX
            subjectPosition[1] += child.top - parent.scrollY
            child = parent
        }
        return PointF(subjectPosition[0], subjectPosition[1])
    }
}
