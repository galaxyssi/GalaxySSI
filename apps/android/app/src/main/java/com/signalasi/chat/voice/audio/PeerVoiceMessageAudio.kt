package com.signalasi.chat.voice.audio

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.audiofx.Equalizer
import java.util.WeakHashMap

object PeerVoiceMessageAudio {
    const val SAMPLE_RATE_HZ = 48_000
    const val CHANNEL_COUNT = 2
    const val AAC_BIT_RATE_BPS = 128_000

    val preferredAudioSources: List<Int> = listOf(
        MediaRecorder.AudioSource.CAMCORDER,
        MediaRecorder.AudioSource.MIC
    )

    fun shouldUseDedicatedCapture(purpose: String, isPersonContact: Boolean): Boolean =
        purpose == "chat_message" && isPersonContact

    fun configureRecorder(recorder: MediaRecorder) {
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setAudioSamplingRate(SAMPLE_RATE_HZ)
        recorder.setAudioChannels(CHANNEL_COUNT)
        recorder.setAudioEncodingBitRate(AAC_BIT_RATE_BPS)
    }

    fun playbackAttributes(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    fun gentleGainMillibels(centerFrequencyHz: Int): Int = when {
        centerFrequencyHz < 120 -> -100
        centerFrequencyHz < 700 -> 120
        centerFrequencyHz < 4_000 -> 40
        centerFrequencyHz < 8_000 -> -60
        else -> -120
    }
}

object PeerVoicePlaybackEffects {
    private val equalizers = WeakHashMap<MediaPlayer, Equalizer>()

    @Synchronized
    fun attach(player: MediaPlayer) {
        release(player)
        val equalizer = runCatching { Equalizer(0, player.audioSessionId) }.getOrNull() ?: return
        runCatching {
            val range = equalizer.bandLevelRange
            repeat(equalizer.numberOfBands.toInt()) { index ->
                val band = index.toShort()
                val centerHz = equalizer.getCenterFreq(band) / 1_000
                val level = PeerVoiceMessageAudio.gentleGainMillibels(centerHz)
                    .coerceIn(range[0].toInt(), range[1].toInt())
                    .toShort()
                equalizer.setBandLevel(band, level)
            }
            equalizer.enabled = true
            equalizers[player] = equalizer
        }.onFailure {
            equalizer.release()
        }
    }

    @Synchronized
    fun release(player: MediaPlayer?) {
        player ?: return
        equalizers.remove(player)?.let { effect ->
            runCatching { effect.enabled = false }
            runCatching { effect.release() }
        }
    }
}
