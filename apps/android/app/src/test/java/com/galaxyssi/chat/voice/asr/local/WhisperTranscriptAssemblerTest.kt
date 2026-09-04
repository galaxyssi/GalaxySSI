package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Test

class WhisperTranscriptAssemblerTest {
    @Test
    fun removesChineseOverlapAcrossVadSegments() {
        val assembler = WhisperTranscriptAssembler()
        assembler.append("\u4eca\u5929\u4e0b\u5348\u6211\u4eec\u53bb\u673a\u573a")

        assertEquals(
            "\u4eca\u5929\u4e0b\u5348\u6211\u4eec\u53bb\u673a\u573a\u63a5\u4eba",
            assembler.append("\u673a\u573a\u63a5\u4eba")
        )
    }

    @Test
    fun removesEnglishOverlapAndPreservesWordSpacing() {
        val assembler = WhisperTranscriptAssembler()
        assembler.append("open the settings")

        assertEquals("open the settings and enable voice", assembler.append("settings and enable voice"))
        assertEquals(
            "open the settings and enable voice now",
            assembler.append("now")
        )
    }

    @Test
    fun previewDoesNotMutateCommittedTranscript() {
        val assembler = WhisperTranscriptAssembler()
        assembler.append("hello")

        assertEquals("hello world", assembler.preview("world"))
        assertEquals("hello", assembler.value())
    }
}
