package com.galaxyssi.chat

import kotlin.math.roundToLong

/** A paused chapter retains elapsed time; time spent away never advances it. */
internal class HealthAtlasChapterClock(private val chapters: Int, initial: Float) {
    init { require(chapters > 0) }
    private val length = chapters * STEP_MS
    private var elapsed = milliseconds(initial)
    private var startedAt: Long? = null
    val playing get() = startedAt != null

    private fun milliseconds(phase: Float): Long =
        ((if (phase.isFinite()) phase.coerceIn(0f, 1f) else 0f) * length.toDouble()).roundToLong()

    private fun position(now: Long) =
        startedAt?.let { elapsed + (now - it).coerceIn(0, length - elapsed) } ?: elapsed

    fun resume(now: Long) {
        if (playing) return
        if (elapsed == length) elapsed = 0
        startedAt = now
    }

    fun pause(now: Long) {
        elapsed = position(now)
        startedAt = null
    }

    fun seek(phase: Float) {
        elapsed = milliseconds(phase)
        startedAt = null
    }

    fun sample(now: Long): Float {
        val current = position(now)
        if (current == length) pause(now)
        return (current / length.toDouble()).toFloat()
    }

    fun nextStepIn(now: Long) = STEP_MS - position(now) % STEP_MS

    companion object { const val STEP_MS = 5_000L }
}
