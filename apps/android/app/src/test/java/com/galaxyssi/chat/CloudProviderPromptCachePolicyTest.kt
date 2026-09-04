package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudProviderPromptCachePolicyTest {
    @Test
    fun `anthropic project prompts request explicit prefix caching`() {
        assertTrue(
            CloudProviderPromptCachePolicy.shouldRequestExplicitCache(
                apiStyle = "anthropic",
                defaultSystemPrompt = false
            )
        )
    }

    @Test
    fun `ordinary anthropic chat does not change request behavior`() {
        assertFalse(
            CloudProviderPromptCachePolicy.shouldRequestExplicitCache(
                apiStyle = "anthropic",
                defaultSystemPrompt = true
            )
        )
    }

    @Test
    fun `implicitly cached providers do not receive anthropic fields`() {
        assertFalse(CloudProviderPromptCachePolicy.shouldRequestExplicitCache("openai", false))
        assertFalse(CloudProviderPromptCachePolicy.shouldRequestExplicitCache("gemini", false))
    }
}
