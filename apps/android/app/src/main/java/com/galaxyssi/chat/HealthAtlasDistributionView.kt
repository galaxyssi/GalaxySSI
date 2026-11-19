package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

internal object HealthAtlasDistributionText {
    val names = listOf(R.string.health_atlas_distribution_central, R.string.health_atlas_distribution_peripheral,
        R.string.health_atlas_distribution_eliminated)
    val colors = listOf(R.color.health_overview_green, R.color.health_overview_orange, R.color.text_secondary)
    fun amounts(model: HealthAtlasDistribution) = model.amounts.let { listOf(it.central, it.peripheral, it.eliminated) }
    fun summary(context: Context, model: HealthAtlasDistribution) = context.getString(R.string.health_atlas_distribution_summary,
        HealthAtlasPhysiologyText.number(model.hours), *amounts(model).map { HealthAtlasPhysiologyText.number(it) }.toTypedArray())
    fun prompt(context: Context, model: HealthAtlasDistribution) = listOf(
        context.getString(R.string.health_atlas_drug_two), context.getString(R.string.health_atlas_distribution_scope),
        context.getString(R.string.health_atlas_distribution_rates, HealthAtlasPhysiologyText.number(model.k12),
            HealthAtlasPhysiologyText.number(model.k21), HealthAtlasPhysiologyText.number(model.k10)),
        summary(context, model), context.getString(R.string.health_atlas_distribution_formula),
        context.getString(R.string.health_atlas_distribution_boundary), HealthAtlasDistribution.SOURCE).joinToString("\n")
}

/** Amount nodes are not organ images. Native labels retain measured height at larger font scales. */
internal class HealthAtlasDistributionDiagram(context: Context) : ViewGroup(context) {
    private val density = resources.displayMetrics.density
    private fun dp(value: Int) = (density * value).toInt()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = density * 2; color = context.getColor(R.color.text_secondary) }
    private val numbers = arrayListOf<TextView>()
    private val nodes = HealthAtlasDistributionText.names.mapIndexed { index, title ->
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            addView(TextView(context).apply {
                text = context.getString(title); textSize = 14f; gravity = Gravity.CENTER
                setTextColor(context.getColor(R.color.text_primary)); tag = "atlas-distribution-node-title-$index"
            }, LinearLayout.LayoutParams(-1, -2))
            addView(TextView(context).apply {
                textSize = 22f; gravity = Gravity.CENTER; setTextColor(context.getColor(HealthAtlasDistributionText.colors[index]))
                tag = "atlas-distribution-node-value-$index"; numbers += this
                maxLines = 1
                setAutoSizeTextTypeUniformWithConfiguration(12, 22, 1, android.util.TypedValue.COMPLEX_UNIT_SP)
            }, LinearLayout.LayoutParams(-1, (30 * resources.displayMetrics.scaledDensity).toInt() + dp(8)))
            tag = "atlas-distribution-node-$index"
        }
    }
    var model = HealthAtlasDistribution()
        set(value) {
            field = value
            HealthAtlasDistributionText.amounts(value).forEachIndexed { i, amount ->
                numbers[i].text = context.getString(R.string.health_atlas_distribution_percent, HealthAtlasPhysiologyText.number(amount))
            }
            contentDescription = HealthAtlasDistributionText.summary(context, value)
            invalidate()
        }
    init { isSaveEnabled = false; setWillNotDraw(false); tag = "atlas-distribution-diagram"; nodes.forEach(::addView); model = model }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val nodeWidth = ((width - dp(44)) / 2).coerceAtLeast(1)
        nodes.forEach { it.measure(MeasureSpec.makeMeasureSpec(nodeWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)) }
        setMeasuredDimension(width, resolveSize(maxOf(nodes[0].measuredHeight, nodes[1].measuredHeight) + dp(52) + nodes[2].measuredHeight, heightMeasureSpec))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val firstHeight = maxOf(nodes[0].measuredHeight, nodes[1].measuredHeight)
        nodes.forEachIndexed { i, node ->
            val left = if (i == 1) width - node.measuredWidth else 0
            val top = if (i == 2) firstHeight + dp(52) else (firstHeight - node.measuredHeight) / 2
            node.layout(left, top, left + node.measuredWidth, top + node.measuredHeight)
        }
    }
    override fun onDraw(canvas: Canvas) {
        fun arrow(x1: Float, y1: Float, x2: Float, y2: Float) {
            canvas.drawLine(x1, y1, x2, y2, paint)
            val length = kotlin.math.hypot(x2 - x1, y2 - y1).coerceAtLeast(1f)
            val dx = (x2 - x1) / length; val dy = (y2 - y1) / length
            canvas.drawPath(Path().apply {
                moveTo(x2, y2); lineTo(x2 - dx * dp(7) + dy * dp(4), y2 - dy * dp(7) - dx * dp(4))
                lineTo(x2 - dx * dp(7) - dy * dp(4), y2 - dy * dp(7) + dx * dp(4)); close()
            }, paint)
        }
        val left = nodes[0].right + dp(4).toFloat(); val right = nodes[1].left - dp(4).toFloat()
        val middle = (nodes[0].top + nodes[0].bottom) / 2f
        arrow(left, middle - dp(7), right, middle - dp(7)); arrow(right, middle + dp(7), left, middle + dp(7))
        val x = nodes[0].width / 2f
        arrow(x, nodes[0].bottom + dp(8).toFloat(), x, nodes[2].top - dp(8).toFloat())
    }
}

