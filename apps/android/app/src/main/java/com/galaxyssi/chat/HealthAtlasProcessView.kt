package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.Gravity
import android.view.ViewGroup
import android.widget.TextView

/** Native, focusable stages over a schematic process path, not anatomical geometry. */
internal class HealthAtlasProcessView(context: Context, private val mechanism: HealthAtlasMechanism,
    private val selected: (Int) -> Unit = {}) : ViewGroup(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private var rowHeight = 0
    private var current = -1
    private val stages = mechanism.stages.mapIndexed { index, label ->
        object : TextView(context) {
            override fun getAccessibilityClassName(): CharSequence = "android.widget.Button"
        }.apply {
            text = label; textSize = 12f; gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            setTextColor(context.getColor(R.color.text_primary))
            setPadding(dp(4), dp(40), dp(4), dp(8)); minimumHeight = dp(64)
            tag = "atlas-process-stage-$index"; isSaveEnabled = false; isFocusable = true
            contentDescription = context.getString(R.string.health_atlas_stage, index + 1, 4, label)
            val background = android.util.TypedValue()
            context.theme.resolveAttribute(android.R.attr.selectableItemBackground, background, true)
            if (background.resourceId != 0) setBackgroundResource(background.resourceId)
            setOnClickListener { phase = index / 4f; selected(index) }
        }.also { addView(it) }
    }
    var phase = 0f
        set(value) {
            field = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
            val next = minOf(3, (field * 4).toInt())
            if (next != current) {
                current = next
                stages.forEachIndexed { index, stage -> stage.isSelected = index == current }
            }
            invalidate()
        }
    init {
        isSaveEnabled = false; tag = "atlas-process"; setWillNotDraw(false)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        phase = 0f
    }
    private fun dp(value: Int) = (value * density).toInt()
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val column = ((width - dp(40)) / 2).coerceAtLeast(1)
        stages.forEach {
            it.measure(MeasureSpec.makeMeasureSpec(column, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        }
        rowHeight = stages.maxOf { it.measuredHeight }
        setMeasuredDimension(width, resolveSize(rowHeight * 2 + dp(40), heightMeasureSpec))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        stages.forEachIndexed { index, stage ->
            val left = if (index == 0 || index == 3) dp(8) else width - dp(8) - stage.measuredWidth
            val top = dp(8) + if (index < 2) 0 else rowHeight + dp(24)
            stage.layout(left, top, left + stage.measuredWidth, top + rowHeight)
        }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val accent = context.getColor(R.color.health_overview_green)
        val points = stages.map { (it.left + it.width / 2f) to (it.top + dp(16).toFloat()) }
        val path = Path().apply {
            moveTo(points[0].first, points[0].second); lineTo(points[1].first, points[1].second)
            lineTo(width - dp(4).toFloat(), points[1].second)
            lineTo(width - dp(4).toFloat(), points[2].second)
            lineTo(points[2].first, points[2].second); lineTo(points[3].first, points[3].second)
        }
        paint.strokeWidth = density * 2; paint.style = Paint.Style.STROKE
        paint.color = context.getColor(R.color.separator)
        canvas.drawPath(path, paint)
        val measure = android.graphics.PathMeasure(path, false)
        val position = FloatArray(2)
        val firstLeg = points[1].first - points[0].first
        val secondLeg = 2 * (width - dp(4) - points[1].first) + points[2].second - points[1].second
        val milestones = floatArrayOf(0f, firstLeg, firstLeg + secondLeg, measure.length, measure.length)
        val fraction = phase * 4 - current
        val distance = milestones[current] + (milestones[current + 1] - milestones[current]) * fraction
        measure.getPosTan(distance, position, null)
        paint.style = Paint.Style.FILL; paint.color = accent
        canvas.drawCircle(position[0], position[1], density * 5, paint)
        points.forEachIndexed { index, (x,y) ->
            paint.style = Paint.Style.FILL; paint.color = if (index <= current) accent else context.getColor(R.color.button_soft)
            canvas.drawCircle(x,y,density * 14,paint)
            paint.color = if (index <= current) android.graphics.Color.WHITE else context.getColor(R.color.text_primary)
            paint.textAlign = Paint.Align.CENTER; paint.textSize = density * 13
            canvas.drawText((index + 1).toString(),x,y + density * 4,paint)
        }
    }
}
