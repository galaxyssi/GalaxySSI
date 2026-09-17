package com.galaxyssi.watch

/** Only final recognition results may arm a one-shot, user-interruptible send. */
internal class WatchVoiceDraft {
    var text: String = ""
        private set
    var deadline: Long? = null
        private set
    fun recognized(value: String, now: Long) {
        text = value.trim().take(4000)
        deadline = if (text.isBlank()) null else now + 2000
    }
    fun interrupt() { deadline = null }
    fun clear() { text = ""; deadline = null }
    fun takeDue(now: Long): String? {
        val due = deadline ?: return null
        if (now < due) return null
        return take()
    }
    fun take(): String? = text.takeIf { it.isNotBlank() }?.also { clear() }
}
