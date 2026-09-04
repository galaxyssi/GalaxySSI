package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceTranscriptCorrectionTest {
    @Test
    fun `risk classifier covers conversation through critical commands`() {
        assertEquals(
            VoiceCommandRisk.CONVERSATION,
            DefaultVoiceCommandRiskClassifier.classify("Explain this document")
        )
        assertEquals(
            VoiceCommandRisk.LOW,
            DefaultVoiceCommandRiskClassifier.classify("Check battery status")
        )
        assertEquals(
            VoiceCommandRisk.MEDIUM,
            DefaultVoiceCommandRiskClassifier.classify("Change settings")
        )
        assertEquals(
            VoiceCommandRisk.HIGH,
            DefaultVoiceCommandRiskClassifier.classify("Delete Downloads/a.txt")
        )
        assertEquals(
            VoiceCommandRisk.CRITICAL,
            DefaultVoiceCommandRiskClassifier.classify("Transfer money to Alice")
        )
    }

    @Test
    fun `recipient mismatch is a protected entity difference`() {
        val result = DefaultEntityConsistencyChecker.compare(
            "\u7ed9\u5f20\u4e09\u53d1\u9001\u6587\u4ef6",
            "\u7ed9\u5f20\u5c71\u53d1\u9001\u6587\u4ef6"
        )

        assertFalse(result.consistent)
        assertEquals(VoiceEntityType.RECIPIENT, result.differences.single().type)
        assertEquals(listOf("\u5f20\u4e09"), result.differences.single().fastValues)
        assertEquals(listOf("\u5f20\u5c71"), result.differences.single().accurateValues)
    }

    @Test
    fun `path mismatch blocks a protected command before execution`() {
        val fast = hypothesis("\u5220\u9664\u4e0b\u8f7d\u76ee\u5f55\u4e2d\u7684 a.txt", revision = 1)
        val accurate = hypothesis("\u5220\u9664\u4e0b\u8f7d\u76ee\u5f55\u4e2d\u7684 8.txt", revision = 2)
        val record = record(risk = VoiceCommandRisk.HIGH)

        val decision = DefaultTranscriptCorrectionController().compare(fast, accurate, record)

        assertTrue(decision is CorrectionDecision.RequireConfirmationBeforeExecution)
        val diff = DefaultEntityConsistencyChecker.compare(fast.text, accurate.text)
        assertTrue(diff.differences.any { it.type == VoiceEntityType.FILE_PATH })
    }

    @Test
    fun `amount mismatch blocks payment before execution`() {
        val decision = DefaultTranscriptCorrectionController().compare(
            hypothesis("Pay Alice 50 USD", revision = 1),
            hypothesis("Pay Alice 500 USD", revision = 2),
            record(risk = VoiceCommandRisk.CRITICAL)
        )

        assertTrue(decision is CorrectionDecision.RequireConfirmationBeforeExecution)
    }

    @Test
    fun `ordinary correction after model dispatch updates future context only`() {
        val fast = hypothesis("Summarize the blue report", revision = 1)
        val accurate = hypothesis("Summarize the new report", revision = 2)
        val record = record(
            risk = VoiceCommandRisk.CONVERSATION,
            primaryDispatchClaimed = true
        )

        val decision = DefaultTranscriptCorrectionController().compare(fast, accurate, record)

        assertTrue(decision is CorrectionDecision.UpdateFutureContext)
    }

    @Test
    fun `manual user edit remains authoritative`() {
        val fast = hypothesis("Open calendar", revision = 1)
        val accurate = hypothesis("Open calculator", revision = 2)
        val record = record(risk = VoiceCommandRisk.LOW, userEdited = true)

        val decision = DefaultTranscriptCorrectionController().compare(fast, accurate, record)

        assertTrue(decision is CorrectionDecision.UpdateFutureContext)
    }

    @Test
    fun `punctuation-only change is ignored`() {
        val decision = DefaultTranscriptCorrectionController().compare(
            hypothesis("Hello world", revision = 1),
            hypothesis("Hello, world!", revision = 2),
            record(risk = VoiceCommandRisk.CONVERSATION)
        )

        assertTrue(decision is CorrectionDecision.NoMaterialChange)
    }

    @Test
    fun `duplicate correction revision is ignored`() {
        val decision = DefaultTranscriptCorrectionController().compare(
            hypothesis("Open notes", revision = 1),
            hypothesis("Open Notes app", revision = 2),
            record(
                risk = VoiceCommandRisk.LOW,
                highestCorrectionRevision = 2
            )
        )

        assertTrue(decision is CorrectionDecision.NoMaterialChange)
    }

    @Test
    fun `low confidence and proper nouns request an accuracy pass`() {
        val lowConfidence = VoiceSecondPassTriggerPolicy.evaluate(
            fast = hypothesis("hello", revision = 1).copy(confidence = 0.55f),
            utteranceDurationMs = 900L
        )
        val namedEntities = VoiceSecondPassTriggerPolicy.evaluate(
            fast = hypothesis("Compare GPT5.6 with ClaudeCode", revision = 1),
            utteranceDurationMs = 900L
        )

        assertTrue(lowConfidence.requested)
        assertTrue("low_confidence" in lowConfidence.reasons)
        assertTrue(namedEntities.requested)
        assertTrue("proper_nouns" in namedEntities.reasons)
    }

    @Test
    fun `confident short conversation does not request an accuracy pass`() {
        val trigger = VoiceSecondPassTriggerPolicy.evaluate(
            fast = hypothesis("What is the weather", revision = 1).copy(confidence = 0.91f),
            utteranceDurationMs = 1_500L
        )

        assertFalse(trigger.requested)
    }

    private fun hypothesis(text: String, revision: Int) = TranscriptHypothesis(
        text = text,
        revision = revision,
        provider = "whisper.cpp",
        modelProfileId = if (revision == 1) "tiny_q5_1" else "medium_q5_0"
    )

    private fun record(
        risk: VoiceCommandRisk,
        primaryDispatchClaimed: Boolean = false,
        userEdited: Boolean = false,
        highestCorrectionRevision: Int = 0
    ) = VoiceExecutionRecord(
        sessionId = "voice-1",
        idempotencyKey = "voice-1:dispatch",
        fastTranscriptHash = "hash",
        fastRevision = 1,
        risk = risk,
        primaryDispatchClaimed = primaryDispatchClaimed,
        userEdited = userEdited,
        highestCorrectionRevision = highestCorrectionRevision
    )
}
