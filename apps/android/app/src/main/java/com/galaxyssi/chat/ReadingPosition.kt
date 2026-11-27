package com.galaxyssi.chat

import android.view.View
import android.widget.ImageButton

internal object ReadingPosition {
    private fun key(row: AgentTranscriptEntry) = row.turnId.ifBlank { row.taskId }.ifBlank { AgentTranscriptRenderPolicy.identity(row) }
    private fun body(row: AgentTranscriptEntry): Boolean =
        row.role == AgentTranscriptRole.ASSISTANT && !AgentReplyWaitingIndicatorPolicy.isIndicator(row) &&
            !row.id.startsWith("agent-stream-preview-") && !row.dedupeKey.startsWith("delivery-failed:") &&
            (row.text.isNotBlank() || row.richOutputJson.isNotBlank())

    fun newAnswer(previous: List<AgentTranscriptEntry>, current: List<AgentTranscriptEntry>,
                  excluded: (AgentTranscriptEntry) -> Boolean): Boolean {
        if (previous.isEmpty() || current.isEmpty() || previous.last().conversationId != current.last().conversationId) return false
        val last = previous.maxOf { it.timestampMillis }
        val seen = previous.asSequence().filter(::body).filterNot { it.richOutputJson.isNotEmpty() && excluded(it) }.map(::key).toHashSet()
        // An in-flight turn can have an older timestamp than an unrelated, later message.
        val open = previous.asSequence().filter { it.role == AgentTranscriptRole.USER && it.turnId.isNotBlank() }
            .map(::key).filterNot(seen::contains).toHashSet()
        val previousIds = previous.mapTo(hashSetOf(), AgentTranscriptRenderPolicy::identity)
        val boundary = current.indexOfLast { AgentTranscriptRenderPolicy.identity(it) in previousIds }
        return current.withIndex().any { (i, row) ->
            body(row) && !excluded(row) && key(row) !in seen && (key(row) in open ||
                row.timestampMillis > last || (row.timestampMillis == last && boundary >= 0 && i > boundary))
        }
    }
}

internal fun MainActivity.readingArrow(id: Int, show: Boolean) {
    val button = findViewById<ImageButton>(id) ?: return
    button.visibility = if (show) View.VISIBLE else View.GONE
}
