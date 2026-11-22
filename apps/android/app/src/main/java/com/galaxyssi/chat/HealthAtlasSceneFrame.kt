package com.galaxyssi.chat

import android.app.Activity
import android.text.StaticLayout
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthAtlasSceneFrame(activity: Activity, key: String) : LinearLayout(activity) {
    private data class Caption(val view: TextView, val texts: List<String>, val inset: Int)
    private val captions = mutableListOf<Caption>()
    private var measuredWidthForText = 0

    init {
        orientation = VERTICAL
        tag = key
        background = HealthCenterViews(activity).background()
        clipToOutline = true
    }

    fun reserveCaption(view: TextView, texts: List<String>, inset: Int = 0) {
        require(texts.isNotEmpty())
        captions += Caption(view, texts, inset)
        measuredWidthForText = 0
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec) - paddingStart - paddingEnd
        if (width > 0 && width != measuredWidthForText) {
            measuredWidthForText = width
            for ((view, texts, inset) in captions) {
                val textWidth = (width - inset - view.totalPaddingStart - view.totalPaddingEnd).coerceAtLeast(1)
                val lines = texts.maxOf { text ->
                    StaticLayout.Builder.obtain(text, 0, text.length, view.paint, textWidth)
                        .setIncludePad(view.includeFontPadding)
                        .setLineSpacing(view.lineSpacingExtra, view.lineSpacingMultiplier)
                        .setBreakStrategy(view.breakStrategy)
                        .setHyphenationFrequency(view.hyphenationFrequency)
                        .build().height
                }
                view.minimumHeight = lines + view.totalPaddingTop + view.totalPaddingBottom
            }
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}
