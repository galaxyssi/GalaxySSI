package com.galaxyssi.chat

import android.app.Activity
import android.os.Build
import android.view.View
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
                val widthSpec = MeasureSpec.makeMeasureSpec((width - inset).coerceAtLeast(1), MeasureSpec.EXACTLY)
                val heightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
                // Measure with TextView so mixed-script fallback fonts use the same line metrics as playback.
                val probe = TextView(context).apply {
                    paint.set(view.paint)
                    setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, view.paddingBottom)
                    includeFontPadding = view.includeFontPadding
                    setLineSpacing(view.lineSpacingExtra, view.lineSpacingMultiplier)
                    breakStrategy = view.breakStrategy
                    hyphenationFrequency = view.hyphenationFrequency
                    textDirection = view.textDirection
                    if (Build.VERSION.SDK_INT >= 28) isFallbackLineSpacing = view.isFallbackLineSpacing
                    if (Build.VERSION.SDK_INT >= 33) {
                        lineBreakStyle = view.lineBreakStyle
                        lineBreakWordStyle = view.lineBreakWordStyle
                    }
                }
                val reserved = texts.maxOf { text ->
                    probe.text = text
                    probe.measure(widthSpec, heightSpec)
                    probe.measuredHeight
                }
                view.minHeight = reserved
            }
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}
