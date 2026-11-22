package com.galaxyssi.chat

import android.os.Build
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthAtlasCaptionSizes {
    private data class Caption(val view: TextView, val texts: List<String>, val inset: Int)
    private val captions = mutableListOf<Caption>()
    private var measuredWidthForText = 0

    fun add(view: TextView, texts: List<String>, inset: Int) {
        require(texts.isNotEmpty())
        captions += Caption(view, texts, inset)
        measuredWidthForText = 0
    }

    fun measure(width: Int) {
        if (width > 0 && width != measuredWidthForText) {
            measuredWidthForText = width
            for ((view, texts, inset) in captions) {
                val widthSpec = View.MeasureSpec.makeMeasureSpec((width - inset).coerceAtLeast(1), View.MeasureSpec.EXACTLY)
                val heightSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                // Measure with TextView so mixed-script fallback fonts use the same line metrics as playback.
                val probe = TextView(view.context).apply {
                    layoutParams = LinearLayout.LayoutParams(-1, -2)
                    paint.set(view.paint)
                    setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, view.paddingBottom)
                    includeFontPadding = view.includeFontPadding
                    maxLines = view.maxLines
                    ellipsize = view.ellipsize
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
                    probe.forceLayout()
                    probe.measure(widthSpec, heightSpec)
                    probe.measuredHeight
                }
                view.minHeight = reserved
            }
        }
    }
}
