package com.galaxyssi.chat

import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan

internal object AgentRichInlineMarkdownRenderer {
    fun render(value: String): CharSequence = SpannableStringBuilder().apply {
        AgentInlineMarkdown.parse(value).forEach { segment ->
            val start = length
            append(segment.text)
            val end = length
            when (segment.style) {
                AgentInlineStyle.BOLD -> setSpan(
                    StyleSpan(Typeface.BOLD), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                AgentInlineStyle.ITALIC -> setSpan(
                    StyleSpan(Typeface.ITALIC), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                AgentInlineStyle.STRIKE -> setSpan(
                    StrikethroughSpan(), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                AgentInlineStyle.CODE -> {
                    setSpan(TypefaceSpan("monospace"), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    setSpan(
                        BackgroundColorSpan(Color.parseColor("#F0F3F6")),
                        start,
                        end,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                AgentInlineStyle.LINK -> {
                    setSpan(URLSpan(segment.url), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    setSpan(
                        ForegroundColorSpan(Color.parseColor("#087F69")),
                        start,
                        end,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                AgentInlineStyle.NORMAL -> Unit
            }
        }
    }
}