internal class HealthAtlasDistributionChart(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val textSize = 12f * resources.displayMetrics.scaledDensity
    private var samples = emptyList<HealthAtlasDistributionAmounts>()
    var model = HealthAtlasDistribution()
        set(value) {
            val ratesChanged = field.copy(quarterHours = value.quarterHours) != value
            field = value
            if (samples.isEmpty() || ratesChanged) samples = (0..384).map { value.at(it / 8.0) }
            contentDescription = context.getString(R.string.health_atlas_distribution_chart, HealthAtlasDistributionText.summary(context, value))
            invalidate()
        }
    init { tag = "atlas-distribution-chart"; isSaveEnabled = false; model = model }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((180 * density + 3 * textSize).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        paint.textSize = textSize; paint.pathEffect = null; paint.style = Paint.Style.FILL
        val left = paint.measureText("100%") + 12 * density
        val right = width - paint.measureText("48") / 2 - 4 * density
        val top = textSize; val bottom = height - textSize * 2
        if (right <= left || bottom <= top) return
        fun x(hours: Double) = left + ((right - left) * hours / 48).toFloat()
        fun y(amount: Double) = bottom - ((bottom - top) * amount / 100).toFloat()
        for (amount in listOf(0, 50, 100)) {
            paint.strokeWidth = density; paint.color = context.getColor(R.color.separator)
            canvas.drawLine(left, y(amount.toDouble()), right, y(amount.toDouble()), paint)
            paint.color = context.getColor(R.color.text_secondary); paint.textAlign = Paint.Align.RIGHT
            canvas.drawText("$amount%", left - 6 * density, y(amount.toDouble()) + textSize * .3f, paint)
        }
        paint.textAlign = Paint.Align.CENTER
        for (hours in listOf(0, 24, 48)) canvas.drawText(hours.toString(), x(hours.toDouble()), bottom + textSize * 1.4f, paint)
        paint.color = context.getColor(R.color.separator); canvas.drawLine(x(model.hours), top, x(model.hours), bottom, paint)
        val selected = model.amounts
        val series = listOf<(HealthAtlasDistributionAmounts) -> Double>({ it.central }, { it.peripheral }, { it.eliminated })
        series.forEachIndexed { i, value ->
            paint.color = context.getColor(HealthAtlasDistributionText.colors[i]); paint.style = Paint.Style.STROKE; paint.strokeWidth = 2.5f * density
            paint.pathEffect = when (i) {
                1 -> DashPathEffect(floatArrayOf(7 * density, 4 * density), 0f)
                2 -> DashPathEffect(floatArrayOf(2 * density, 4 * density), 0f)
                else -> null
            }
            val path = Path().apply { samples.forEachIndexed { step, amounts ->
                if (step == 0) moveTo(x(0.0), y(value(amounts))) else lineTo(x(step / 8.0), y(value(amounts)))
            } }
            canvas.drawPath(path, paint); paint.pathEffect = null; paint.style = Paint.Style.FILL
            canvas.drawCircle(x(model.hours), y(value(selected)), 4 * density, paint)
        }
    }
}
