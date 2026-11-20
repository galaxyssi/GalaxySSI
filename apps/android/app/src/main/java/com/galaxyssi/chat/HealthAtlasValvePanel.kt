package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

internal object HealthAtlasValveText {
    private val phases = listOf(R.string.health_atlas_valves_filling, R.string.health_atlas_valves_contraction,
        R.string.health_atlas_valves_ejection, R.string.health_atlas_valves_relaxation)

    fun phase(context: Context, stage: Int) = context.getString(phases[stage])
    fun state(context: Context, valve: HealthAtlasValve, stage: Int) =
        context.getString(if (valve.openAt(stage)) R.string.health_atlas_valve_open else R.string.health_atlas_valve_closed)
    fun label(context: Context, atlas: HealthBodyAtlas, valve: HealthAtlasValve, stage: Int) =
        context.getString(R.string.health_atlas_valve_state, atlas[valve.id]!!.name, state(context, valve, stage))

    fun publicContext(context: Context, atlas: HealthBodyAtlas, id: String, stage: Int) = buildString {
        appendLine(context.getString(R.string.health_atlas_valves_scope))
        appendLine(phase(context, stage))
        HealthAtlasValve.entries.filter { id == "heart-valves" || it.id == id }
            .forEach { appendLine(label(context, atlas, it, stage)) }
        append(HealthAtlasHeartSection.CYCLE_SOURCE)
    }
}

internal class HealthAtlasValvePanel(private val activity: Activity, private val atlas: HealthBodyAtlas, item: HealthAtlasItem,
    select: (HealthAtlasItem) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val phase = ui.text("", 17f, bold = true).apply { tag = "atlas-valve-phase" }
    private val diagram = Diagram(activity, item.id)
    private val labels: List<TextView>
    var stage: Int = 0
        set(value) {
            if (field != value) { field = value; update() }
        }

    init {
        orientation = VERTICAL
        addView(phase)
        addView(diagram, LayoutParams(-1, -2))
        labels = HealthAtlasValve.entries.map { valve ->
            val target = atlas[valve.id]!!
            ui.text("", 15f, bold = item.id == valve.id).apply {
                minimumHeight = ui.dp(48)
                gravity = android.view.Gravity.CENTER_VERTICAL
                tag = "atlas-valve-state-${valve.id}"
                if (item.id != valve.id) { isFocusable = true; setOnClickListener { select(target) } }
                addView(this, LayoutParams(-1, -2))
            }
        }
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_valves_scope), 12f, muted = true), 8)
        update()
    }

    private fun update() {
        phase.text = HealthAtlasValveText.phase(activity, stage)
        diagram.stage = stage
        for ((index, valve) in HealthAtlasValve.entries.withIndex()) {
            val label = HealthAtlasValveText.label(activity, atlas, valve, stage)
            if (label != labels[index].text) labels[index].text = label
        }
    }

    internal class Diagram(context: Context, private val selected: String) : View(context) {
        private val heart = context.getDrawable(R.drawable.health_atlas_heart_section)!!.mutate()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val open = context.getColor(R.color.health_overview_green)
        private val closed = context.getColor(R.color.text_primary)
        private val surface = context.getColor(R.color.surface_bg)
        var stage = 0
            set(value) { if (field != value) { field = value; invalidate() } }

        init {
            tag = "atlas-valve-diagram"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val w = MeasureSpec.getSize(widthMeasureSpec)
            setMeasuredDimension(w, resolveSize((w * .82f).toInt().coerceAtMost(
                (300 * resources.displayMetrics.density).toInt()), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            val scale = minOf(width / 480f, height / 460f)
            val left = (width - 480 * scale) / 2
            val top = (height - 460 * scale) / 2
            canvas.save()
            canvas.translate(left, top)
            canvas.scale(scale, scale)
            heart.setBounds(0, 0, 480, 460)
            heart.draw(canvas)
            for (valve in HealthAtlasValve.entries) {
                val active = valve.openAt(stage)
                paint.style = Paint.Style.FILL
                paint.color = surface
                canvas.drawCircle(valve.x, valve.y, if (selected == valve.id) 17f else 13f, paint)
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = if (selected == valve.id) 4f else 2.6f
                paint.color = if (active) open else closed
                canvas.drawCircle(valve.x, valve.y, 9f, paint)
                if (!active) canvas.drawLine(valve.x - 5, valve.y, valve.x + 5, valve.y, paint)
            }
            canvas.restore()
        }
    }
}
