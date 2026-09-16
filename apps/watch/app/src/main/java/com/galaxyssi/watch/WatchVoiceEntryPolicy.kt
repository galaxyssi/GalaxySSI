package com.galaxyssi.watch

internal object WatchVoiceEntryPolicy {
    fun requestsVoice(action: String?, voiceAlias: Boolean, openWithVoice: Boolean, taskLink: Boolean): Boolean =
        !taskLink && ((voiceAlias && action == "android.intent.action.MAIN") ||
            action == "android.intent.action.VOICE_COMMAND" ||
            // Samsung's hardware shortcut sends explicit MAIN without CATEGORY_LAUNCHER.
            (openWithVoice && action == "android.intent.action.MAIN"))
}
