package com.galaxyssi.chat.voice

data class VoiceSessionConfig(
    val requestedSessionId: String = "",
    val source: String,
    val language: String = "auto",
    val targetId: String = "",
    val routingMode: String = "",
    val speakReplies: Boolean = false,
    val continueInBackground: Boolean = false
)
