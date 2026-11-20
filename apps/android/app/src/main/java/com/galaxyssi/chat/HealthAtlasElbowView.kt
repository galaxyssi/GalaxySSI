package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout

internal class HealthAtlasElbowView(activity: Activity) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val diagram = ForceDiagram(activity)
    private val captions = (0..3).map { index -> ui.text("", 14f).apply { tag = "atlas-elbow-force-$index" } }
    private val torque = ui.text("", 14f, bold = true).apply { tag = "atlas-elbow-torque" }
    var forces = HealthAtlasElbow.forces(4.0, 38.0, 40.0)
        set(value) {
            field = value
            diagram.forces = value
            captions.forEachIndexed { index, caption -> caption.text = HealthAtlasElbowText.labels(context, value)[index] }
            torque.text = HealthAtlasElbowText.torque(context, value)
        }
    init {
        orientation = VERTICAL; tag = "atlas-elbow-balance"; isSaveEnabled = false
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_elbow_diagram), 16f, bold = true))
        ui.add(this, diagram)
        captions.forEach { ui.add(this, it, 4) }
        ui.add(this, torque, 8)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_elbow_fixed), 12f, muted = true), 8)
        forces = forces
    }

    /** Only force directions and lever-arm positions are drawn; arrow length is not force magnitude. */
    private class ForceDiagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val density = resources.displayMetrics.density
        private val font = 13f * resources.displayMetrics.scaledDensity
        var forces = HealthAtlasElbow.forces(4.0, 38.0, 40.0)
            set(value) {
                field = value
                contentDescription = HealthAtlasElbowText.context(context, value)
                invalidate()
            }
        init { tag = "atlas-elbow-diagram"; isSaveEnabled = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((140 * density + 4 * font).toInt(), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = 16 * density; val right = width - 16 * density; val y = height * .48f
            if (right <= left) return
            fun x(metres: Double) = left + ((right - left) * metres / .5).toFloat()
            paint.strokeWidth = 5 * density; paint.color = context.getColor(R.color.text_secondary)
            canvas.drawLine(left, y, x(forces.loadArmMetres), y, paint)
            canvas.drawCircle(left, y, 6 * density, paint)
            fun arrow(at: Double, up: Boolean, label: String, color: Int, zero: Boolean = false) {
                val px = x(at); val sign = if (up) -1 else 1
                val end = y + sign * 42 * density
                paint.color = context.getColor(color); paint.strokeWidth = 2.5f * density
                if (!zero) {
                    canvas.drawLine(px, y, px, end, paint)
                    canvas.drawLine(px, end, px - 4 * density, end - sign * 7 * density, paint)
                    canvas.drawLine(px, end, px + 4 * density, end - sign * 7 * density, paint)
                } else canvas.drawCircle(px, y, 3 * density, paint)
                paint.textSize = font; paint.textAlign = Paint.Align.CENTER
                canvas.drawText(label, px, if (up) end - font * .5f else end + font * 1.2f, paint)
            }
            arrow(0.0, false, "E", R.color.text_secondary)
            arrow(forces.muscleArmMetres, true, "B", R.color.health_overview_green)
            arrow(HealthAtlasElbow.ARM_CENTRE_METRES, false, "A", R.color.health_overview_orange)
            arrow(forces.loadArmMetres, false, "L", R.color.health_atlas_blood_high, forces.loadWeight == 0.0)
        }
    }
}

internal object HealthAtlasElbowText {
    fun labels(context: Context, forces: HealthAtlasElbow.Forces): List<String> = listOf(
        R.string.health_atlas_elbow_muscle_force to forces.muscle,
        R.string.health_atlas_elbow_joint_force to forces.jointDown,
        R.string.health_atlas_elbow_arm_weight to forces.armWeight,
        R.string.health_atlas_elbow_load_weight to forces.loadWeight
    ).map { (label, value) -> context.getString(label, HealthAtlasPhysiologyText.number(value)) }
    fun torque(context: Context, forces: HealthAtlasElbow.Forces) = context.getString(R.string.health_atlas_elbow_torque,
        HealthAtlasPhysiologyText.number(forces.torque))
    fun context(context: Context, forces: HealthAtlasElbow.Forces) = buildString {
        appendLine(context.getString(R.string.health_atlas_elbow_diagram))
        labels(context, forces).forEach { appendLine(it) }
        appendLine(torque(context, forces)); append(context.getString(R.string.health_atlas_elbow_fixed))
    }
}
