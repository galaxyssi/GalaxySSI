package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.Base64

class WhisperTiktokenTokenizerTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun promptIdsComeFromGenerationConfigAndTextComesFromTiktokenRanks() {
        val tokenizer = tokenizer()

        assertEquals(listOf(10, 11, 12, 13), tokenizer.generation.prompt("zh").toList())
        assertEquals(listOf(10), tokenizer.generation.prompt("auto").toList())
        assertEquals("hello world", tokenizer.decode(listOf(0, 1, 2, 10)))
        assertEquals(setOf(2, 3), tokenizer.generation.suppressTokens)
        assertEquals(setOf(1), tokenizer.generation.beginSuppressTokens)
    }

    @Test
    fun nonContiguousRanksAreRejected() {
        val tokenizerFile = temporaryFolder.newFile("broken.tiktoken").apply {
            writeText("${encoded("hello")} 0\n${encoded("world")} 2\n", Charsets.US_ASCII)
        }
        val configFile = generationConfig()

        assertThrows(IllegalArgumentException::class.java) {
            WhisperTiktokenTokenizer.load(tokenizerFile, configFile)
        }
    }

    @Test
    fun `official multilingual empty token sentinel is accepted`() {
        val tokenizerFile = temporaryFolder.newFile("multilingual.tiktoken").apply {
            writeText(
                "${encoded("hello")} 0\n" +
                    "${encoded(" world")} 1\n" +
                    "= 2\n",
                Charsets.US_ASCII
            )
        }

        val tokenizer = WhisperTiktokenTokenizer.load(tokenizerFile, generationConfig())

        assertEquals(3, tokenizer.vocabularySize)
        assertEquals("hello world", tokenizer.decode(listOf(0, 1, 2)))
    }

    private fun tokenizer(): WhisperTiktokenTokenizer {
        val tokenizerFile = temporaryFolder.newFile("tokenizer-${System.nanoTime()}.tiktoken").apply {
            writeText(
                "${encoded("hello")} 0\n" +
                    "${encoded(" ")} 1\n" +
                    "${encoded("world")} 2\n",
                Charsets.US_ASCII
            )
        }
        return WhisperTiktokenTokenizer.load(tokenizerFile, generationConfig())
    }

    private fun generationConfig() = temporaryFolder.newFile("generation-${System.nanoTime()}.json").apply {
        writeText(
            """{
                "decoder_start_token_id": 10,
                "eos_token_id": 14,
                "no_timestamps_token_id": 13,
                "lang_to_id": {"<|zh|>": 11, "<|en|>": 15},
                "task_to_id": {"transcribe": 12},
                "suppress_tokens": [2, 3],
                "begin_suppress_tokens": [1]
            }""".trimIndent()
        )
    }

    private fun encoded(value: String): String =
        Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))
}
