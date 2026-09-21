package com.galaxyssi.watch

internal object WatchVoiceEntryPolicy {
    fun requestsVoice(action: String?, voiceAlias: Boolean, taskLink: Boolean): Boolean =
        !taskLink && ((voiceAlias && action == "android.intent.action.MAIN") ||
            action == "android.intent.action.VOICE_COMMAND")
}
