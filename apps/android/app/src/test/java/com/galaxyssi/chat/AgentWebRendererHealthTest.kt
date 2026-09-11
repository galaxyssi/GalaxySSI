package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentWebRendererHealthTest {
    @Test fun processPolicyLeavesMainAndModelProcessesUnchanged() {
        assertFalse(AgentWebRendererProcessPolicy.isRenderer("com.galaxyssi.chat", "com.galaxyssi.chat"))
        assertFalse(AgentWebRendererProcessPolicy.isRenderer("com.galaxyssi.chat", "com.galaxyssi.chat:local_model_runtime"))
        assertFalse(AgentWebRendererProcessPolicy.isRenderer("com.galaxyssi.chat", "another:web_renderer"))
        assertTrue(AgentWebRendererProcessPolicy.isRenderer("com.galaxyssi.chat", "com.galaxyssi.chat:web_renderer"))
        assertFalse(AgentWebRendererProcessPolicy.DIRECTORY_SUFFIX.contains('/'))
    }

    @Test fun unavailableRendererHasBoundedCooldownAndRecovers() {
        var time = 0L
        val health = AgentWebRendererHealth({ time }, 30L)
        health.checkAvailable()
        health.failed()
        repeat(5) {
            time += 5
            assertThrows(AgentWebRendererUnavailableException::class.java) { health.checkAvailable() }
        }
        time = 30
        health.checkAvailable()
        health.failed()
        health.succeeded()
        health.checkAvailable()
    }

    @Test fun rendererFailureTellsModelToUseEvidenceWithoutClaimingSuccess() {
        val failure = IllegalStateException("static fetch failed").apply {
            addSuppressed(AgentWebRendererUnavailableException("renderer_connection_timeout"))
        }
        val result = CloudWebGrounding.failureResult("web_fetch", failure)
        assertEquals("failed", result.getString("status"))
        assertFalse(result.getBoolean("retryable"))
        assertTrue(result.getString("next_action").contains("Do not retry"))
        assertTrue(result.getString("next_action").contains("missing evidence"))
    }

    @Test fun unknownSourceRequestsCorrectionWithoutSilentlyChangingUserScope() {
        val result = CloudWebGrounding.failureResult("web_agent",
            IllegalArgumentException("Unknown web intelligence engines: wiktionary"))
        assertTrue(result.getString("next_action").contains("user did not require a specific source"))
        assertEquals("failed", result.getString("status"))
    }
}
