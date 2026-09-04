package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentIdentityPresentationTest {
    @Test
    fun preservesOperationalMetadataAndUsesDeterministicCapabilityPriority() {
        val presentation = AgentIdentityPresenter.present(
            registration(
                agentId = "desktop:codex",
                name = "Codex",
                capabilities = setOf(
                    AgentCapability.CHAT,
                    AgentCapability.TOOL_USE,
                    AgentCapability.CODE,
                    AgentCapability.REASONING
                ),
                cost = AgentResourceCost.LOW,
                latency = AgentResourceLatency.FAST
            )
        )

        assertEquals(AgentAvatarStyle.CODEX, presentation.avatarStyle)
        assertEquals(
            listOf(
                AgentCapability.CODE,
                AgentCapability.REASONING,
                AgentCapability.TOOL_USE,
                AgentCapability.CHAT
            ),
            presentation.capabilities
        )
        assertEquals(AgentResourceCost.LOW, presentation.cost)
        assertEquals(AgentResourceLatency.FAST, presentation.latency)
    }

    @Test
    fun reportsBusyWhenTheEndpointHasNoRemainingCapacity() {
        val presentation = AgentIdentityPresenter.present(
            registration(
                agentId = "hermes",
                name = "Hermes",
                capabilities = setOf(AgentCapability.RESEARCH),
                activeRuns = 2,
                maxParallelRuns = 2
            )
        )

        assertEquals(AgentAvatarStyle.HERMES, presentation.avatarStyle)
        assertEquals(AgentEndpointStatus.BUSY, presentation.status)
    }

    @Test
    fun distinguishesLocalAndCloudModelAvatars() {
        val local = AgentIdentityPresenter.present(
            registration(
                agentId = "local-llm",
                name = "Local LLM",
                capabilities = setOf(AgentCapability.LOCAL_INFERENCE),
                kind = AgentConnectorKind.MODEL,
                location = AgentResourceLocation.PHONE
            )
        )
        val cloud = AgentIdentityPresenter.present(
            registration(
                agentId = "cloud:openai",
                name = "OpenAI",
                capabilities = setOf(AgentCapability.CHAT),
                kind = AgentConnectorKind.MODEL,
                location = AgentResourceLocation.CLOUD
            )
        )

        assertEquals(AgentAvatarStyle.LOCAL_MODEL, local.avatarStyle)
        assertEquals(AgentAvatarStyle.CLOUD_MODEL, cloud.avatarStyle)
    }

    private fun registration(
        agentId: String,
        name: String,
        capabilities: Set<AgentCapability>,
        kind: AgentConnectorKind = AgentConnectorKind.AGENT,
        location: AgentResourceLocation = AgentResourceLocation.TRUSTED_DESKTOP,
        cost: AgentResourceCost = AgentResourceCost.FREE,
        latency: AgentResourceLatency = AgentResourceLatency.NORMAL,
        activeRuns: Int = 0,
        maxParallelRuns: Int = 1
    ) = AgentRegistration(
        agentId = agentId,
        installationId = "installation",
        deviceId = "device",
        providerId = agentId,
        displayName = name,
        kind = kind,
        location = location,
        status = AgentEndpointStatus.ONLINE,
        capabilities = capabilities,
        protocol = AgentProtocolRange("1", "1", "1"),
        connectionKind = AgentConnectionKind.GALAXYSSI_LINK,
        cost = cost,
        latency = latency,
        activeRuns = activeRuns,
        maxParallelRuns = maxParallelRuns
    )
}
