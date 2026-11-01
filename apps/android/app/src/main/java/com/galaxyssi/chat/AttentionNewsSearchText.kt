package com.galaxyssi.chat

import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan

internal object AttentionNewsSearchText {
    fun highlight(text: String, query: String): CharSequence {
        if (query.isBlank()) return text
        return SpannableString(text).apply {
            AttentionNewsSearchPolicy.ranges(text, query).forEach { range ->
                setSpan(BackgroundColorSpan(0xffc9f3e7.toInt()), range.first, range.last + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
    }
}
