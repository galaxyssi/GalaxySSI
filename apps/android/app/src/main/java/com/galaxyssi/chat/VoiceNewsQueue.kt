package com.galaxyssi.chat

/** Bounded bookmarks only; article bodies and audio never enter the checkpoint. */
internal data class VoiceNewsCheckpoint(val ids: List<String> = emptyList(), val index: Int = 0, val offset: Int = 0)

internal class VoiceNewsQueue(checkpoint: VoiceNewsCheckpoint = VoiceNewsCheckpoint()) {
    var checkpoint = normalize(checkpoint)
        private set
    var state = if (this.checkpoint.ids.isEmpty()) "stopped" else "paused"
        private set
    var revision = 0L
        private set
    val articleId get() = checkpoint.ids.getOrNull(checkpoint.index).orEmpty()
    val playing get() = state == "loading" || state == "playing"

    fun replace(ids: List<String>) {
        require(ids.isNotEmpty() && ids.size <= 20 && ids.all { it.isNotBlank() && it.length <= 256 })
        revision++
        checkpoint = VoiceNewsCheckpoint(ids.distinct())
        state = "paused"
    }
    fun resume(): Long {
        check(articleId.isNotBlank())
        if (state == "finished") checkpoint = checkpoint.copy(offset = 0)
        state = "loading"
        return ++revision
    }
    fun progress(token: Long, offset: Int): Boolean {
        if (token != revision || !playing) return false
        state = "playing"
        checkpoint = checkpoint.copy(offset = maxOf(checkpoint.offset, offset.coerceAtLeast(0)))
        return true
    }
    fun pause() { revision++; state = if (articleId.isBlank()) "stopped" else "paused" }
    fun fail() { revision++; state = "failed" }
    fun stop(clear: Boolean) {
        revision++; state = "stopped"
        if (clear) checkpoint = VoiceNewsCheckpoint()
    }
    fun next(): Boolean {
        revision++
        if (checkpoint.index + 1 >= checkpoint.ids.size) { state = "finished"; return false }
        checkpoint = checkpoint.copy(index = checkpoint.index + 1, offset = 0)
        state = "paused"
        return true
    }

    companion object {
        private fun normalize(value: VoiceNewsCheckpoint): VoiceNewsCheckpoint {
            if (value.ids.size > 20 || value.ids.any { it.isBlank() || it.length > 256 } ||
                value.ids.distinct().size != value.ids.size) return VoiceNewsCheckpoint()
            return value.copy(index = value.index.coerceIn(0, maxOf(0, value.ids.lastIndex)), offset = value.offset.coerceAtLeast(0))
        }
    }
}
