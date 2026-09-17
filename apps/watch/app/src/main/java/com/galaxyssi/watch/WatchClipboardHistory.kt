package com.galaxyssi.watch

/** Only explicit copies of app replies; never monitors other apps or persists clipboard text. */
internal object WatchClipboardHistory {
    private val entries = ArrayDeque<String>()
    fun remember(text: String) {
        if (text.isBlank()) return
        val value = text.take(4000)
        entries.remove(value)
        entries.addFirst(value)
        while (entries.size > 20) entries.removeLast()
    }
    fun snapshot(): List<String> = entries.toList()
    fun clear() = entries.clear()
}
