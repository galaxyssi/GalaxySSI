package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ObsidianProjectionPrivacyPolicyTest {
    @Test
    fun `blocks security and transport credentials`() {
        assertFalse(ObsidianProjectionPrivacyPolicy.safeKnowledge("identity_key_sha256: abc123"))
        assertFalse(ObsidianProjectionPrivacyPolicy.safeKnowledge("MQTT password is secret"))
        assertFalse(ObsidianProjectionPrivacyPolicy.safeKnowledge("api_key=sk-private"))
    }

    @Test
    fun `allows ordinary agent knowledge`() {
        assertTrue(ObsidianProjectionPrivacyPolicy.safeKnowledge(
            "GalaxySSI uses a background cognition worker for memory evolution."
        ))
    }

    @Test
    fun `blocks credentials embedded in source metadata`() {
        assertFalse(ObsidianProjectionPrivacyPolicy.safeMetadata(
            "https://example.test/article?access_token=secret"
        ))
        assertTrue(ObsidianProjectionPrivacyPolicy.safeMetadata(
            "https://example.test/article?id=42"
        ))
    }

    @Test
    fun `redacts sensitive agent transcript content`() {
        assertEquals(
            "[Sensitive content omitted by GalaxySSI]",
            ObsidianProjectionPrivacyPolicy.transcriptText("My private key is abc123")
        )
    }
}
