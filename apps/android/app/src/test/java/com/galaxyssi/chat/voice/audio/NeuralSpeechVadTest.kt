package com.galaxyssi.chat.voice.audio

import org.junit.Assert.*
import org.junit.Test

class NeuralSpeechVadTest {
    private class Model(var score: Float = 0.9f) : SpeechProbabilityModel {
        var calls = 0
        var resets = 0
        var closed = false
        val frames = mutableListOf<FloatArray>()
        override fun prepare() = Unit
        override fun probability(samples: FloatArray): Float {
            calls++
            frames += samples.copyOf()
            return score
        }
        override fun reset() { resets++ }
        override fun close() { closed = true }
    }

    private fun frame(sequence: Long, size: Int = 320, amplitude: Short = 1_000) =
        AudioFrame(sequence, sequence * 20_000_000L, ShortArray(size) { amplitude }, size, {})

    @Test fun captureFrameSizesDoNotChangeTheModelWindowOrConfirmationTime() {
        listOf(160, 320, 512, 1_600).forEach { size ->
            val model = Model()
            NeuralSpeechVad(model).use { vad ->
                vad.prepare(16_000)
                var firstSpeechAt = 0
                repeat(16_000 / size) { index ->
                    val result = vad.accept(frame(index.toLong(), size))
                    if (result.speechStarted && firstSpeechAt == 0) firstSpeechAt = (index + 1) * size
                }
                assertTrue(firstSpeechAt in 1_024..(1_024 + size - 1))
                assertEquals((16_000 / size * size) / 512, model.calls)
                model.frames.forEach { assertEquals(512, it.size) }
            }
        }
    }

    @Test fun loudNoiseCannotBecomeSpeechFromAmplitudeAlone() {
        val model = Model(0.02f)
        NeuralSpeechVad(model).use { vad ->
            repeat(500) { index ->
                val decision = vad.accept(frame(index.toLong(), amplitude = Short.MAX_VALUE))
                assertFalse(decision.isSpeech)
                assertFalse(decision.speechStarted)
                assertTrue(decision.rms > 0.99f)
            }
        }
    }

    @Test fun isolatedProbabilitySpikesDoNotStartSpeech() {
        val model = Model()
        NeuralSpeechVad(model).use { vad ->
            repeat(20) { index ->
                model.score = if (index % 2 == 0) 0.99f else 0.01f
                assertFalse(vad.accept(frame(index.toLong(), 512)).isSpeech)
            }
        }
    }

    @Test fun aHeldProbabilityIsNotCountedAsMultipleModelDecisions() {
        val model = Model()
        NeuralSpeechVad(model).use { vad ->
            repeat(6) { assertFalse(vad.accept(frame(it.toLong(), 160)).isSpeech) }
            assertEquals(1, model.calls)
            assertTrue(vad.accept(frame(6, 160)).speechStarted)
        }
    }

    @Test fun releaseHysteresisPreservesQuietSyllablesAndEndsOnce() {
        val model = Model()
        NeuralSpeechVad(model).use { vad ->
            vad.accept(frame(0, 512))
            assertTrue(vad.accept(frame(1, 512)).speechStarted)
            model.score = 0.4f
            assertTrue(vad.accept(frame(2, 512)).isSpeech)
            model.score = 0.01f
            repeat(3) { assertTrue(vad.accept(frame(3L + it, 512)).isSpeech) }
            val ended = vad.accept(frame(6, 512))
            assertTrue(ended.speechEndedCandidate)
            assertFalse(ended.isSpeech)
            assertFalse(vad.accept(frame(7, 512)).speechEndedCandidate)
        }
    }

    @Test fun droppedFramesCannotJoinUnrelatedSpeechCandidates() {
        val model = Model()
        NeuralSpeechVad(model).use { vad ->
            vad.accept(frame(0, 512))
            assertFalse(vad.accept(frame(2, 512)).isSpeech)
            assertEquals(1, model.resets)
            assertTrue(vad.accept(frame(3, 512)).speechStarted)
        }
    }

    @Test fun resetDiscardsPartialWindowsAndCaptureHistory() {
        val model = Model()
        NeuralSpeechVad(model).use { vad ->
            vad.accept(frame(0))
            vad.reset()
            vad.accept(frame(0, 512, 2_000))
            assertEquals(1, model.calls)
            assertTrue(model.frames.single().all { it == 2_000 / 32768f })
            assertFalse(vad.accept(frame(1, 0)).isSpeech)
        }
        assertTrue(model.closed)
    }

    @Test fun nonFiniteScoresFailInsteadOfFallingBackToLoudness() {
        listOf(Float.NaN, Float.POSITIVE_INFINITY, -0.1f, 1.1f).forEach { score ->
            NeuralSpeechVad(Model(score)).use { vad ->
                assertThrows(IllegalStateException::class.java) { vad.accept(frame(0, 512)) }
            }
        }
    }

    @Test fun unsupportedSampleRateIsNotSilentlyMisclassified() {
        NeuralSpeechVad(Model()).use { vad ->
            assertThrows(IllegalArgumentException::class.java) { vad.prepare(48_000) }
        }
    }

    @Test fun preRollPreservesTheFirstSyllableBeforeNeuralConfirmation() {
        val model = Model(0.01f)
        val store = InMemorySpeechSegmentStore(16_000, 5_000)
        NeuralSpeechVad(model).use { vad ->
            repeat(50) { index ->
                val speech = index >= 25
                model.score = if (speech) 0.95f else 0.01f
                val frame = frame(index.toLong(), amplitude = if (speech) 2_000 else 0)
                store.append(frame)
                if (vad.accept(frame).speechStarted) store.markSpeechStart(frame.sequence)
            }
            val snapshot = store.snapshot(SegmentRange(preRollMs = 300, postRollMs = 400))
            assertTrue(snapshot.speechDetected)
            assertTrue(snapshot.captureStartSample <= 25L * 320)
            assertEquals(8_000, snapshot.samples.count { it == 2_000.toShort() })
            snapshot.samples.fill(0)
        }
        store.clear()
    }
}
