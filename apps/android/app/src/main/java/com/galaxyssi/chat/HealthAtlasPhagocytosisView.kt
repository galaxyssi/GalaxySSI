package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas

/** Four qualitative stages share the painted structure plate and the native playhead. */
internal class HealthAtlasPhagocytosisView(context: Context, stageTitles: List<String>) :
    HealthAtlasCellSceneView(context, stageTitles, R.string.health_atlas_phagocytosis_visual_stage, maxHeightDp = 235) {
    constructor(context: Context, mechanism: HealthAtlasMechanism) : this(context, mechanism.stages)

    private val art = requireNotNull(context.getDrawable(R.drawable.health_atlas_cell_macrophage)).mutate().apply {
        setBounds(17, -22, 261, 222)
        setFilterBitmap(true)
    }
    private val particle = 0xff9f6c44.toInt()
    private val compartment = 0xffa06476.toInt()
    private val signal = 0xff40827f.toInt()
    init { tag = "atlas-phagocytosis-diagram" }

    private fun target(canvas: Canvas, x: Float, y: Float) {
        fill(particle)
        canvas.save()
        canvas.rotate(-23f, x, y)
        canvas.drawRoundRect(x - 11f, y - 5f, x + 11f, y + 5f, 5f, 5f, paint)
        canvas.restore()
    }
    override fun drawScene(canvas: Canvas, t: Float) {
        art.draw(canvas)
        when (stage) {
            0 -> {
                target(canvas, 298f - t * 80f, 98f)
                stroke(particle, 2f)
                canvas.drawLine(276f, 119f, 215f, 119f, paint)
                canvas.drawLine(215f, 119f, 222f, 114f, paint)
                canvas.drawLine(215f, 119f, 222f, 124f, paint)
            }
            1 -> {
                val x = 218f - t * 62f
                stroke(compartment, 2.5f)
                paint.alpha = (70f + t * 185f).toInt()
                canvas.drawCircle(x, 98f, 15f + t * 8f, paint)
                target(canvas, x, 98f)
            }
            2 -> {
                stroke(compartment, 2.5f); canvas.drawCircle(156f, 98f, 23f, paint)
                fill(particle)
                canvas.drawCircle(146f, 94f, 4.5f - t * 2f, paint)
                canvas.drawCircle(156f, 105f, 4f - t * 2f, paint)
                canvas.drawCircle(166f, 96f, 3.5f - t * 2f, paint)
            }
            3 -> {
                stroke(compartment, 2.5f); canvas.drawCircle(156f, 98f, 10f, paint)
                fill(particle); canvas.drawCircle(156f, 98f, 2.5f, paint)
                stroke(signal, 2.5f)
                val drift = t * 18f
                canvas.drawArc(220f + drift, 75f, 260f + drift, 121f, -38f, 76f, false, paint)
                canvas.drawArc(218f + drift, 64f, 276f + drift, 132f, -38f, 76f, false, paint)
            }
        }
    }
    companion object { const val OWNER = "cell-macrophage" }
}
