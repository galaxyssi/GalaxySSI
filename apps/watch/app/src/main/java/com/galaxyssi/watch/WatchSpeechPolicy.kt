package com.galaxyssi.watch

import com.galaxyssi.chat.voice.modelstream.DefaultSentenceCommitter

/** Commit completed displayed paragraphs once; stopping suppresses the rest of that response. */
internal class WatchSpeechPolicy {
    data class Update(val reset: Boolean, val chunks: List<String>, val awaitingMore: Boolean)
    private var initialized = false
    private var responseId = ""
    private var previous = ""
    private var consumed = 0
    private var muted = false

    fun observe(id: String, text: String, complete: Boolean, enabled: Boolean): Update {
        val first = !initialized
        val changed = first || id != responseId
        initialized = true
        if (changed) {
            responseId = id; previous = ""; consumed = 0; muted = false
        }
        val rewritten = !changed && !text.startsWith(previous)
        if (rewritten) muted = true
        previous = text
        val boundary = if (complete) text.length else (text.lastIndexOf('\n') + 1)
        val ready = if (!first && !(changed && complete) && !muted && enabled && id.isNotBlank() && boundary > consumed)
            listOf(text.substring(consumed, boundary)) else emptyList()
        consumed = boundary
        return Update(changed || rewritten, ready, !complete && enabled && !muted && id.isNotBlank())
    }
    fun stop() { muted = true }

    companion object {
        fun chunks(text: String): List<String> = text.lineSequence().flatMap { paragraph ->
            val clean = paragraph.trim().replace(Regex("^[\u2022\u2610\u2611]\\s*"), "")
            val committer = DefaultSentenceCommitter().apply { reset("watch-paragraph") }
            (committer.acceptDelta(0, clean) + committer.flush()).asSequence().map { it.speechText }
        }.filter(String::isNotBlank).toList()
    }
}
