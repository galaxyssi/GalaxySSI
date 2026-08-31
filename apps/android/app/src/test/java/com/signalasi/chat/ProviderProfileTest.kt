package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProviderProfileTest {
    @Test
    fun catalogContainsEveryRequiredModelProvider() {
        assertEquals(
            setOf(
                "openai",
                "anthropic",
                "gemini",
                "deepseek",
                "qwen",
                "ollama",
                "lm-studio",
                "openrouter"
            ),
            ProviderProfileCatalog.modelProviders.map { it.providerId }.toSet()
        )
        ProviderProfileCatalog.modelProviders.forEach { provider ->
            assertTrue(provider.contextWindowTokens > 0)
        }
    }

    @Test
    fun cloudContactProducesRoutableProfileWithLimitsAndToolCapability() {
        val contact = JSONObject()
            .put("id", "cloud:deepseek")
            .put("cloud_provider", "DeepSeek")
            .put("cloud_model", "deepseek-v4-pro")
            .put("cloud_endpoint", "https://api.deepseek.com/chat/completions")
            .put("cloud_api_key", "stored-key")
            .put("cloud_api_style", "openai")
            .put("cloud_context_window_tokens", 96_000)
            .put("cloud_max_output_tokens", 8_192)

        val profile = ProviderProfileCatalog.fromCloudContact(
            contact,
            AgentConnectorStatus.AVAILABLE
        )

        assertEquals("model:deepseek", profile.profileId)
        assertEquals("deepseek-v4-pro", profile.modelId)
        assertEquals(96_000, profile.contextWindowTokens)
        assertEquals(8_192, profile.maxOutputTokens)
        assertEquals(10, profile.maxParallelRuns)
        assertTrue(profile.supportsTools)
        assertTrue(AgentCapability.LIVE_DATA in profile.capabilities)
        assertTrue(profile.credentialConfigured)
    }

    @Test
    fun jsonRoundTripKeepsMetricsButNeverContainsCredentialValue() {
        val original = ProviderProfileCatalog.fromCloudContact(
            JSONObject()
                .put("id", "cloud:openai")
                .put("cloud_provider", "OpenAI")
                .put("cloud_model", "gpt-test")
                .put("cloud_endpoint", "https://api.openai.com/v1/chat/completions")
                .put("cloud_api_key", "private-secret"),
            AgentConnectorStatus.AVAILABLE,
            ProviderPerformanceProfile(
                attempts = 5,
                successes = 4,
                failures = 1,
                failureRate = 0.2,
                ewmaLatencyMs = 850.0
            )
        )

        val encoded = ProviderProfileCatalog.encode(original)
        val restored = ProviderProfileCatalog.decode(encoded)

        assertNotNull(restored)
        assertEquals(original, restored)
        assertFalse(encoded.toString().contains("private-secret"))
    }

    @Test
    fun nativeAgentKeepsProductIdentityAndNativeAdapter() {
        val registration = AgentRegistration(
            agentId = "desktop_a:codex",
            installationId = "desktop_a",
            deviceId = "desktop_a",
            providerId = "desktop_a",
            displayName = "Codex · Workstation",
            kind = AgentConnectorKind.AGENT,
            location = AgentResourceLocation.TRUSTED_DESKTOP,
            status = AgentEndpointStatus.ONLINE,
            capabilities = setOf(
                AgentCapability.CHAT,
                AgentCapability.CODE,
                AgentCapability.TASK_EXECUTION,
                AgentCapability.TOOL_USE
            ),
            protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
            connectionKind = AgentConnectionKind.SIGNALASI_LINK,
            adapterType = "codex-app-server",
            failureDomain = "desktop_a"
        )

        val profile = ProviderProfileCatalog.fromRegistration(registration)

        assertEquals("codex", profile.productId)
        assertEquals("codex-app-server", profile.adapterType)
        assertEquals(ProviderProfileKind.AGENT, profile.kind)
        assertEquals("desktop_a", profile.providerId)
    }

    @Test
    fun nativeAgentWithoutExplicitDomainStillUsesTrustedDesktopBoundary() {
        val target = StaticAgentConnectorRegistry().availableTargets().first { it.id == "codex" }

        val profile = ProviderProfileCatalog.fromTarget(target)

        assertEquals(AgentResourceLocation.TRUSTED_DESKTOP, profile.location)
        assertEquals(AgentResourceTrust.VERIFIED_PAIRED, profile.trust)
        assertEquals(10, profile.maxParallelRuns)
    }

    @Test
    fun resourceCatalogConsumesProfileInsteadOfGenericCloudDefaults() {
        val profile = ProviderProfileCatalog.fromCloudContact(
            JSONObject()
                .put("id", "cloud:qwen")
                .put("cloud_provider", "Qwen")
                .put("cloud_model", "qwen-test")
                .put("cloud_endpoint", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
                .put("cloud_api_key", "stored"),
            AgentConnectorStatus.AVAILABLE,
            ProviderPerformanceProfile(
                attempts = 10,
                successes = 8,
                failures = 2,
                failureRate = 0.2,
                ewmaLatencyMs = 1_100.0
            )
        )
        val target = AgentCallableTarget(
            id = "cloud:qwen",
            title = "Qwen",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = profile.capabilities.toList(),
            providerProfile = profile
        )

        val resource = AgentResourceCatalog.build(listOf(target), emptyList()).single()

        assertEquals(profile.contextWindowTokens, resource.contextWindowTokens)
        assertEquals(profile.pricing.tier, resource.cost)
        assertEquals(profile.latency, resource.latency)
        assertEquals(0.2, resource.providerProfile?.performance?.failureRate ?: -1.0, 0.0001)
    }
}
