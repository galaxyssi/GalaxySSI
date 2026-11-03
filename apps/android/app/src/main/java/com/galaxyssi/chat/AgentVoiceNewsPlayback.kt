package com.galaxyssi.chat

/** UI subscription only. The foreground service owns speech and survives page destruction. */
internal class AgentVoiceNewsPlayback(private val activity: MainActivity,
    private val onChunk: (String) -> Unit, private val onDone: () -> Unit, private val onPaused: () -> Unit) {
    private var previous = VoiceNewsPlaybackBus.current
    private var localPause = false
    private val listener: (VoiceNewsPlaybackState) -> Unit = { value ->
        val before = previous
        previous = value
        if (activity.agentVoiceConversation?.hasForegroundHost() == true) {
            if (value.state == "playing" && value.paragraph.isNotBlank() &&
                (before.paragraph != value.paragraph || before.state != value.state)) onChunk(value.paragraph)
            else if (before.playing && value.state in setOf("finished", "failed")) onDone()
            else if (!localPause && before.playing && value.state in setOf("paused", "stopped")) onPaused()
            AppVoiceControlBridge.update(activity)
        }
    }
    init { VoiceNewsPlaybackBus.add(listener) }
    val state get() = VoiceNewsPlaybackBus.current.state
    val articleId get() = VoiceNewsPlaybackBus.current.articleId
    val playing get() = VoiceNewsPlaybackBus.current.playing
    fun replace(values: List<String>) {
        require(values.isNotEmpty() && values.size <= 20)
        VoiceNewsPlaybackService.command(activity, "replace", values)
    }
    fun pause() {
        localPause = true
        try { VoiceNewsPlaybackService.pauseForInput() } finally { localPause = false }
    }
    fun stop(clear: Boolean = false) { if (articleId.isNotBlank()) VoiceNewsPlaybackService.command(activity, if (clear) "stop" else "pause") }
    fun next() = VoiceNewsPlaybackService.command(activity, "next")
    fun resume() = VoiceNewsPlaybackService.command(activity, "resume")
    fun release() = VoiceNewsPlaybackBus.remove(listener)
}
