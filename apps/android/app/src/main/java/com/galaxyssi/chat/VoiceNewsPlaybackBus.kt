package com.galaxyssi.chat

internal data class VoiceNewsPlaybackState(
    val articleId: String = "", val state: String = "stopped", val paragraph: String = "", val error: String = ""
) {
    val playing get() = state == "loading" || state == "playing"
}

/** Main-thread events for public news only, never Agent replies or contact messages. */
internal object VoiceNewsPlaybackBus {
    var current = VoiceNewsPlaybackState()
        private set
    private val listeners = linkedSetOf<(VoiceNewsPlaybackState) -> Unit>()
    fun add(listener: (VoiceNewsPlaybackState) -> Unit) { listeners.add(listener); listener(current) }
    fun remove(listener: (VoiceNewsPlaybackState) -> Unit) { listeners.remove(listener) }
    fun publish(value: VoiceNewsPlaybackState) { current = value; listeners.toList().forEach { it(value) } }
}
