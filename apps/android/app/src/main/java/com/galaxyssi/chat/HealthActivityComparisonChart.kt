package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import java.time.LocalDate
import java.text.NumberFormat
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.ceil

internal class HealthActivityComparisonChart(
    context: Context,
    private val data: HealthActivityComparison,
    private val kind: HealthActivityKind,
    selectedDay: LocalDate?,
    private val onGestureFinished: () -> Unit,
    private val onSelection: (LocalDate?) -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val tooltipPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val area = RectF()
    private val divisor = if (kind == HealthActivityKind.CYCLING) 60_000.0 else 1.0
    private val interval = ceil((data.current.filterNotNull().maxOrNull() ?: 0L) / divisor / 3).coerceAtLeast(1.0)
    private val maximum = interval * 3 * divisor
    private val locale = resources.configuration.locales[0]
    private val numbers = NumberFormat.getIntegerInstance(locale)
    private val valueLabels = List(4) { numbers.format(interval * it) }
    private val dates = DateTimeFormatter.ofPattern(if (data.first.year == data.last.year) "M/d" else "yy/M/d", locale)
    private val dateLabels = data.current.indices.map { dates.format(data.dayAt(it)) }
    private var selectedIndex = data.current.indices.firstOrNull { data.dayAt(it) == selectedDay }
    private enum class Gesture { IDLE, PENDING, SCRUBBING, IGNORED }
    private var gesture = Gesture.IDLE
    val trackingTouch: Boolean get() = gesture != Gesture.IDLE
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f

    init {
        minimumHeight = (220 * density).toInt()
        isClickable = data.current.isNotEmpty()
        isFocusable = isClickable
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        updateDescription()
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) =
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize(minimumHeight, heightMeasureSpec))
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics)
        val metrics = paint.fontMetrics
        val dateWidth = dateLabels.maxOf(paint::measureText)
        val left = maxOf(valueLabels.maxOf(paint::measureText) + 9 * density, dateWidth / 2 + density)
        val right = width - maxOf(10 * density, dateWidth / 2 + density)
        val top = maxOf(14 * density, (metrics.descent - metrics.ascent) / 2 + density)
        val bottom = height - (metrics.descent - metrics.ascent) - 12 * density
        area.set(left, top, right, bottom)
        if (right <= left || bottom <= top) return

        paint.textAlign = Paint.Align.RIGHT
        valueLabels.forEachIndexed { tick, label ->
            val y = bottom - (bottom - top) * tick / valueLabels.lastIndex
            paint.color = context.getColor(R.color.separator); paint.strokeWidth = density
            canvas.drawLine(left, y, right, y, paint)
            paint.color = context.getColor(R.color.text_secondary)
            canvas.drawText(label, left - 8 * density, y - (metrics.ascent + metrics.descent) / 2, paint)
        }
        val maxTicks = ((right - left) / (dateWidth + 8 * density)).toInt() + 1
        val preferredTicks = if (data.current.size <= 7) 7 else 5
        paint.textAlign = Paint.Align.CENTER
        data.dateTickIndices(minOf(maxTicks, preferredTicks)).forEach { index ->
            canvas.drawText(dateLabels[index], xAt(index), bottom + 6 * density - metrics.ascent, paint)
        }

        val accent = context.getColor(R.color.health_overview_green)
        selectedIndex?.let {
            paint.color = accent
            paint.alpha = 128
            paint.strokeWidth = density
            canvas.drawLine(xAt(it), top, xAt(it), bottom, paint)
        }
        paint.color = accent
        paint.strokeWidth = 2 * density
        var previousPoint: Pair<Float, Float>? = null
        data.current.forEachIndexed { index, value ->
            if (value == null) { previousPoint = null; return@forEachIndexed }
            val x = xAt(index)
            val y = yAt(value)
            previousPoint?.let { canvas.drawLine(it.first, it.second, x, y, paint) }
            canvas.drawCircle(x, y, 2.5f * density, paint)
            previousPoint = x to y
        }
        selectedIndex?.let { index ->
            val x = xAt(index)
            val value = data.current[index]
            val y = value?.let(::yAt) ?: area.centerY()
            if (value != null) {
                val radius = 5.5f * density
                canvas.drawCircle(x, y, radius, paint)
                paint.color = context.getColor(R.color.page_bg)
                canvas.drawCircle(x, y, radius - density, paint)
                paint.color = accent
                canvas.drawCircle(x, y, 2.5f * density, paint)
            }
            drawPointValue(canvas, x, y, pointLabel(index))
        }
    }

    private fun xAt(index: Int) = if (data.current.size == 1) area.centerX()
        else area.left + area.width() * index / data.current.lastIndex
    private fun yAt(value: Long) = area.bottom - area.height() * (value / maximum).toFloat()

    private fun pointLabel(index: Int) = context.getString(R.string.health_activity_point_value, dateLabels[index],
        data.current[index]?.let { healthActivityAmount(context, kind, it) }
            ?: context.getString(R.string.health_activity_day_unrecorded))

    private fun drawPointValue(canvas: Canvas, x: Float, y: Float, label: String) {
        val gap = 9 * density
        val padX = 8 * density
        val padY = 5 * density
        tooltipPaint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12f, resources.displayMetrics)
        tooltipPaint.color = context.getColor(R.color.text_primary)
        val ideal = ceil(tooltipPaint.measureText(label))
        val roomRight = width - x - gap - 2 * density
        val roomLeft = x - area.left - gap
        val onRight = roomRight >= ideal + 2 * padX || roomRight >= roomLeft
        val available = (if (onRight) roomRight else roomLeft) - 2 * padX
        if (available < density) return
        val textWidth = minOf(ideal, available).toInt().coerceAtLeast(1)
        val text = StaticLayout.Builder.obtain(label, 0, label.length, tooltipPaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false).build()
        val boxWidth = textWidth + 2 * padX
        val boxHeight = text.height + 2 * padY
        val left = if (onRight) x + gap else x - gap - boxWidth
        val top = (y - boxHeight / 2).coerceIn(area.top, maxOf(area.top, area.bottom - boxHeight))
        paint.color = context.getColor(R.color.button_soft)
        canvas.drawRoundRect(left, top, left + boxWidth, top + boxHeight, 6 * density, 6 * density, paint)
        canvas.save()
        canvas.translate(left + padX, top + padY)
        text.draw(canvas)
        canvas.restore()
    }

    private fun updateDescription() {
        contentDescription = selectedIndex?.let(::pointLabel) ?: context.getString(R.string.health_trend_chart_data)
    }

    private fun select(index: Int?) {
        if (selectedIndex == index) return
        selectedIndex = index
        updateDescription()
        onSelection(index?.let(data::dayAt))
        invalidate()
    }

    fun clearSelection() = select(null)

    private fun onTimeline(x: Float, y: Float): Boolean {
        val edge = 10 * density
        return !area.isEmpty && x >= area.left - edge && x <= area.right + edge &&
            y >= area.top - edge && y <= height
    }

    private fun selectAt(x: Float) {
        if (!area.isEmpty) select(data.nearestDayIndex((x - area.left) / area.width()))
    }

    private fun finishGesture() {
        if (gesture == Gesture.IDLE) return
        gesture = Gesture.IDLE
        parent?.requestDisallowInterceptTouchEvent(false)
        post { if (isAttachedToWindow) onGestureFinished() }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isClickable) return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = event.x; downY = event.y; gesture = Gesture.PENDING }
            MotionEvent.ACTION_MOVE -> {
                if (gesture == Gesture.PENDING) {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (maxOf(dx, dy) > touchSlop) {
                        gesture = if (dx > dy && onTimeline(downX, downY)) Gesture.SCRUBBING else Gesture.IGNORED
                        if (gesture == Gesture.SCRUBBING) parent?.requestDisallowInterceptTouchEvent(true)
                    }
                }
                if (gesture == Gesture.SCRUBBING) selectAt(event.x)
            }
            MotionEvent.ACTION_UP -> {
                if (gesture == Gesture.SCRUBBING) selectAt(event.x)
                else if (gesture == Gesture.PENDING &&
                    maxOf(abs(event.x - downX), abs(event.y - downY)) <= touchSlop) {
                    if (onTimeline(event.x, event.y)) {
                        selectAt(event.x)
                        super.performClick()
                    } else clearSelection()
                }
                finishGesture()
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                gesture = Gesture.IGNORED
                parent?.requestDisallowInterceptTouchEvent(false)
            }
            MotionEvent.ACTION_CANCEL -> finishGesture()
        }
        return true
    }

    override fun performClick(): Boolean {
        if (!isClickable) return false
        if (selectedIndex == null) select(data.current.lastIndex)
        super.performClick()
        return true
    }

    private fun moveSelection(forward: Boolean): Boolean {
        val next = selectedIndex?.let { it + if (forward) 1 else -1 }
            ?: if (forward) 0 else data.current.lastIndex
        if (next !in data.current.indices) return false
        select(next)
        return true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT && moveSelection(true)) return true
        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT && moveSelection(false)) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        if (data.current.size <= 1) return
        if (selectedIndex != data.current.lastIndex) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD)
        if (selectedIndex != 0) info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD)
    }

    override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean = when (action) {
        AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> moveSelection(true)
        AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD -> moveSelection(false)
        else -> super.performAccessibilityAction(action, arguments)
    }
}

internal fun healthActivityAmount(context: Context, kind: HealthActivityKind, value: Long): String {
    val locale = context.resources.configuration.locales[0]
    val (number, unit) = if (kind == HealthActivityKind.STEPS)
        NumberFormat.getIntegerInstance(locale).format(value) to R.string.health_activity_steps_unit
    else NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }.format(value / 60_000.0) to
        R.string.health_activity_minutes
    return "$number ${context.getString(unit)}"
}
