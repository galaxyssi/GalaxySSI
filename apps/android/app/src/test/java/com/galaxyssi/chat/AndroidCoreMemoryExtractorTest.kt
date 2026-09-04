package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidCoreMemoryExtractorTest {
    @Test
    fun `extracts explicit identity device and project facts`() {
        val candidates = AndroidCoreMemoryExtractor.extract(
            "我的名字是陈星，我的手机是 Galaxy S26 Ultra，当前项目是 GalaxySSI。"
        )

        assertEquals("The user's preferred name is 陈星.", candidates.first {
            it.key == AndroidCoreMemoryExtractor.KEY_NAME
        }.value)
        assertEquals("The user's primary device is Galaxy S26 Ultra.", candidates.first {
            it.key == AndroidCoreMemoryExtractor.KEY_PRIMARY_DEVICE
        }.value)
        assertEquals("The user's current project is GalaxySSI.", candidates.first {
            it.key == AndroidCoreMemoryExtractor.KEY_CURRENT_PROJECT
        }.value)
    }

    @Test
    fun `does not promote ordinary chat into core memory`() {
        assertTrue(AndroidCoreMemoryExtractor.extract("帮我查一下今天的 Agent 新闻").isEmpty())
    }

    @Test
    fun `truncates identity at sentence punctuation`() {
        val candidate = AndroidCoreMemoryExtractor.extract("请叫我 Nova！不要保存后面这句。").single()

        assertEquals("The user's preferred name is Nova.", candidate.value)
    }

    @Test
    fun `accepts common explicit identity phrases`() {
        listOf(
            "我的名字叫 Nova",
            "我的姓名是 Nova",
            "你可以叫我 Nova",
            "I go by Nova",
            "I'm called Nova"
        ).forEach { message ->
            assertEquals(
                "The user's preferred name is Nova.",
                AndroidCoreMemoryExtractor.extract(message)
                    .single { it.key == AndroidCoreMemoryExtractor.KEY_NAME }
                    .value
            )
        }
    }
}
