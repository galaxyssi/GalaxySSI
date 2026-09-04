package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class VoiceExecutionLedgerTest {
    @Test
    fun `external effects agent runs and tts corrections are each idempotent`() {
        val ledger = VoiceExecutionLedger()
        ledger.begin("session", "session:dispatch", hypothesis(), VoiceCommandRisk.HIGH)

        assertTrue(ledger.claimPrimaryDispatch("session"))
        assertFalse(ledger.claimPrimaryDispatch("session"))
        assertTrue(ledger.claimExternalSideEffect("session"))
        assertFalse(ledger.claimExternalSideEffect("session"))
        assertTrue(ledger.claimAgentRun("session"))
        assertFalse(ledger.claimAgentRun("session"))
        assertTrue(ledger.claimTtsCorrection("session"))
        assertFalse(ledger.claimTtsCorrection("session"))

        val record = requireNotNull(ledger.snapshot("session"))
        assertEquals(1, record.externalSideEffectCount)
        assertEquals(1, record.agentRunCount)
        assertEquals(1, record.ttsCorrectionCount)
    }

    @Test
    fun `only the highest correction revision is accepted`() {
        val ledger = VoiceExecutionLedger()
        ledger.begin("session", "session:dispatch", hypothesis(), VoiceCommandRisk.CONVERSATION)

        assertTrue(ledger.acceptCorrectionRevision("session", 2))
        assertFalse(ledger.acceptCorrectionRevision("session", 2))
        assertFalse(ledger.acceptCorrectionRevision("session", 1))
        assertTrue(ledger.acceptCorrectionRevision("session", 3))
        assertEquals(3, ledger.snapshot("session")?.highestCorrectionRevision)
    }

    @Test
    fun `bounded records are persisted without transcript plaintext`() {
        val writes = CopyOnWriteArrayList<List<VoiceExecutionRecord>>()
        val ledger = VoiceExecutionLedger(
            persistence = VoiceExecutionRecordPersistence(writes::add),
            maxRecords = 16
        )

        repeat(20) { index ->
            ledger.begin("session-$index", "dispatch-$index", hypothesis("private-$index"), VoiceCommandRisk.LOW)
        }

        assertEquals(16, ledger.all().size)
        assertTrue(writes.last().none { it.fastTranscriptHash.contains("private") })
    }

    private fun hypothesis(text: String = "hello") = TranscriptHypothesis(
        text = text,
        revision = 1,
        provider = "whisper.cpp",
        modelProfileId = "tiny_q5_1"
    )
}
