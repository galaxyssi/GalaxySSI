package com.galaxyssi.chat

internal object VoiceNewsHighlightPolicy {
    fun matches(block: String, spoken: String): Boolean {
        fun clean(value: String) = value.filterNot(Char::isWhitespace)
        val text = clean(block)
        val speech = clean(spoken)
        if (text.isBlank() || speech.isBlank()) return false
        return text.contains(speech) || speech.contains(text) ||
            (text.length >= 12 && speech.length >= 12 &&
                (text.contains(speech.take(32)) || speech.contains(text.take(32))))
    }
}
