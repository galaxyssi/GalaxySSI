package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import java.math.BigDecimal
import java.math.MathContext
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.hypot

internal class HealthTrendChart(context: Context, private val selected: (HealthTrendPoint) -> Unit) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private val area = RectF()
    private var summary: HealthTrendSummary? = null
    private var unavailable: String? = null
    private data class Anchor(val point: HealthTrendPoint, val x: Float, val y: Float)
    private val anchors = arrayListOf<Anchor>()
    private var focus = -1; private var downX = 0f; private var downY = 0f
    private var minimum = 0.0; private var maximum = 1.0
    init { isFocusable = true; isClickable = true; isSaveEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES }
    fun bind(value: HealthTrendSummary?) {
        summary = value; focus = -1; unavailable = null; isEnabled = value != null; isClickable = value?.points?.isNotEmpty() == true
        contentDescription = if (value == null) context.getString(R.string.health_loading)
            else context.getString(R.string.health_trend_chart_description, value.eligible, value.numericDays)
        rebuild(); invalidate()
    }
    fun unavailable(message: String) { summary = null; anchors.clear(); unavailable = message; isEnabled = false; contentDescription = message; invalidate() }
    fun clear() { summary = null; unavailable = null; anchors.clear(); isEnabled = false; contentDescription = ""; invalidate() }
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) { super.onSizeChanged(w, h, oldw, oldh); rebuild() }
    private fun rebuild() {
        anchors.clear(); area.set(58 * density, 20 * density, (width - 14 * density).coerceAtLeast(60 * density), (height - 40 * density).coerceAtLeast(24 * density))
        val model = summary ?: return
        val values = model.points.map { it.value.toDouble() }
        if (values.isEmpty()) return
        val low = values.min(); val high = values.max(); val padding = if (low == high) maxOf(abs(low) * .05, 1.0) else (high - low) * .1
        minimum = maxOf(0.0, low - padding); maximum = high + padding
        val buckets = ((model.spec.days + model.spec.bucketDays - 1) / model.spec.bucketDays).toInt()
        model.points.forEach { point ->
            val x = if (buckets == 1) area.centerX() else area.left + area.width() * point.bucket / (buckets - 1)
            val y = area.bottom - area.height() * ((point.value.toDouble() - minimum) / (maximum - minimum)).toFloat()
            anchors += Anchor(point, x, y)
        }
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val model = summary
        paint.style = Paint.Style.FILL; paint.color = context.getColor(R.color.text_secondary); paint.textSize = 12 * resources.displayMetrics.scaledDensity
        if (model == null || anchors.isEmpty()) {
            paint.textAlign = Paint.Align.CENTER
            canvas.drawText(unavailable?.let { context.getString(R.string.health_trend_unavailable) }
                ?: context.getString(if (model == null) R.string.health_loading else R.string.health_trend_empty), width / 2f, height / 2f, paint)
            return
        }
        repeat(3) { index ->
            val y = area.bottom - area.height() * index / 2
            paint.color = context.getColor(R.color.separator); paint.strokeWidth = density
            canvas.drawLine(area.left, y, area.right, y, paint)
            paint.color = context.getColor(R.color.text_secondary); paint.textAlign = Paint.Align.RIGHT
            canvas.drawText(label(minimum + (maximum - minimum) * index / 2), area.left - 6 * density, y + 4 * density, paint)
        }
        val formatter = DateTimeFormatter.ofPattern(if (model.spec.days > 365) "uuuu-MM" else "MM-dd")
        listOf(model.spec.first, model.spec.first.plusDays((model.spec.days - 1) / 2), model.spec.last).forEachIndexed { index, date ->
            paint.textAlign = when (index) { 0 -> Paint.Align.LEFT; 2 -> Paint.Align.RIGHT; else -> Paint.Align.CENTER }
            canvas.drawText(date.format(formatter), area.left + area.width() * index / 2, area.bottom + 24 * density, paint)
        }
        model.spec.metric.requiredFields.forEachIndexed { index, field ->
            val points = anchors.filter { it.point.field == field }
            path.reset()
            points.forEach { anchor -> if (anchor.point.gapBefore) path.moveTo(anchor.x, anchor.y) else path.lineTo(anchor.x, anchor.y) }
            paint.color = if (index == 0) GREEN else BLUE; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2 * density
            canvas.drawPath(path, paint); paint.style = Paint.Style.FILL
            points.forEach { canvas.drawCircle(it.x, it.y, 3 * density, paint) }
        }
        anchors.getOrNull(focus)?.let { paint.style = Paint.Style.STROKE; paint.color = Color.BLACK; paint.strokeWidth = density; canvas.drawCircle(it.x, it.y, 7 * density, paint) }
    }
    private fun label(value: Double): String {
        val number = BigDecimal.valueOf(value).round(MathContext(4)).stripTrailingZeros()
        return if (value != 0.0 && (abs(value) >= 1_000_000 || abs(value) < .01)) number.toEngineeringString() else number.toPlainString()
    }
    internal fun hit(x: Float, y: Float): HealthTrendPoint? = anchors.asReversed().minByOrNull { hypot(it.x - x, it.y - y) }?.takeIf { hypot(it.x - x, it.y - y) <= 30 * density }?.point
    override fun onTouchEvent(event: MotionEvent): Boolean = when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> { downX = event.x; downY = event.y; true }
        MotionEvent.ACTION_MOVE -> abs(event.y - downY) < android.view.ViewConfiguration.get(context).scaledTouchSlop
        MotionEvent.ACTION_UP -> {
            if (hypot(event.x - downX, event.y - downY) <= android.view.ViewConfiguration.get(context).scaledTouchSlop) hit(event.x, event.y)?.let { point ->
                focus = anchors.indexOfFirst { it.point == point }; performClick(); selected(point); invalidate()
            }; true
        }
        MotionEvent.ACTION_CANCEL -> true
        else -> super.onTouchEvent(event)
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (anchors.isEmpty()) return super.onKeyDown(keyCode, event)
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_LEFT -> {
                focus = (focus + if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) 1 else -1).coerceIn(0, anchors.lastIndex)
                val point = anchors[focus].point
                contentDescription = context.getString(R.string.health_trend_point, context.getString(healthFieldResource(point.field)), point.value.toPlainString(), summary!!.spec.unit, point.count)
                announceForAccessibility(contentDescription); invalidate(); return true
            }
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_CENTER -> { anchors.getOrNull(focus)?.let { selected(it.point) }; return true }
        }
        return super.onKeyDown(keyCode, event)
    }
    companion object { const val GREEN = 0xff169d70.toInt(); const val BLUE = 0xff4b86b6.toInt() }
}
