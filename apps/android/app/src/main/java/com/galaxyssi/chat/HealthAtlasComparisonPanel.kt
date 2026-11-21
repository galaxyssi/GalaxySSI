package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.LinearLayout
import android.widget.SeekBar

internal object HealthAtlasComparisonText {
    const val VALIDATION_SOURCE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6977398/"
    val labels = listOf(R.string.health_atlas_compare_control, R.string.health_atlas_compare_exchange,
        R.string.health_atlas_compare_faster)

    private fun number(value: Double) = HealthAtlasPhysiologyText.number(value)
    fun time(context: Context, model: HealthAtlasModelComparison) =
        context.getString(R.string.health_atlas_distribution_time, number(model.hours))
    fun rates(context: Context, model: HealthAtlasModelComparison) = model.scenario.distribution.let {
        context.getString(R.string.health_atlas_distribution_rates, number(it.k12), number(it.k21), number(it.k10))
    }
    fun summary(context: Context, point: HealthAtlasComparisonPoint) = context.getString(
        R.string.health_atlas_compare_summary, number(point.one), number(point.two.central), number(point.centralGap))
    fun range(context: Context, point: HealthAtlasComparisonPoint) =
        context.getString(R.string.health_atlas_compare_range, number(point.low), number(point.high))
    fun prompt(context: Context, model: HealthAtlasModelComparison) = model.point.let { point ->
        listOf(context.getString(R.string.health_atlas_compare_title), context.getString(R.string.health_atlas_compare_scope),
            context.getString(labels[model.scenario.ordinal]), rates(context, model), time(context, model),
            summary(context, point), range(context, point), context.getString(R.string.health_atlas_compare_limit),
            HealthAtlasDistribution.SOURCE, VALIDATION_SOURCE).joinToString("\n")
    }
}

internal class HealthAtlasComparisonPanel(
    activity: Activity, body: LinearLayout, initial: HealthAtlasModelComparison,
    changed: (HealthAtlasModelComparison) -> Unit, source: (String) -> Unit,
) {
    init {
        val ui = HealthCenterViews(activity)
        var model = initial
        val choice = ui.column()
        val rates = ui.text("", 13f, muted = true).apply { tag = "atlas-comparison-rates" }
        val time = ui.text("", 14f).apply { tag = "atlas-comparison-time" }
        val result = ui.text("", 15f, bold = true).apply { tag = "atlas-comparison-result" }
        val range = ui.text("", 13f).apply { tag = "atlas-comparison-range" }
        val chart = HealthAtlasComparisonChart(activity, initial)
        val seek = SeekBar(activity).apply { tag = "atlas-comparison-elapsed"; max = 192; progress = initial.quarterHours }
        fun update() {
            val point = model.point
            rates.text = HealthAtlasComparisonText.rates(activity, model)
            time.text = HealthAtlasComparisonText.time(activity, model)
            seek.contentDescription = time.text
            result.text = HealthAtlasComparisonText.summary(activity, point)
            range.text = HealthAtlasComparisonText.range(activity, point)
            chart.model = model
            changed(model)
        }
        fun scenarios() {
            choice.removeAllViews()
            choice.addView(HealthAtlasUi.tabs(activity, HealthAtlasComparisonText.labels, model.scenario.ordinal,
                "atlas-comparison-case") {
                model = model.copy(scenario = HealthAtlasComparisonScenario.entries[it]); scenarios(); update()
                choice.findViewWithTag<View>("atlas-comparison-case-$it")?.requestFocus(View.FOCUS_FORWARD)
            })
        }
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_compare_scope), 13f, muted = true), 12)
        ui.add(body, choice, 8)
        ui.add(body, rates, 8)
        ui.add(body, chart, 8)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_compare_legend), 12f, muted = true), 4)
        val timeRow = ui.line()
        timeRow.addView(time, LinearLayout.LayoutParams(0, -2, 1f))
        timeRow.addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
            model = HealthAtlasModelComparison(); seek.progress = model.quarterHours; scenarios(); update()
        }.apply { tag = "atlas-comparison-reset" })
        ui.add(body, timeRow, 8)
        ui.add(body, seek)
        ui.add(body, result, 8)
        ui.add(body, range, 6)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_compare_evidence), 16f, bold = true), 20)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_compare_limit), 13f, muted = true)
            .apply { tag = "atlas-comparison-evidence" }, 6)
        ui.add(body, ui.row(activity.getString(R.string.health_atlas_distribution_reference)) {
            source(HealthAtlasDistribution.SOURCE)
        }.apply { tag = "atlas-source-comparison-equations" }, 8)
        ui.add(body, ui.row(activity.getString(R.string.health_atlas_compare_reference)) {
            source(HealthAtlasComparisonText.VALIDATION_SOURCE)
        }.apply { tag = "atlas-source-comparison-validation" }, 8)
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(bar: SeekBar?) = Unit
            override fun onStopTrackingTouch(bar: SeekBar?) = Unit
            override fun onProgressChanged(bar: SeekBar?, value: Int, user: Boolean) {
                model = model.copy(quarterHours = value); update()
            }
        })
        scenarios()
        update()
    }
}

