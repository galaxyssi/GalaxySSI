package com.galaxyssi.chat.voice.asr

import com.galaxyssi.chat.voice.TranscriptHypothesis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FinalTranscriptArbiterTest {
    @Test
    fun oneTranscriptCanCommitExecutionOnlyOnce() {
        val arbiter = FinalTranscriptArbiter { 42L }
        val first = arbiter.consider(final("online result", 2), TranscriptSource.ONLINE_PRIMARY, "exec-1")
        val duplicate = arbiter.consider(final("online result", 2), TranscriptSource.LOCAL_FALLBACK, "exec-2")
        val competing = arbiter.consider(final("different local result", 3), TranscriptSource.LOCAL_FALLBACK, "exec-3")

        assertTrue(first is TranscriptArbitrationDecision.Commit)
        assertEquals("duplicate_final", (duplicate as TranscriptArbitrationDecision.Ignored).reasonCode)
        assertEquals("execution_already_committed", (competing as TranscriptArbitrationDecision.Ignored).reasonCode)
        assertEquals("exec-1", arbiter.committed("transcript-1")?.executionId)
    }

    @Test
    fun accurateAndManualResultsBecomeCorrectionsWithoutSecondExecution() {
        val arbiter = FinalTranscriptArbiter()
        arbiter.consider(final("first", 1), TranscriptSource.ONLINE_PRIMARY)

        assertTrue(
            arbiter.consider(final("accurate", 2), TranscriptSource.ACCURATE_PASS) is
                TranscriptArbitrationDecision.Correction
        )
        assertTrue(
            arbiter.consider(final("manual", 3), TranscriptSource.MANUAL_EDIT, userConfirmed = true) is
                TranscriptArbitrationDecision.Correction
        )
        assertNotNull(arbiter.committed("transcript-1"))
    }

    @Test
    fun staleAndDuplicatePartialsAreIgnored() {
        val arbiter = FinalTranscriptArbiter()
        val visible = arbiter.consider(partial("hello", 2), TranscriptSource.ONLINE_PRIMARY)
        val duplicate = arbiter.consider(partial("hello", 2), TranscriptSource.ONLINE_PRIMARY)
        val stale = arbiter.consider(partial("old", 1), TranscriptSource.ONLINE_PRIMARY)

        assertTrue(visible is TranscriptArbitrationDecision.DisplayOnly)
        assertEquals("duplicate_partial", (duplicate as TranscriptArbitrationDecision.Ignored).reasonCode)
        assertEquals("stale_revision", (stale as TranscriptArbitrationDecision.Ignored).reasonCode)
    }

    private fun final(text: String, revision: Int) = partial(text, revision).copy(isFinal = true)

    private fun partial(text: String, revision: Int) = TranscriptHypothesis(
        text = text,
        revision = revision,
        provider = "realtime",
        transcriptId = "transcript-1"
    )
}
