package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.nio.FloatBuffer
import java.util.ArrayDeque
import java.util.Base64

class WhisperGreedyTranscriberTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun fixedChinesePromptIsForcedBeforeGreedyTextTokens() {
        val network = FakeNetwork(99, 99, 99, 0, 1, 14)
        val result = WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "zh", 10)

        assertEquals("hello world", result.text)
        assertEquals(listOf(0, 1), result.tokenIds)
        assertEquals(listOf(10, 11, 12, 13, 0, 1), network.inputTokens)
        assertEquals(listOf(0, 1, 2, 3, 4, 5), network.positions)
        assertEquals(6, result.decoderSteps)
        assertEquals("zh", result.detectedLanguage)
        assertEquals(AsrTranscriptTermination.END_OF_TEXT, result.termination)
    }

    @Test
    fun automaticLanguageUsesPredictedLanguageBeforeTranscribePrompt() {
        val network = FakeNetwork(11, 99, 99, 0, 14)
        val result = WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "auto", 10)

        assertEquals("hello", result.text)
        assertEquals(listOf(10, 11, 12, 13, 0), network.inputTokens)
        assertEquals("zh", result.detectedLanguage)
    }

    @Test
    fun exactBudgetUsesLookAheadToRecognizeEndOfText() {
        val network = FakeNetwork(99, 99, 99, 0, 14)
        val result = WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "zh", 1)

        assertEquals(listOf(0), result.tokenIds)
        assertEquals(listOf(10, 11, 12, 13, 0), network.inputTokens)
        assertEquals(5, result.decoderSteps)
        assertEquals(AsrTranscriptTermination.END_OF_TEXT, result.termination)
    }

    @Test
    fun tokenBudgetReportsLimitWhenLookAheadIsMoreText() {
        val network = FakeNetwork(99, 99, 99, 0, 1)
        val result = WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "zh", 1)

        assertEquals(listOf(0), result.tokenIds)
        assertEquals(listOf(10, 11, 12, 13, 0), network.inputTokens)
        assertEquals(5, result.decoderSteps)
        assertEquals(AsrTranscriptTermination.TOKEN_LIMIT, result.termination)
    }

    @Test
    fun repetitiveDecoderOutputUsesConstrainedRecoveryWithoutReencoding() {
        val network = RecoveryNetwork(
            listOf(99, 99, 99, 0, 1, 0, 1, 0, 1, 0, 1, 14),
            listOf(99, 99, 99, 0, 1, 2, 14)
        )

        val result = WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "zh", 20)

        assertEquals("hello worldunused", result.text)
        assertEquals(1, network.encodeCalls)
        assertEquals(2, result.decodePasses)
        assertEquals(AsrTranscriptTermination.END_OF_TEXT, result.termination)
    }

    @Test
    fun recoveryPassAppliesDynamicNoRepeatSuppression() {
        val repeated = listOf(99, 99, 99, 0, 1, 0, 1, 0, 1, 0, 1, 14)
        val network = RecoveryNetwork(repeated, repeated)

        WhisperGreedyTranscriber(network, tokenizer()).transcribe(mel(), "zh", 20)

        assertTrue(network.additionalSuppression.any(Set<Int>::isNotEmpty))
    }

    private fun tokenizer(): WhisperTiktokenTokenizer {
        val tokenizerFile = temporaryFolder.newFile("tokenizer-${System.nanoTime()}.tiktoken").apply {
            writeText(
                "${encoded("hello")} 0\n${encoded(" world")} 1\n${encoded("unused")} 2\n",
                Charsets.US_ASCII
            )
        }
        val config = temporaryFolder.newFile("generation-${System.nanoTime()}.json").apply {
            writeText(
                """{
                    "decoder_start_token_id": 10,
                    "eos_token_id": 14,
                    "no_timestamps_token_id": 13,
                    "lang_to_id": {"<|zh|>": 11, "<|en|>": 15},
                    "task_to_id": {"transcribe": 12},
                    "suppress_tokens": [],
                    "begin_suppress_tokens": []
                }""".trimIndent()
            )
        }
        return WhisperTiktokenTokenizer.load(tokenizerFile, config)
    }

    private fun mel() = FloatArray(
        WhisperLargeTurboQnnContract.MEL_BINS * WhisperLargeTurboQnnContract.MEL_FRAMES
    ) { -1.5F }

    private fun encoded(value: String): String =
        Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))

    private class FakeNetwork(vararg tokens: Int) : WhisperQnnNetwork {
        private val outputTokens = ArrayDeque(tokens.toList())
        val inputTokens = mutableListOf<Int>()
        val positions = mutableListOf<Int>()

        override fun encode(melFeatures: FloatBuffer): Long {
            assertEquals(384_000, melFeatures.remaining())
            return 2_000_000L
        }

        override fun resetDecoder() = Unit

        override fun decode(
            inputToken: Int,
            position: Int,
            selection: WhisperDecoderSelection,
            additionalSuppressedTokens: Set<Int>
        ): WhisperQnnDecoderStep {
            inputTokens += inputToken
            positions += position
            return WhisperQnnDecoderStep(outputTokens.removeFirst(), 1_000_000L)
        }

        override fun close() = Unit
    }

    private class RecoveryNetwork(vararg passes: List<Int>) : WhisperQnnNetwork {
        private val scripts = ArrayDeque(passes.toList())
        private var outputTokens = ArrayDeque<Int>()
        var encodeCalls = 0
        val additionalSuppression = mutableListOf<Set<Int>>()

        override fun encode(melFeatures: FloatBuffer): Long {
            encodeCalls += 1
            return 2_000_000L
        }

        override fun resetDecoder() {
            outputTokens = ArrayDeque(scripts.removeFirst())
        }

        override fun decode(
            inputToken: Int,
            position: Int,
            selection: WhisperDecoderSelection,
            additionalSuppressedTokens: Set<Int>
        ): WhisperQnnDecoderStep {
            additionalSuppression += additionalSuppressedTokens
            val scripted = outputTokens.removeFirst()
            val next = if (scripted in additionalSuppressedTokens) 14 else scripted
            return WhisperQnnDecoderStep(next, 1_000_000L)
        }

        override fun close() = Unit
    }
}
