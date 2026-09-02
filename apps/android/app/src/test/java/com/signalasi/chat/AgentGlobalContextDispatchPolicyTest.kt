package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentGlobalContextDispatchPolicyTest {
    @Test
    fun exactGreetingsUseMinimalContext() {
        listOf(
            "hello",
            "Hello!",
            "hi there",
            "\u4f60\u597d",
            "\u4f60\u597d\uff01",
            "\u65e9\u4e0a\u597d"
        ).forEach { query ->
            assertEquals(
                query,
                AgentGlobalContextMode.MINIMAL,
                AgentGlobalContextDispatchPolicy.mode(query, hasAttachments = false)
            )
        }
    }

    @Test
    fun attachmentsExcludeUnrelatedGlobalContext() {
        assertEquals(
            AgentGlobalContextMode.MINIMAL,
            AgentGlobalContextDispatchPolicy.mode("hello", hasAttachments = true)
        )
    }

    @Test
    fun taskAndContinuationRequestsPreserveFullContext() {
        listOf(
            "\u4f60\u597d\uff0c\u8bf7\u7ee7\u7eed\u5904\u7406\u521a\u624d\u7684\u56fe\u7247",
            "hello, summarize the attachment",
            "\u7ee7\u7eed",
            "\u5f53\u524d\u8bf7\u6c42",
            "\u65e9\u4e0a\u597d\uff0c\u67e5\u770b\u4eca\u5929\u7684\u65b0\u95fb"
        ).forEach { query ->
            assertEquals(
                query,
                AgentGlobalContextMode.FULL,
                AgentGlobalContextDispatchPolicy.mode(query, hasAttachments = false)
            )
        }
    }
}
