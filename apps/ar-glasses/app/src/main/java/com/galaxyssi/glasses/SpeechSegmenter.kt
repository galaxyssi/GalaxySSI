package com.galaxyssi.glasses

import java.io.ByteArrayOutputStream

/** Collects 16 kHz, mono PCM16LE speech with leading audio and a silence tail. */
internal class SpeechSegmenter {
    private val utterance = ByteArrayOutputStream(32000)
    private var recording = false
    private var silentBytes = 0
    private var voicedBytes = 0

    fun accept(buffer: ByteArray, size: Int, amplitude: Int): ShortArray? {
        require(size in 0..buffer.size && size % 2 == 0)
        if (size == 0) return null
        val voiced = amplitude >= VOICE_THRESHOLD
        if (voiced) { recording = true; voicedBytes += size }
        utterance.write(buffer, 0, size)
        if (recording) silentBytes = if (voiced) 0 else silentBytes + size
        else if (utterance.size() > LEADING_BYTES) {
            val bytes = utterance.toByteArray()
            reset()
            utterance.write(bytes, bytes.size - LEADING_BYTES, LEADING_BYTES)
        }
        if (!recording || (silentBytes < END_SILENCE_BYTES && utterance.size() < MAX_UTTERANCE_BYTES))
            return null
        val pcm = if (voicedBytes >= MIN_VOICED_BYTES) utterance.toByteArray().let { bytes ->
            ShortArray(bytes.size / 2) { index ->
                ((bytes[index * 2 + 1].toInt() shl 8) or
                    (bytes[index * 2].toInt() and 0xff)).toShort()
            }
        } else null
        reset()
        return pcm
    }

    fun reset() {
        utterance.reset()
        recording = false
        silentBytes = 0
        voicedBytes = 0
    }

    companion object {
        const val VOICE_THRESHOLD = 180
        const val LEADING_BYTES = 16000             // 0.5 seconds
        const val END_SILENCE_BYTES = 16000 * 2 * 3 / 4
        const val MAX_UTTERANCE_BYTES = 16000 * 2 * 20
        const val MIN_VOICED_BYTES = 8192
    }
}
