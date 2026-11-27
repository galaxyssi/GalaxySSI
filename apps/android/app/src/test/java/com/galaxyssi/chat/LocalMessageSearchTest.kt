package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class LocalMessageSearchTest {
    @Test fun snippetUsesActualMatchingWordsAndOnlyShortSurroundingText() {
        val body = "a".repeat(120) + "Original Words\nsecond line" + "b".repeat(180)
        val snippet = LocalMessageSearch.excerpt(body, "original words")!!
        assertTrue(snippet.contains("Original Words second line"))
        assertTrue(snippet.startsWith("…") && snippet.endsWith("…"))
        assertTrue(snippet.length < 120)
        assertNull(LocalMessageSearch.excerpt(body, "unrelated"))
    }
    @Test fun phraseCanCrossSeveralEncryptedChunkBoundaries() {
        val chunks = sequenceOf("前文 在线", "博", "士 后文", "不相关的段落")
        assertTrue(LocalMessageSearch.inChunks(chunks, "在线博士")!!.contains("在线博士 后文"))
    }
    @Test fun onlyOrdinaryHistoriesAreAdmittedBeforeLookingUpMessages() {
        val plain = AgentConversation("chat", "ordinary", 1, 2)
        assertTrue(LocalMessageSearch.ordinary(plain))
        assertFalse(LocalMessageSearch.ordinary(plain.copy(privateMode = true)))
        assertFalse(LocalMessageSearch.ordinary(plain.copy(globalTopicKey = "health-care:old")))
        assertFalse(LocalMessageSearch.ordinary(plain.copy(globalTopicKey = "body-atlas:item")))
        assertFalse(LocalMessageSearch.ordinary(plain.copy(trackingPaused = true)))
        assertFalse(LocalMessageSearch.ordinary(plain.copy(mergedIntoConversationId = "private-target")))
    }
}
