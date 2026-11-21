package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint

internal class HealthAtlasCellFunctionArt(context: Context, story: HealthAtlasFunctionStory, owner: String) :
    HealthAtlasFunctionArt(context, story) {
    private val scene = renderer(context, story, owner)
    private val panel = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xffeaf4f1.toInt() }
    private val radius = 8f * resources.displayMetrics.density

    init { tag = "atlas-function-$owner" }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        scene.measure(widthMeasureSpec, heightMeasureSpec)
        setMeasuredDimension(scene.measuredWidth, scene.measuredHeight)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), radius, radius, panel)
        scene.drawFrame(canvas, width, height, phase)
    }

    private fun renderer(context: Context, story: HealthAtlasFunctionStory, owner: String): HealthAtlasCellSceneView {
        val title = story.chapters.map { context.getString(it.first) }
        if (owner == HealthAtlasPhagocytosisView.OWNER) return HealthAtlasPhagocytosisView(context, title)
        HealthAtlasGranulocyte.forId(owner)?.let { return HealthAtlasGranulocyteView(context, it, title) }
        HealthAtlasImmuneLink.forId(owner)?.let { return HealthAtlasImmuneLinkView(context, it, title) }
        HealthAtlasBloodDefense.forId(owner)?.let { return HealthAtlasBloodDefenseView(context, it, title) }
        error("Missing cell renderer for $owner")
    }
}
