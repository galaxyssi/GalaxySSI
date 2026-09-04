package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentLargeOutputPolicyTest {
    @Test
    fun `large output splits at readable boundaries and reconstructs exactly`() {
        val source = buildString {
            repeat(80) { index ->
                append("Section ").append(index).append('\n')
                append("content ".repeat(180))
                append("\n\n")
            }
        }

        val prepared = AgentLargeOutputPolicy.prepare(source, includePreview = true)

        assertTrue(prepared.chunkCount > 1)
        assertTrue(prepared.storedValue.length <= AgentLargeOutputPolicy.PREVIEW_CHARACTERS)
        assertEquals(source, prepared.chunks.joinToString(""))
        assertEquals(source.length, prepared.totalLength)
        assertEquals(AgentLargeOutputPolicy.digest(source), prepared.sha256)
    }

    @Test
    fun `deferred content distinguishes preview from hydrated entry`() {
        val source = "long response\n".repeat(2_000)
        val prepared = AgentLargeOutputPolicy.prepare(source, includePreview = true)
        val preview = entry(
            text = prepared.storedValue,
            chunkCount = prepared.chunkCount,
            totalLength = prepared.totalLength,
            sha256 = prepared.sha256
        )
        val hydrated = preview.copy(text = source)

        assertTrue(AgentLargeOutputPolicy.hasDeferredContent(preview))
        assertFalse(AgentLargeOutputPolicy.hasDeferredContent(hydrated))
    }

    @Test
    fun `chunk and preview boundaries preserve non bmp characters`() {
        val source = buildString {
            append("a".repeat(AgentLargeOutputPolicy.PREVIEW_CHARACTERS - 1))
            append("\uD83D\uDE80")
            append("b".repeat(AgentLargeOutputPolicy.CHUNK_THRESHOLD_CHARACTERS))
        }

        val prepared = AgentLargeOutputPolicy.prepare(source, includePreview = true)

        assertFalse(Character.isHighSurrogate(prepared.storedValue.last()))
        prepared.chunks.forEach { chunk ->
            assertFalse(Character.isHighSurrogate(chunk.last()))
            assertFalse(Character.isLowSurrogate(chunk.first()))
        }
        assertEquals(source, prepared.chunks.joinToString(""))
        assertEquals(AgentLargeOutputPolicy.digest(source), prepared.sha256)
    }

    private fun entry(
        text: String,
        chunkCount: Int,
        totalLength: Int,
        sha256: String
    ) = AgentTranscriptEntry(
        id = "entry",
        role = AgentTranscriptRole.ASSISTANT,
        text = text,
        timestampMillis = 1L,
        conversationId = "conversation",
        textChunkCount = chunkCount,
        textLength = totalLength,
        textSha256 = sha256
    )
}
