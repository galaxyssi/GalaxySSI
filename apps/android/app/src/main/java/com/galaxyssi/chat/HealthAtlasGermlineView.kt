package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout

internal class HealthAtlasGermlineView(activity: Activity, private val id: String) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val target = ui.text("", 14f, bold = true).apply { tag = "atlas-germline-target" }
    private val numbers = ui.text("", 18f, bold = true).apply { tag = "atlas-germline-numbers" }
    private val diagram = ChromosomeDiagram(activity)
    val counts get() = requireNotNull(HealthAtlasGermline.counts(id, stage))
    var stage = -1
        set(value) {
            require(value in 0..3)
            if (field == value) return
            field = value
            target.text = context.getString(HealthAtlasGermlineText.target(counts.target))
            numbers.text = HealthAtlasGermlineText.numbers(context, counts)
            diagram.counts = counts
        }
    init {
        require(id in HealthAtlasGermline.supported)
        orientation = VERTICAL; isSaveEnabled = false; tag = "atlas-germline"
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_germline_title), 16f, bold = true))
        ui.add(this, target, 8); ui.add(this, numbers, 4); ui.add(this, diagram, 4)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_germline_symbols), 12f, muted = true), 4)
        stage = 0
    }
    private class ChromosomeDiagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val density = resources.displayMetrics.density
        var counts = HealthAtlasGermline.Counts(2, 2, HealthAtlasGermline.Target.LINEAGE_CELL)
            set(value) { field = value; contentDescription = HealthAtlasGermlineText.numbers(context, value); invalidate() }
        init { tag = "atlas-germline-diagram"; isSaveEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((150 * density).toInt(), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val radius = minOf(width * .44f, height * .43f)
            val cx = width / 2f; val cy = height / 2f
            paint.color = context.getColor(R.color.text_secondary); paint.strokeWidth = 2 * density; paint.style = Paint.Style.STROKE
            canvas.drawCircle(cx, cy, radius, paint)
            paint.color = context.getColor(R.color.health_overview_green); paint.strokeWidth = 4 * density; paint.strokeCap = Paint.Cap.ROUND
            val symbols = counts.sets * 2
            for (i in 0 until symbols) {
                val x = cx + (i - (symbols - 1) / 2f) * radius * .42f
                val half = radius * .28f
                if (counts.duplicated) {
                    canvas.drawLine(x - half * .35f, cy - half, x + half * .35f, cy + half, paint)
                    canvas.drawLine(x + half * .35f, cy - half, x - half * .35f, cy + half, paint)
                } else canvas.drawLine(x, cy - half, x, cy + half, paint)
            }
            paint.strokeCap = Paint.Cap.BUTT
        }
    }
}

internal object HealthAtlasGermlineText {
    fun target(value: HealthAtlasGermline.Target): Int = when (value) {
        HealthAtlasGermline.Target.LINEAGE_CELL -> R.string.health_atlas_germline_cell
        HealthAtlasGermline.Target.PATERNAL_GENOME -> R.string.health_atlas_germline_paternal
        HealthAtlasGermline.Target.MATERNAL_GENOME -> R.string.health_atlas_germline_maternal
        HealthAtlasGermline.Target.COMBINED_GENOMES -> R.string.health_atlas_germline_combined
    }
    fun numbers(context: Context, counts: HealthAtlasGermline.Counts): String = context.getString(
        R.string.health_atlas_germline_counts, counts.chromosomes, counts.dnaMolecules,
        if (counts.sets == 1) "n" else "2n", "${counts.dnaContent}C")
    fun context(context: Context, id: String, stage: Int): String? = HealthAtlasGermline.counts(id, stage)?.let { counts ->
        listOf(context.getString(R.string.health_atlas_germline_title), context.getString(target(counts.target)),
            numbers(context, counts), context.getString(R.string.health_atlas_germline_scope), HealthAtlasGermline.SOURCE).joinToString("\n")
    }
}
