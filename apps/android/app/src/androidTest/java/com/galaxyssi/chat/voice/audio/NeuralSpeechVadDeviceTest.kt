package com.galaxyssi.chat.voice.audio

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkAudioLoader
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random

/** Real bundled model and CPU runtime; no network, private recordings or volume changes. */
class NeuralSpeechVadDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val inferenceMs = mutableListOf<Double>()

    @Test fun bundledModelRejectsNonSpeechAndAcceptsChineseAtDifferentLevels() {
        val random = Random(42)
        val noises = linkedMapOf(
            "silence" to ShortArray(80_000),
            "white_noise" to ShortArray(80_000) { random.nextInt(-6_000, 6_000).toShort() },
            "fan_hum" to ShortArray(80_000) {
                (2_500 * sin(2 * PI * 100 * it / 16_000) + random.nextInt(-500, 500)).toInt().toShort()
            },
            "notification_tone" to ShortArray(80_000) { (6_000 * sin(2 * PI * 1_000 * it / 16_000)).toInt().toShort() },
            "clicks" to ShortArray(80_000) { if (it % 4_000 < 10) 24_000 else 0 }
        )
        val started = SystemClock.elapsedRealtime()
        NeuralSpeechVad(SileroSpeechProbabilityModel(context.assets)).use { vad ->
            vad.prepare(16_000)
            val preparationMs = SystemClock.elapsedRealtime() - started
            noises.forEach { (name, samples) ->
                try { assertEquals("False speech: $name", 0, classify(vad, samples)) }
                finally { samples.fill(0) }
            }
            val speech = WhisperBenchmarkAudioLoader.load(context).window(10_000)
            try {
                assertTrue("Chinese fixture must be detected", classify(vad, speech) > 100)
                val quiet = ShortArray(speech.size) { (speech[it] * 0.12f).toInt().toShort() }
                val noisy = ShortArray(speech.size) {
                    (speech[it].toInt() + random.nextInt(-550, 550)).coerceIn(-32768, 32767).toShort()
                }
                try {
                    assertTrue("Quiet speech must not be gated by volume", classify(vad, quiet) > 100)
                    assertTrue("Speech mixed with noise must survive", classify(vad, noisy) > 100)
                } finally { quiet.fill(0); noisy.fill(0) }
                assertEquals("State cannot leak into the next capture", 0, classify(vad, ShortArray(48_000)))
            } finally { speech.fill(0) }
            val sorted = inferenceMs.sorted()
            val p95 = sorted[(sorted.size * 0.95).toInt().coerceAtMost(sorted.lastIndex)]
            assertTrue("VAD must fit within a 20 ms capture frame: $p95", p95 < 20)
            instrumentation.sendStatus(0, Bundle().apply {
                putString("neural_vad", "5 non-speech fixtures rejected; normal, quiet and noisy Chinese accepted; reset clean")
                putLong("vad_prepare_ms", preparationMs)
                putString("vad_frame_p95_ms", "%.3f".format(p95))
                putString("vad_frame_max_ms", "%.3f".format(sorted.last()))
            })
        }
    }

    @Test fun modelCanBeReopenedWithoutRetainingRecurrentState() {
        repeat(5) {
            NeuralSpeechVad(SileroSpeechProbabilityModel(context.assets)).use { vad ->
                vad.prepare(16_000)
                assertEquals(0, classify(vad, ShortArray(16_000)))
            }
        }
    }

    private fun classify(vad: VoiceActivityDetector, samples: ShortArray): Int {
        vad.reset()
        var speechFrames = 0
        var sequence = 0L
        for (offset in samples.indices step 320) {
            val block = samples.copyOfRange(offset, minOf(offset + 320, samples.size))
            AudioFrame(sequence++, 0, block, block.size, { it.fill(0) }).use { frame ->
                val started = SystemClock.elapsedRealtimeNanos()
                val decision = vad.accept(frame)
                inferenceMs += (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0
                if (decision.isSpeech) speechFrames++
            }
        }
        return speechFrames
    }
}
