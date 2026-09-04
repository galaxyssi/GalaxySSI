package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WakeWordPolicyTest {
    @Test
    fun recognizesHelloAsAStandaloneWakeWord() {
        listOf("hello", "Hello!", "please, hello now", "hello world").forEach { transcript ->
            assertTrue(transcript, WakeWordPolicy.matches(transcript))
        }
    }

    @Test
    fun rejectsEveryLegacyAliasAndEmbeddedSubstring() {
        listOf(
            "GalaxySSI",
            "galaxy ssi",
            "hi",
            "wake up",
            "assistant",
            "\u4f60\u597d",
            "\u5c0f\u4fe1",
            "\u9192\u9192",
            "shelloworld"
        ).forEach { transcript ->
            assertFalse(transcript, WakeWordPolicy.matches(transcript))
        }
    }
}
