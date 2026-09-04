package com.galaxyssi.chat.voice.modelstream

data class ModelStreamUiUpdate(
    val text: String,
    val firstDelta: Boolean,
    val complete: Boolean = false
)

class ModelStreamUiMerger(
    private val minUpdateIntervalMs: Long = 80L,
    private val maxCharacters: Int = 200_000
) {
    private val text = StringBuilder()
    private var highestSequence = 0L
    private var lastPublishedAtMs = Long.MIN_VALUE
    private var publishedLength = 0

    init {
        require(minUpdateIntervalMs in 16L..1_000L)
        require(maxCharacters >= 4_096)
    }

    @Synchronized
    fun offer(sequence: Long, delta: String, nowMs: Long): ModelStreamUiUpdate? {
        if (sequence <= highestSequence || delta.isEmpty()) return null
        highestSequence = sequence
        if (text.length < maxCharacters) {
            text.append(delta.take(maxCharacters - text.length))
        }
        val first = publishedLength == 0 && text.isNotEmpty()
        if (!first && nowMs - lastPublishedAtMs < minUpdateIntervalMs) return null
        return publish(nowMs, first, complete = false)
    }

    @Synchronized
    fun flush(nowMs: Long, complete: Boolean = false): ModelStreamUiUpdate? {
        if (text.length == publishedLength && !complete) return null
        return publish(nowMs, first = publishedLength == 0 && text.isNotEmpty(), complete = complete)
    }

    @Synchronized
    fun snapshot(): String = text.toString()

    private fun publish(nowMs: Long, first: Boolean, complete: Boolean): ModelStreamUiUpdate {
        publishedLength = text.length
        lastPublishedAtMs = nowMs
        return ModelStreamUiUpdate(text.toString(), first, complete)
    }
}
