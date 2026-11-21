package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path

internal abstract class HealthAtlasEndocrineCellStoryView(
    context: Context,
    story: HealthAtlasFunctionStory,
    assignment: HealthAtlasEndocrineCellAssignments,
) : HealthAtlasIllustratedStoryView(context, story) {
    protected val bloodWall = 0xffa26070
    protected val bloodFill = 0xffeab4b6
    protected val divider = 0xffa4b7b4
    private val glyph = Path()

    init { tag = assignment.artTag }

    protected fun vessel(c: Canvas, route: Path, width: Float) {
        stroke(c, route, bloodWall, width + 3f)
        stroke(c, route, bloodFill, width)
    }

    protected fun diamond(c: Canvas, x: Float, y: Float, r: Float, color: Long) {
        glyph.rewind()
        glyph.moveTo(x, y - r)
        glyph.lineTo(x + r, y)
        glyph.lineTo(x, y + r)
        glyph.lineTo(x - r, y)
        glyph.close()
        ink(color); c.drawPath(glyph, paint)
    }

    protected inline fun curve(draw: Path.() -> Unit): Path = Path().apply(draw)
}
