package com.signalasi.chat.voice.audio

import android.media.AudioAttributes

object PeerVoiceMessageAudio {
    const val SAMPLE_RATE_HZ = 48_000
    const val CHANNEL_COUNT = 1
    const val OPUS_BIT_RATE_BPS = 48_000
    const val HIGH_PASS_HZ = 75
    const val TARGET_LUFS = -18.0
    const val PEAK_DBFS = -1.0

    fun shouldUseDedicatedCapture(purpose: String, isPersonContact: Boolean): Boolean =
        purpose == "chat_message" && isPersonContact

    fun playbackAttributes(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
}
