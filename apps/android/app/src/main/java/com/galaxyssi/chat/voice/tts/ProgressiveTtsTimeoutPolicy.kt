package com.galaxyssi.chat.voice.tts

internal object ProgressiveTtsTimeoutPolicy {
    fun forText(text: String): Long =
        (15_000L + text.codePointCount(0, text.length) * 500L).coerceIn(20_000L, 600_000L)
}
