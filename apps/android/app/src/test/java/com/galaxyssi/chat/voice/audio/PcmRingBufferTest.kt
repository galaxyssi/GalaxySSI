package com.galaxyssi.chat.voice.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmRingBufferTest {
    @Test
    fun snapshotReportsSpeechDurationIndependentlyFromPreAndPostRoll() {
        val store = InMemorySpeechSegmentStore(sampleRateHz = 1_000, maxDurationMs = 5_000L)
        repeat(5) { sequence ->
            frame(sequence.toLong(), ShortArray(1_000)).use(store::append)
        }
        store.markSpeechStart(1L)
        store.markSpeechEnd(4L)

        val snapshot = store.snapshot(SegmentRange(preRollMs = 300, postRollMs = 400))

        assertEquals(3_000L, snapshot.speechDurationMs)
        assertEquals(3_700L, snapshot.durationMs)
    }

    @Test
    fun ringRetainsNewestSamplesAcrossWrap() {
        val ring = PcmRingBuffer(6)
        ring.append(shortArrayOf(1, 2, 3, 4), 4)
        ring.append(shortArrayOf(5, 6, 7, 8), 4)

        assertEquals(2L, ring.retainedStartSample())
        assertArrayEquals(shortArrayOf(3, 4, 5, 6, 7, 8), ring.snapshot(0, 8))
    }

    @Test
    fun speechSnapshotKeepsPreAndPostRoll() {
        val store = InMemorySpeechSegmentStore(sampleRateHz = 1_000, maxDurationMs = 2_000)
        repeat(10) { sequence ->
            frame(sequence.toLong(), ShortArray(100) { sequence.toShort() }).use { store.append(it) }
            if (sequence == 3) store.markSpeechStart(3)
            if (sequence == 7) store.markSpeechEnd(7)
        }

        val snapshot = store.snapshot(SegmentRange(preRollMs = 200, postRollMs = 100))

        assertTrue(snapshot.speechDetected)
        assertEquals(700, snapshot.samples.size)
        assertEquals(1, snapshot.samples.first().toInt())
        assertEquals(7, snapshot.samples.last().toInt())
    }

    @Test
    fun partialSnapshotOnlyCopiesTheNewestRollingWindow() {
        val store = InMemorySpeechSegmentStore(sampleRateHz = 1_000, maxDurationMs = 20_000)
        repeat(120) { sequence ->
            frame(sequence.toLong(), ShortArray(100) { sequence.toShort() }).use { store.append(it) }
            if (sequence == 5) store.markSpeechStart(5)
        }

        val partial = store.snapshotWindow(maxDurationMs = 4_000L, SegmentRange(preRollMs = 0, postRollMs = 0))

        assertEquals(4_000, partial.samples.size)
        assertEquals(8_000L, partial.captureStartSample)
        assertEquals(12_000L, partial.captureEndSampleExclusive)
        assertEquals(80, partial.samples.first().toInt())
        assertEquals(119, partial.samples.last().toInt())
    }

    private fun frame(sequence: Long, values: ShortArray) = AudioFrame(
        sequence = sequence,
        captureTimeNanos = sequence,
        samples = values,
        validSamples = values.size,
        releaseAction = {}
    )
}
