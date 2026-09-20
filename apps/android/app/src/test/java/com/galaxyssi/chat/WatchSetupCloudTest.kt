package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchSetupCloudTest {
    private fun profile(endpoint: String = "https://example.com/v1/chat/completions", style: String = "openai") =
        JSONObject().put("endpoint", endpoint).put("api_style", style).put("model", "test-model").put("api_key", "test-only-key")
    @Test fun acceptsTheThreeWatchProtocols() {
        WatchSetupCloud.validate(profile())
        WatchSetupCloud.validate(profile("https://example.com/v1/messages", "anthropic"))
        WatchSetupCloud.validate(profile("https://example.com/v1/models/test:generateContent", "gemini"))
    }
    @Test fun rejectsUnsafeOrIncompatibleConfigurationBeforeSending() {
        listOf("http://example.com/v1/chat/completions", "https://user:pass@example.com/v1/chat/completions",
            "https://example.com/v1/chat/completions?key=secret", "https://example.com/v1/chat/completions#fragment",
            "https://example.com/v1/models").forEach { assertTrue(runCatching { WatchSetupCloud.validate(profile(it)) }.isFailure) }
        assertTrue(runCatching { WatchSetupCloud.validate(profile().put("api_key", "key\r\nInjected: header")) }.isFailure)
    }
    @Test fun certificateAndBothNoncesBindComparisonCode() {
        val code = WatchSetupClient.verificationCode(byteArrayOf(1), ByteArray(32) { 2 }, ByteArray(32) { 3 })
        assertEquals(6, code.length)
        assertNotEquals(code, WatchSetupClient.verificationCode(byteArrayOf(4), ByteArray(32) { 2 }, ByteArray(32) { 3 }))
        assertNotEquals(code, WatchSetupClient.verificationCode(byteArrayOf(1), ByteArray(32) { 5 }, ByteArray(32) { 3 }))
        assertNotEquals(code, WatchSetupClient.verificationCode(byteArrayOf(1), ByteArray(32) { 2 }, ByteArray(32) { 6 }))
    }
}
