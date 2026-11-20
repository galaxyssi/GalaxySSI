package com.galaxyssi.chat

import android.content.Context
import android.view.View

internal abstract class HealthAtlasFunctionArt(context: Context, protected val story: HealthAtlasFunctionStory) : View(context) {
    var phase = 0f
        set(value) {
            val previous = story.chapter(field)
            field = HealthAtlasFunctionStory.safePhase(value)
            if (previous != story.chapter(field)) describe()
            invalidate()
        }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        describe()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val maxHeight = (resources.displayMetrics.density * 390).toInt()
        setMeasuredDimension(width, resolveSize(width.coerceAtMost(maxHeight), heightMeasureSpec))
    }

    private fun describe() {
        contentDescription = context.getString(story.chapters[story.chapter(phase)].second)
    }
}
