package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentPublicDownloadPolicyTest {
    @Test
    fun `extracts one https URL without adjacent Chinese instructions`() {
        assertEquals(
            "https://mp.weixin.qq.com/s/zxLMhBSaSV57_aRjQPwbXg",
            AgentPublicDownloadPolicy.normalizeHttpsUrl(
                "https://mp.weixin.qq.com/s/zxLMhBSaSV57_aRjQPwbXg\uff0c\u8bf7\u4e0b\u8f7d\u4fdd\u5b58"
            )
        )
    }

    @Test
    fun `preserves encoded paths and query parameters`() {
        assertEquals(
            "https://example.com/report%20final.pdf?token=a%2Fb&download=1",
            AgentPublicDownloadPolicy.normalizeHttpsUrl(
                "Download https://example.com/report%20final.pdf?token=a%2Fb&download=1 now"
            )
        )
    }

    @Test
    fun `rejects non https and credential-bearing URLs`() {
        assertNull(AgentPublicDownloadPolicy.normalizeHttpsUrl("http://example.com/file.zip"))
        assertNull(AgentPublicDownloadPolicy.normalizeHttpsUrl("https://user:secret@example.com/file.zip"))
    }
}
