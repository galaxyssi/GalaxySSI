package com.galaxyssi.chat.voice.audio

import kotlin.math.abs
import kotlin.math.sqrt

/** A bounded residual-echo check, in addition to (not instead of) the recorder's AEC. */
internal class PlaybackEchoReference {
    private data class Clip(val id: Long, var startMs: Long, var signal: FloatArray, var finished: Boolean = false)
    private val clips = ArrayDeque<Clip>()
    private var nextId = 0L

    /** Takes ownership of the reduced, in-memory reference. Call only when playback actually starts. */
    @Synchronized fun start(signal: FloatArray, nowMs: Long): Long {
        prune(nowMs)
        while (clips.size >= 2) clips.removeFirst().signal.fill(0f)
        val id = ++nextId
        clips.addLast(Clip(id, nowMs, signal))
        return id
    }

    /** Keep only the short already-played tail, including when playback was cancelled. */
    @Synchronized fun finish(id: Long, nowMs: Long) {
        val clip = clips.firstOrNull { it.id == id && !it.finished } ?: return
        val end = ((nowMs - clip.startMs) * 2).toInt().coerceIn(0, clip.signal.size)
        val start = (end - (TAIL_MS + WINDOW_MS) * 2).coerceAtLeast(0)
        val tail = clip.signal.copyOfRange(start, end)
        clip.signal.fill(0f)
        clip.signal = tail
        clip.startMs += start / 2
        clip.finished = true
        prune(nowMs)
    }

    @Synchronized fun prune(nowMs: Long) {
        val iterator = clips.iterator()
        while (iterator.hasNext()) {
            val clip = iterator.next()
            if (nowMs > clip.startMs + clip.signal.size / 2 + TAIL_MS) {
                clip.signal.fill(0f)
                iterator.remove()
            }
        }
    }

    @Synchronized fun clear() {
        clips.forEach { it.signal.fill(0f) }
        clips.clear()
    }

    @Synchronized internal fun correlation(input: FloatArray, endMs: Long): Float {
        prune(endMs)
        if (clips.isEmpty()) return 0f
        val mean = input.sum().toDouble() / input.size
        var inputEnergy = 0.0
        for (sample in input) inputEnergy += (sample - mean) * (sample - mean)
        if (inputEnergy < 1.0) return 0f
        var best = 0.0
        // Half-millisecond reference offsets tolerate different capture/playback sample phases.
        for (clip in clips) {
            val nominal = (endMs - clip.startMs - input.size).toInt() * 2
            val first = maxOf(0, nominal - TAIL_MS * 2)
            val last = minOf(clip.signal.size - input.size * 2, nominal + 120)
            if (first > last) continue
            val sums = DoubleArray(2)
            val squares = DoubleArray(2)
            for (offset in first..last) {
                val phase = offset % 2
                if (offset < first + 2) {
                    for (i in input.indices) {
                        val sample = clip.signal[offset + i * 2].toDouble()
                        sums[phase] += sample
                        squares[phase] += sample * sample
                    }
                } else {
                    val old = clip.signal[offset - 2].toDouble()
                    val new = clip.signal[offset + input.size * 2 - 2].toDouble()
                    sums[phase] += new - old
                    squares[phase] += new * new - old * old
                }
                val energy = squares[phase] - sums[phase] * sums[phase] / input.size
                if (energy < 1.0) continue
                var dot = 0.0
                for (i in input.indices) dot += (input[i] - mean) * clip.signal[offset + i * 2]
                best = maxOf(best, abs(dot) / sqrt(inputEnergy * energy))
            }
        }
        return best.coerceIn(0.0, 1.0).toFloat()
    }

    class Monitor(private val reference: PlaybackEchoReference) {
        private val window = FloatArray(WINDOW_MS)
        private var filled = 0
        private var sum = 0f
        private var count = 0
        private var sequence = -1L
        private var endMs = 0L
        var maximumCorrelation = 0f
            private set
        var rejectedFrames = 0L
            private set

        @Synchronized fun append(frame: PcmFramePacket) {
            if (frame.sampleRateHz != 16_000 || (sequence >= 0 && frame.sequence != sequence + 1)) clear()
            sequence = frame.sequence
            endMs = frame.captureTimeNanos / 1_000_000L
            if (frame.sampleRateHz != 16_000) return
            for (sample in frame.samples) {
                sum += sample
                if (++count == 16) {
                    if (filled == window.size) {
                        window.copyInto(window, 0, 1)
                        filled--
                    }
                    window[filled++] = sum / 16
                    sum = 0f
                    count = 0
                }
            }
        }

        @Synchronized fun isEcho(): Boolean {
            if (filled < window.size) return false
            val correlation = reference.correlation(window, endMs)
            maximumCorrelation = maxOf(maximumCorrelation, correlation)
            // Require strong waveform agreement, not just the presence of output or similar words.
            return (correlation >= 0.90f).also { if (it) rejectedFrames++ }
        }

        @Synchronized fun clear() {
            window.fill(0f)
            filled = 0
            sum = 0f
            count = 0
            sequence = -1L
        }
    }

    companion object {
        private const val WINDOW_MS = 160
        private const val TAIL_MS = 900

        /** Two interleaved 1 kHz references, offset by half a millisecond. */
        fun prepare(pcm: ShortArray): FloatArray {
            require(pcm.size <= 16_000 * 90) { "Playback reference exceeds the playback duration limit" }
            return FloatArray(((pcm.size - 8) / 8).coerceAtLeast(0)) { index ->
                var sum = 0f
                repeat(16) { sum += pcm[index * 8 + it] }
                sum / 16
            }
        }
    }
}
