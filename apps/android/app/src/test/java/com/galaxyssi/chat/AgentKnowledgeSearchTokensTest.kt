package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentKnowledgeSearchTokensTest {
    @Test fun indexesChineseWordsBigramsAndSupplementaryCharacters() {
        val terms = AgentKnowledgeSearchTokens.terms("\u624b\u673a\u5185\u5b58 \uD840\uDC00\u7535").toSet()
        assertTrue("b:\u624b\u673a" in terms)
        assertTrue("b:\u5185\u5b58" in terms)
        assertTrue("c:\uD840\uDC00" in terms)
        assertTrue("b:\uD840\uDC00\u7535" in terms)
        assertFalse(terms.any { it.contains('\uFFFD') })
    }
    @Test fun normalizesCaseAndCompatibilityForms() {
        assertEquals(AgentKnowledgeSearchTokens.terms("Camera 123").toList(),
            AgentKnowledgeSearchTokens.terms("\uFF23\uFF41\uFF4D\uFF45\uFF52\uFF41 \uFF11\uFF12\uFF13").toList())
    }
    @Test fun punctuationCannotInjectFtsSyntaxAndWordsAreNotStored() {
        AgentKnowledgeSearchTokens(ByteArray(32) { 7 }).use { tokens ->
            val query = tokens.query("secret\" OR * NEAR(title:private)")
            assertFalse(query.contains("secret"))
            assertTrue(query.split(" OR ").all { it.matches(Regex("\"[0-9a-f]{64}\"")) })
            assertEquals("", tokens.query("!@#$%"))
        }
    }
    @Test fun indexIsDeterministicOnlyWithinTheSameSecret() {
        val first = AgentKnowledgeSearchTokens(ByteArray(32) { 1 }).use { it.encode("camera") }
        val same = AgentKnowledgeSearchTokens(ByteArray(32) { 1 }).use { it.encode("CAMERA") }
        val other = AgentKnowledgeSearchTokens(ByteArray(32) { 2 }).use { it.encode("camera") }
        assertEquals(first, same)
        assertNotEquals(first, other)
    }
    @Test fun repeatsDoNotExplodeStoredTokensAndCloseWipesDerivedSecret() {
        val key = ByteArray(32) { 9 }
        val tokens = AgentKnowledgeSearchTokens(key)
        assertEquals(tokens.encode("\u79c1\u5bc6"), tokens.encode("\u79c1\u5bc6 ".repeat(1000)))
        tokens.close()
        assertTrue(key.all { it == 0.toByte() })
    }
    @Test fun documentIndexDoesNotStopAtSixtyFourTerms() {
        val words = (1..100).joinToString(" ") { "word$it" }
        AgentKnowledgeSearchTokens(ByteArray(32) { 3 }).use { tokens ->
            val encoded = tokens.encode(words).split(' ').toSet()
            val lastWord = tokens.query("word100").split(" OR ").map { it.trim('"') }
            assertTrue(encoded.containsAll(lastWord))
        }
    }
    @Test fun adjacentChineseAndLatinHaveIndependentWordTokens() {
        val terms = AgentKnowledgeSearchTokens.terms("\u4f7f\u7528Kotlin\u5f00\u53d1").toSet()
        assertTrue("w:kotlin" in terms)
        assertTrue("t:kot" in terms)
        assertTrue("b:\u5f00\u53d1" in terms)
    }
    @Test fun lexicalRerankingUsesTheSameUnicodeNormalization() {
        val item = AgentKnowledgeItem(id = "width", kind = AgentKnowledgeKind.NOTE,
            title = "\uFF23\uFF21\uFF2D\uFF25\uFF32\uFF21", content = "photo")
        val score = AgentKnowledgeCodec.semanticScore(item, "camera", AgentKnowledgeTextAnalyzer.tokens("camera"),
            AgentKnowledgeTextAnalyzer.trigrams("camera"))
        assertTrue(score >= 14.0)
    }
}