internal class HealthAtlasComparisonChart(context: Context, initial: HealthAtlasModelComparison) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private val font = 12f * resources.displayMetrics.scaledDensity
    private var samples = emptyList<HealthAtlasComparisonPoint>()
    var model = initial
        set(value) {
            if (samples.isEmpty() || field.scenario != value.scenario) samples = (0..192).map { value.at(it / 4.0) }
            field = value
            invalidate()
        }
    init {
        tag = "atlas-comparison-chart"; isSaveEnabled = false
        // The exact readings and legend are adjacent accessible text.
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        model = initial
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((144 * density + 3 * font).toInt(), heightMeasureSpec))
    }
    override fun onDraw(canvas: Canvas) {
        paint.textSize = font; paint.style = Paint.Style.FILL
        val left = paint.measureText("100%") + 12 * density
        val right = width - paint.measureText("48") / 2 - 4 * density
        val top = font; val bottom = height - font * 2
        if (right <= left || bottom <= top) return
        fun x(hours: Double) = left + ((right - left) * hours / 48.0).toFloat()
        fun y(amount: Double) = bottom - ((bottom - top) * amount / 100.0).toFloat()
        val green = context.getColor(R.color.health_overview_green)
        val orange = context.getColor(R.color.health_overview_orange)
        val guide = context.getColor(R.color.separator)
        val neutral = context.getColor(R.color.text_secondary)
        val area = Path().apply {
            samples.forEachIndexed { i, point ->
                if (i == 0) moveTo(left, y(point.high)) else lineTo(x(i / 4.0), y(point.high))
            }
            for (i in samples.indices.reversed()) lineTo(x(i / 4.0), y(samples[i].low))
            close()
        }
        paint.color = green; paint.alpha = 42; canvas.drawPath(area, paint); paint.alpha = 255
        paint.strokeWidth = density
        for (tick in listOf(0, 50, 100)) {
            val yy = y(tick.toDouble())
            paint.color = guide; canvas.drawLine(left, yy, right, yy, paint)
            paint.color = neutral; paint.textAlign = Paint.Align.RIGHT
            canvas.drawText("$tick%", left - 6 * density, yy + font * .3f, paint)
        }
        paint.textAlign = Paint.Align.CENTER
        for (tick in listOf(0, 24, 48)) canvas.drawText(tick.toString(), x(tick.toDouble()), bottom + font * 1.4f, paint)
        val marker = x(model.hours)
        val selected = model.point
        paint.color = neutral; canvas.drawLine(marker, top, marker, bottom, paint)
        fun series(color: Int, dashed: Boolean, value: (HealthAtlasComparisonPoint) -> Double) {
            val path = Path().apply {
                samples.forEachIndexed { i, point ->
                    if (i == 0) moveTo(left, y(value(point))) else lineTo(x(i / 4.0), y(value(point)))
                }
            }
            paint.color = color; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2.5f * density
            paint.pathEffect = if (dashed) DashPathEffect(floatArrayOf(6 * density, 4 * density), 0f) else null
            canvas.drawPath(path, paint)
            paint.pathEffect = null; paint.style = Paint.Style.FILL
            canvas.drawCircle(marker, y(value(selected)), 3.5f * density, paint)
        }
        series(orange, false) { it.two.central }
        series(green, true) { it.one }
    }
}
