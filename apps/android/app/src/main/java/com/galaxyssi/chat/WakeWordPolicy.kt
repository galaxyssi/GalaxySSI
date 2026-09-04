package com.galaxyssi.chat

import java.util.Locale

object WakeWordPolicy {
    const val WAKE_WORD = "hello"
    val configuredWords: List<String> = listOf(WAKE_WORD)

    fun matches(transcript: String): Boolean = transcript
        .lowercase(Locale.ROOT)
        .split(NON_LETTER)
        .any { it == WAKE_WORD }

    private val NON_LETTER = "[^a-z]+".toRegex()
}
