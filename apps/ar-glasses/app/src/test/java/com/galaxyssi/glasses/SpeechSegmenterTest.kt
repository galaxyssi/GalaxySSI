package com.galaxyssi.glasses

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Test

class SpeechSegmenterTest {
    private val frame = ByteArray(4096)

    @Test fun normalQuestionWaitsForSilenceBeforeTranscription() {
        val segmenter = SpeechSegmenter()
        repeat(8) { assertNull(segmenter.accept(frame, frame.size, 500)) }
        repeat(5) { assertNull(segmenter.accept(frame, frame.size, 0)) }
        val pcm = segmenter.accept(frame, frame.size, 0)
        assertNotNull(pcm)
        assertEquals((8 + 6) * frame.size / 2, pcm!!.size)
    }

    @Test fun briefNoiseDoesNotBecomeAnUtterance() {
        val segmenter = SpeechSegmenter()
        assertNull(segmenter.accept(frame, frame.size, 500))
        repeat(6) { assertNull(segmenter.accept(frame, frame.size, 0)) }
    }

    @Test fun continuousSpeechIsCappedAtExactlyTwoSeconds() {
        val segmenter = SpeechSegmenter()
        val fullFrames = (SpeechSegmenter.MAX_UTTERANCE_BYTES + frame.size - 1) / frame.size
        repeat(fullFrames - 1) { assertNull(segmenter.accept(frame, frame.size, 500)) }
        val pcm = segmenter.accept(frame, frame.size, 500)
        assertNotNull(pcm)
        assertEquals(16000 * 2, pcm!!.size)
    }
}
