package com.signalasi.chat

internal data class AgentRuntimeOutputExcerpt(
    val text: String,
    val totalChars: Int,
    val omittedChars: Int
) {
    val truncated: Boolean = omittedChars > 0
}

internal object AgentRuntimeModelObservation {
    fun compact(value: String): AgentRuntimeOutputExcerpt {
        if (value.length <= MAX_MODEL_CHARS) {
            return AgentRuntimeOutputExcerpt(value, value.length, 0)
        }
        val markerTemplate = "\n... SignalASI omitted %d characters from this tool observation ...\n"
        var omitted = value.length - MAX_MODEL_CHARS
        var marker = markerTemplate.format(omitted)
        val available = (MAX_MODEL_CHARS - marker.length).coerceAtLeast(2)
        val headChars = available / HEAD_TAIL_RATIO
        val tailChars = available - headChars
        omitted = value.length - headChars - tailChars
        marker = markerTemplate.format(omitted)
        val adjustedAvailable = (MAX_MODEL_CHARS - marker.length).coerceAtLeast(2)
        val adjustedHeadChars = adjustedAvailable / HEAD_TAIL_RATIO
        val adjustedTailChars = adjustedAvailable - adjustedHeadChars
        omitted = value.length - adjustedHeadChars - adjustedTailChars
        return AgentRuntimeOutputExcerpt(
            text = value.take(adjustedHeadChars) + markerTemplate.format(omitted) +
                value.takeLast(adjustedTailChars),
            totalChars = value.length,
            omittedChars = omitted
        )
    }

    private const val MAX_MODEL_CHARS = 24 * 1024
    private const val HEAD_TAIL_RATIO = 3
}
