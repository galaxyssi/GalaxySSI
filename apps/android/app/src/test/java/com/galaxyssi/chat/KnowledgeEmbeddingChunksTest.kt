package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class KnowledgeEmbeddingChunksTest {
    private val count: (String) -> Int = { it.codePointCount(0, it.length) + 2 }
    private fun chunks(text: String, window: Int = 32): List<KnowledgeEmbeddingChunk> = buildList {
        var next = 0
        while (true) {
            val chunk = KnowledgeEmbeddingChunks.next(text, next, window, count) ?: break
            add(chunk); assertTrue(chunk.next > next); next = chunk.next
            if (next == text.length) break
            check(size < text.length + 1)
        }
    }
    @Test fun everyNonWhitespaceCodeUnitIsCoveredWithoutTruncation() {
        val text = ("\u624b\u673a\u8bb0\u5fc6 \uD83D\uDE80 English 123 \n").repeat(150)
        val covered = BooleanArray(text.length)
        val chunks = chunks(text)
        assertTrue(chunks.size > 100)
        chunks.forEach {
            assertEquals(text.substring(it.start, it.end), it.text)
            assertTrue(count(it.text) <= 32)
            assertFalse(it.text.first().isLowSurrogate())
            assertFalse(it.text.last().isHighSurrogate())
            for (index in it.start until it.end) covered[index] = true
        }
        text.indices.forEach { assertTrue("Uncovered offset $it", covered[it] || text[it].isWhitespace()) }
    }
    @Test fun shortAndEmptyInputsHaveNoArtificialExtraChunks() {
        assertEquals(1, chunks("\u4f60\u597d").size)
        assertEquals(0, chunks(" \n\t").size)
        assertEquals(0, chunks("").size)
    }
    @Test fun checkpointResumesAtTheSameNextChunk() {
        val text = "abcdefghijklmnopqrstuvwx".repeat(100)
        val chunks = chunks(text)
        assertEquals(chunks[1], KnowledgeEmbeddingChunks.next(text, chunks[0].next, 32, count))
        assertTrue(chunks[1].start < chunks[0].end)
    }
    @Test fun exactBoundaryKeepsOneChunkAndLongWordsRemainCovered() {
        assertEquals(1, chunks("x".repeat(30)).size)
        assertTrue(chunks("x".repeat(31)).size > 1)
        assertEquals(10000, chunks("x".repeat(10000)).last().end)
    }
    @Test fun normalizationExpansionUsesActualTokenizerCount() {
        val counter: (String) -> Int = { it.fold(2) { total, char -> total + if (char == '\uFDFA') 18 else 1 } }
        val text = "\uFDFA".repeat(20)
        val chunk = requireNotNull(KnowledgeEmbeddingChunks.next(text, 0, 32, counter))
        assertEquals(1, chunk.text.length)
    }
    @Test fun invalidOffsetsAndUnencodableCodePointsFailExplicitly() {
        assertThrows(IllegalArgumentException::class.java) { KnowledgeEmbeddingChunks.next("test", -1, 32, count) }
        assertThrows(IllegalArgumentException::class.java) { KnowledgeEmbeddingChunks.next("test", 5, 32, count) }
        assertThrows(IllegalArgumentException::class.java) { KnowledgeEmbeddingChunks.next("\uD83D\uDE80", 1, 32, count) }
        assertThrows(IllegalArgumentException::class.java) { KnowledgeEmbeddingChunks.next("x", 0, 32) { 33 } }
    }
    @Test fun largeWhitespaceGapsAreSkippedWithoutHidingLaterText() {
        val text = "first" + " ".repeat(10000) + "last"
        assertTrue(chunks(text).last().text.endsWith("last"))
    }
}
