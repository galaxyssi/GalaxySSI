package com.galaxyssi.chat.voice.audio

import org.junit.Assert.*
import org.junit.Test
import java.util.Random
import java.io.File
import com.galaxyssi.chat.LocalWhisperAsr

class PlaybackEchoReferenceTest {
    private fun signal(seed: Long, ms: Int = 3_000): ShortArray {
        val random = Random(seed)
        var previous = 0.0
        return ShortArray(ms * 16) {
            previous = previous * 0.92 + random.nextGaussian() * 800
            previous.toInt().coerceIn(-30_000, 30_000).toShort()
        }
    }

    private fun input(monitor: PlaybackEchoReference.Monitor, pcm: ShortArray, start: Int,
                      timeMs: Long, gain: Double = 1.0, other: ShortArray? = null): Boolean {
        var echo = false
        repeat(10) { frame ->
            val samples = ShortArray(320) { offset ->
                val index = start + frame * 320 + offset
                (pcm[index] * gain + (other?.get(index) ?: 0)).toInt().toShort()
            }
            monitor.append(PcmFramePacket(frame.toLong(), (timeMs + (frame + 1) * 20) * 1_000_000,
                samples, 16_000))
            echo = monitor.isEcho()
            samples.fill(0)
        }
        return echo
    }

    @Test fun recognizesDelayedAttenuatedAndInvertedEchoWithoutChangingVadThresholds() {
        val pcm = signal(7)
        for (delay in listOf(0L, 80L, 310L, 850L)) {
            for (gain in listOf(0.05, 0.4, -0.25)) {
                val reference = PlaybackEchoReference()
                reference.start(PlaybackEchoReference.prepare(pcm), 1_000)
                val monitor = PlaybackEchoReference.Monitor(reference)
                assertTrue("delay=$delay gain=$gain", input(monitor, pcm, 8_000, 1_500 + delay, gain))
                reference.clear()
            }
        }
    }

    @Test fun differentSpeakerAndDoubleTalkAreNotRejected() {
        val playback = signal(7)
        val person = signal(29)
        for (gain in listOf(0.0, 0.1, 0.4, 1.0)) {
            val reference = PlaybackEchoReference()
            reference.start(PlaybackEchoReference.prepare(playback), 1_000)
            assertFalse("echo gain=$gain", input(PlaybackEchoReference.Monitor(reference),
                playback, 8_000, 1_600, gain, person))
        }
    }

    @Test fun captureAndPlaybackNeedNotHaveTheSameSamplePhase() {
        val pcm = signal(7)
        for (phase in 0 until 16) {
            val reference = PlaybackEchoReference()
            reference.start(PlaybackEchoReference.prepare(pcm), 1_000)
            assertTrue("sample phase=$phase", input(PlaybackEchoReference.Monitor(reference),
                pcm, 8_000 + phase, 1_600, 0.25))
        }
    }

    @Test fun recordedChineseSpeechWithDelayAttenuationAndRoomFilteringDoesNotInterrupt() {
        val pcm = LocalWhisperAsr.decodeAudioBytesToPcm16(
            File("src/main/assets/voice/benchmark/zh_cn_v1.wav").readBytes(), "wav")
        val reference = PlaybackEchoReference()
        val monitor = PlaybackEchoReference.Monitor(reference)
        reference.start(PlaybackEchoReference.prepare(pcm), 1_000)
        val policy = AcousticBargeInPolicy()
        var detections = 0
        var checked = 0
        try {
            for (frame in 0 until pcm.size / 320) {
                val samples = ShortArray(320) { i ->
                    val index = frame * 320 + i
                    ((pcm[index] * 0.8 + pcm[(index - 3).coerceAtLeast(0)] * 0.2) * 0.2).toInt().toShort()
                }
                val rms = kotlin.math.sqrt(samples.sumOf { it.toDouble() * it } / samples.size).toFloat() / 32768
                monitor.append(PcmFramePacket(frame.toLong(), (1_180L + (frame + 1) * 20) * 1_000_000, samples, 16_000))
                val echo = monitor.isEcho()
                if (echo) checked++
                val vad = VadDecision(0.95f, true, false, false, rms, 5_000, -58f)
                if (policy.accept(vad, 320, outputPlaying = true, playbackEcho = echo).started) detections++
                samples.fill(0)
            }
            assertTrue("Real speech supplies echo evidence", checked > 100)
            assertEquals("Recorded output cannot interrupt its own playback", 0, detections)
        } finally {
            pcm.fill(0)
            monitor.clear()
            reference.clear()
        }
    }

    @Test fun silenceNoReferenceAndSynthesisBeforePlaybackDoNotBlockInput() {
        val reference = PlaybackEchoReference()
        assertFalse(input(PlaybackEchoReference.Monitor(reference), signal(7), 0, 1_000))
        reference.start(PlaybackEchoReference.prepare(signal(7)), 3_000)
        assertFalse(input(PlaybackEchoReference.Monitor(reference), signal(7), 0, 1_000))
        assertFalse(input(PlaybackEchoReference.Monitor(reference), ShortArray(16_000), 0, 3_000))
    }

    @Test fun completedAudioTailRemainsDuringTheNextSynthesisButExpires() {
        val pcm = signal(7)
        val reference = PlaybackEchoReference()
        val prepared = PlaybackEchoReference.prepare(pcm)
        val id = reference.start(prepared, 1_000)
        reference.finish(id, 2_000)
        assertTrue("Full reference erased on finish", prepared.all { it == 0f })
        assertTrue(input(PlaybackEchoReference.Monitor(reference), pcm, 800 * 16, 2_100, 0.2))
        assertFalse(input(PlaybackEchoReference.Monitor(reference), pcm, 800 * 16, 3_000, 0.2))
    }

    @Test fun cancellingCannotMatchUnplayedFutureAudio() {
        val pcm = signal(7)
        val reference = PlaybackEchoReference()
        val id = reference.start(PlaybackEchoReference.prepare(pcm), 1_000)
        reference.finish(id, 1_400)
        assertFalse(input(PlaybackEchoReference.Monitor(reference), pcm, 600 * 16, 1_600))
    }

    @Test fun twoClipsAreBoundedAndClearedWithoutAnOldFinishDeletingTheNewOne() {
        val reference = PlaybackEchoReference()
        val one = PlaybackEchoReference.prepare(signal(1))
        val two = PlaybackEchoReference.prepare(signal(2))
        val three = PlaybackEchoReference.prepare(signal(3))
        val first = reference.start(one, 1_000)
        reference.start(two, 1_100)
        reference.start(three, 1_200)
        assertTrue(one.all { it == 0f })
        reference.finish(first, 1_250)
        assertTrue(input(PlaybackEchoReference.Monitor(reference), signal(3), 800 * 16, 2_000))
        reference.clear()
        assertTrue(two.all { it == 0f })
        assertTrue(three.all { it == 0f })
    }

    @Test fun shortDiscontinuousFramesCannotReuseAnOldMatch() {
        val pcm = signal(7)
        val reference = PlaybackEchoReference()
        reference.start(PlaybackEchoReference.prepare(pcm), 1_000)
        val monitor = PlaybackEchoReference.Monitor(reference)
        assertTrue(input(monitor, pcm, 8_000, 1_600))
        monitor.append(PcmFramePacket(99, 1_820_000_000, pcm.copyOfRange(11_200, 11_520), 16_000))
        assertFalse(monitor.isEcho())
        monitor.clear()
        assertFalse(monitor.isEcho())
    }
}
