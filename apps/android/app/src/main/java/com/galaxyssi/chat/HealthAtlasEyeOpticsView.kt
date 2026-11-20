package com.galaxyssi.chat

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout
import kotlin.math.abs

internal class HealthAtlasEyeOpticsView(activity: Activity) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val rays = RayDiagram(activity)
    private val status = ui.text("", 16f, bold = true).apply {
        tag = "atlas-eye-focus-side"
        accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
    }
    private val imageDistance = ui.text("", 14f)
    var eye = HealthAtlasEyeOptics()
        set(value) {
            field = value
            rays.eye = value
            val side = HealthAtlasEyeOpticsText.focusSide(context, value)
            if (status.text != side) status.text = side
            imageDistance.text = HealthAtlasEyeOpticsText.imageDistance(context, value)
        }

    init {
        orientation = VERTICAL
        tag = "atlas-eye-optics"
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_eye_ray_title), 17f, bold = true))
        ui.add(this, rays, 4)
        ui.add(this, status, 4)
        ui.add(this, imageDistance, 4)
        ui.add(this, ui.text(activity.getString(R.string.health_atlas_eye_ray_legend), 13f, muted = true), 8)
        eye = eye
    }

    internal class RayDiagram(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val dp = resources.displayMetrics.density
        private val axisDash = DashPathEffect(floatArrayOf(5 * dp, 4 * dp), 0f)
        var eye = HealthAtlasEyeOptics()
            set(value) {
                field = value
                contentDescription = HealthAtlasEyeOpticsText.context(context, value)
                invalidate()
            }
        init {
            tag = "atlas-eye-rays"
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize((128 * dp).toInt(), heightMeasureSpec))
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = 10 * dp
            val right = width - left
            if (right <= left) return
            val lens = left + (right - left) * .30f
            val axis = height * .50f
            val unit = (right - lens) / 22f
            val yScale = height * .32f
            val retina = lens + HealthAtlasEyeOptics.RETINAL_PLANE_MM.toFloat() * unit
            val focus = lens + eye.imageDistanceMm.toFloat() * unit

            paint.color = context.getColor(R.color.text_secondary)
            paint.strokeWidth = dp
            paint.pathEffect = axisDash
            canvas.drawLine(left, axis, right, axis, paint)
            paint.pathEffect = null
            paint.color = context.getColor(R.color.health_atlas_eye_ray)
            paint.alpha = 60
            canvas.drawOval(lens - 7 * dp, axis - yScale - 9 * dp, lens + 7 * dp, axis + yScale + 9 * dp, paint)
            paint.alpha = 255
            paint.color = context.getColor(R.color.health_atlas_eye_retina)
            paint.strokeWidth = 3 * dp
            canvas.drawLine(retina, axis - yScale - 8 * dp, retina, axis + yScale + 8 * dp, paint)

            paint.color = context.getColor(R.color.health_atlas_eye_ray)
            paint.strokeWidth = 2 * dp
            for (sign in listOf(-1.0, 1.0)) {
                val incoming = eye.rayHeight(-100.0, sign).toFloat() * yScale
                val outgoing = eye.rayHeight(22.0, sign).toFloat() * yScale
                canvas.drawLine(left, axis + incoming, lens, axis + sign.toFloat() * yScale, paint)
                canvas.drawLine(lens, axis + sign.toFloat() * yScale, right, axis + outgoing, paint)
            }
            paint.color = context.getColor(R.color.health_overview_green)
            canvas.drawCircle(focus, axis, 4 * dp, paint)
        }
    }
}

internal object HealthAtlasEyeOpticsText {
    fun focusSide(context: Context, eye: HealthAtlasEyeOptics) = context.getString(when (eye.focusSide) {
        HealthAtlasEyeOptics.FocusSide.IN_FRONT -> R.string.health_atlas_eye_in_front
        HealthAtlasEyeOptics.FocusSide.AT_PLANE -> R.string.health_atlas_eye_at_plane
        HealthAtlasEyeOptics.FocusSide.BEHIND -> R.string.health_atlas_eye_behind
    })

    fun imageDistance(context: Context, eye: HealthAtlasEyeOptics) = context.getString(R.string.health_atlas_eye_image_distance,
        HealthAtlasPhysiologyText.number(eye.imageDistanceMm), HealthAtlasPhysiologyText.number(HealthAtlasEyeOptics.RETINAL_PLANE_MM))

    fun offsetNumber(value: Double) = HealthAtlasPhysiologyText.number(if (abs(value) < .005) 0.0 else value)

    fun context(context: Context, eye: HealthAtlasEyeOptics) = listOf(
        focusSide(context, eye), imageDistance(context, eye), context.getString(R.string.health_atlas_eye_ray_legend)
    ).joinToString("\n")
}
