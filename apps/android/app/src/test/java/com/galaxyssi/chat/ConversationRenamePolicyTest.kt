package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationRenamePolicyTest {
    @Test fun emptyAndWhitespaceNamesAreRejected() {
        listOf("", " ", "\t\r\n", "\u3000\u00a0").forEach { assertNull(ConversationRenamePolicy.normalize(it)) }
    }
    @Test fun onlyOuterWhitespaceIsTrimmed() {
        assertEquals("Research  plan", ConversationRenamePolicy.normalize("  Research  plan  "))
    }
    @Test fun chineseAccentsAndEmojiArePreserved() {
        val name = "\u7814\u7a76\u8ba1\u5212 caf\u00e9 \ud83d\ude80"
        assertEquals(name, ConversationRenamePolicy.normalize(name))
    }
    @Test fun exactStorageLimitIsAcceptedWithoutTruncating() {
        val name = "a".repeat(72)
        assertEquals(name, ConversationRenamePolicy.normalize(name))
        assertEquals(72, ConversationRenamePolicy.MAX_CHARACTERS)
    }
    @Test fun exceedingStorageLimitIsRejectedInsteadOfSilentlyRenamed() {
        assertNull(ConversationRenamePolicy.normalize("a".repeat(73)))
    }
    @Test fun emojiUseTheSameUtf16BudgetAsPersistedAgentTitles() {
        assertEquals("\ud83d\ude80".repeat(36), ConversationRenamePolicy.normalize("\ud83d\ude80".repeat(36)))
        assertNull(ConversationRenamePolicy.normalize("\ud83d\ude80".repeat(37)))
    }
    @Test fun embeddedControlCharactersAndUnicodeLineBreaksAreRejected() {
        listOf('\u0000', '\t', '\n', '\r', '\u007f', '\u2028', '\u2029').forEach {
            assertNull(ConversationRenamePolicy.normalize("First${it}Second"))
        }
    }
    @Test fun punctuationIsTextAndNeverInterpretedAsAnIdentifierOrPath() {
        assertEquals("../project / notes: 2026", ConversationRenamePolicy.normalize("../project / notes: 2026"))
    }
}
