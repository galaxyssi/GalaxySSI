package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.LinearLayout

internal class HealthAtlasVesselFlowView(activity: Activity) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val diagram = ProfileDiagram(activity)
    private val geometry = ui.text("", 14f).apply { tag = "atlas-vessel-geometry" }
    private val values = (0..2).map { ui.text("", 14f).apply { tag = "atlas-vessel-value-$it" } }
    var flow = HealthAtlasVesselFlow()
        set(value) {
            field = value; diagram.flow = value
            geometry.text = HealthAtlasVesselFlowText.geometry(context, value)
            values.forEachIndexed { index, caption -> caption.text = HealthAtlasVesselFlowText.values(context, value)[index] }
        }
    init {
        orientation = VERTICAL; tag = "atlas-vessel-flow"; isSaveEnabled = false
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_vessel_diagram), 16f, bold = true))
        ui.add(this, geometry, 4); ui.add(this, diagram)
        values.forEach { ui.add(this, it, 4) }
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_vessel_diagram_scope), 12f, muted = true), 8)
        flow = flow
    }

    /** A longitudinal section of a circular tube; arrow lengths show the normalized radial speed profile. */
    private class ProfileDiagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val density = resources.displayMetrics.density
        var flow = HealthAtlasVesselFlow()
            set(value) {
                field = value; contentDescription = HealthAtlasVesselFlowText.context(context, value); invalidate()
            }
        init { tag = "atlas-vessel-profile"; isSaveEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((160 * density).toInt(), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = 12 * density; val usable = width - 24 * density
            if (usable <= 0) return
            val right = left + usable * (flow.lengthMm / 100).toFloat()
            val half = 60 * density * (flow.radiusMm / .2).toFloat(); val middle = height / 2f
            paint.color = context.getColor(R.color.separator); paint.style = Paint.Style.FILL
            canvas.drawRect(left, middle - half, right, middle + half, paint)
            paint.color = context.getColor(R.color.text_secondary); paint.strokeWidth = 2.5f * density
            canvas.drawLine(left, middle - half, right, middle - half, paint)
            canvas.drawLine(left, middle + half, right, middle + half, paint)
            val origin = left + 4 * density; val run = (right - origin - 4 * density).coerceAtLeast(0f)
            fun end(relative: Double): Float = origin + if (flow.centreSpeedMmPerSecond == 0.0) 0f else
                run * (flow.speedMmPerSecond(relative) / flow.centreSpeedMmPerSecond).toFloat()
            paint.color = context.getColor(R.color.health_atlas_blood_high); paint.strokeWidth = 2 * density
            for (index in -4..4) {
                val relative = index / 4.0; val y = middle + half * relative.toFloat(); val finish = end(relative)
                if (finish - origin > 3 * density) {
                    canvas.drawLine(origin, y, finish, y, paint)
                    canvas.drawLine(finish, y, finish - 3 * density, y - 3 * density, paint)
                    canvas.drawLine(finish, y, finish - 3 * density, y + 3 * density, paint)
                } else canvas.drawCircle(origin, y, 2 * density, paint)
            }
            val profile = Path()
            for (index in 0..80) {
                val relative = index / 40.0 - 1
                val x = end(relative); val y = middle + half * relative.toFloat()
                if (index == 0) profile.moveTo(x, y) else profile.lineTo(x, y)
            }
            paint.style = Paint.Style.STROKE; paint.color = context.getColor(R.color.health_overview_green)
            paint.strokeWidth = 2 * density; canvas.drawPath(profile, paint); paint.style = Paint.Style.FILL
        }
    }
}

internal object HealthAtlasVesselFlowText {
    fun geometry(context: Context, flow: HealthAtlasVesselFlow) = context.getString(R.string.health_atlas_vessel_geometry,
        HealthAtlasPhysiologyText.number(flow.radiusMm, 3), HealthAtlasPhysiologyText.number(flow.lengthMm))
    fun values(context: Context, flow: HealthAtlasVesselFlow) = listOf(
        R.string.health_atlas_vessel_mean_speed to flow.meanSpeedMmPerSecond,
        R.string.health_atlas_vessel_centre_speed to flow.centreSpeedMmPerSecond,
        R.string.health_atlas_vessel_shear to flow.wallShearPascals
    ).map { (label, value) -> context.getString(label, HealthAtlasPhysiologyText.number(value, 4)) }
    fun context(context: Context, flow: HealthAtlasVesselFlow) = buildString {
        appendLine(context.getString(R.string.health_atlas_vessel_diagram)); appendLine(geometry(context, flow))
        values(context, flow).forEach { appendLine(it) }
        append(context.getString(R.string.health_atlas_vessel_diagram_scope))
    }
}
