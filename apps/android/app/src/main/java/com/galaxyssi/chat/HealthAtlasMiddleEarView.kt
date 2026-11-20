package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.widget.LinearLayout
import kotlin.math.sqrt

internal class HealthAtlasMiddleEarView(activity: Activity) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val diagram = TransformerDiagram(activity)
    private val details = ui.text("", 14f).apply { tag = "atlas-middle-ear-details" }
    var model = HealthAtlasMiddleEar()
        set(value) {
            field = value
            diagram.model = value
            details.text = HealthAtlasMiddleEarText.ratios(context, value)
        }

    init {
        orientation = VERTICAL
        tag = "atlas-middle-ear-model"
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_middle_ear_transformer), 17f, bold = true))
        ui.add(this, diagram, 4)
        ui.add(this, details, 4)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_middle_ear_diagram_scope), 13f, muted = true), 8)
        model = model
    }

    internal class TransformerDiagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val tripod = Path()
        private val dp = resources.displayMetrics.density
        var model = HealthAtlasMiddleEar()
            set(value) {
                field = value
                contentDescription = HealthAtlasMiddleEarText.context(context, value)
                invalidate()
            }
        init {
            tag = "atlas-middle-ear-transformer"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((144 * dp).toInt(), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val centre = width * .5f
            val arm = width * .19f
            val left = centre - arm * model.leverRatio.toFloat()
            val right = centre + arm
            val beam = height * .66f
            val disc = height * .30f
            val scale = minOf(width * .12f, height * .24f)
            val inputRadius = scale * sqrt(model.membraneAreaMm2 / 75).toFloat()
            val outputRadius = scale * sqrt(model.footplateAreaMm2 / 75).toFloat()

            paint.color = context.getColor(R.color.text_secondary)
            paint.strokeWidth = 2 * dp
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawLine(left, beam, right, beam, paint)
            canvas.drawLine(left, disc, left, beam, paint)
            canvas.drawLine(right, disc, right, beam, paint)
            tripod.reset()
            tripod.moveTo(centre, beam)
            tripod.lineTo(centre - 10 * dp, beam + 17 * dp)
            tripod.lineTo(centre + 10 * dp, beam + 17 * dp)
            tripod.close()
            canvas.drawPath(tripod, paint)
            paint.color = context.getColor(R.color.health_atlas_ear_input)
            canvas.drawCircle(left, disc, inputRadius, paint)
            paint.color = context.getColor(R.color.health_atlas_ear_output)
            canvas.drawCircle(right, disc, outputRadius, paint)
        }
    }
}

internal object HealthAtlasMiddleEarText {
    fun ratios(context: Context, model: HealthAtlasMiddleEar) = context.getString(R.string.health_atlas_middle_ear_ratios,
        HealthAtlasPhysiologyText.number(model.areaRatio), HealthAtlasPhysiologyText.number(model.leverRatio),
        HealthAtlasPhysiologyText.number(model.volumeVelocityRatio, 3))

    fun context(context: Context, model: HealthAtlasMiddleEar) = listOf(
        context.getString(R.string.health_atlas_middle_ear_transformer), ratios(context, model),
        context.getString(R.string.health_atlas_middle_ear_diagram_scope),
    ).joinToString("\n")
}
