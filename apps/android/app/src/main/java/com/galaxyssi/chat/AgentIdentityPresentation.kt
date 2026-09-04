package com.galaxyssi.chat

enum class AgentAvatarStyle {
    CODEX,
    CLAUDE,
    HERMES,
    OPENCLAW,
    LOCAL_MODEL,
    CLOUD_MODEL,
    DEVICE,
    GENERIC
}

data class AgentIdentityPresentation(
    val agentId: String,
    val displayName: String,
    val avatarStyle: AgentAvatarStyle,
    val status: AgentEndpointStatus,
    val capabilities: List<AgentCapability>,
    val cost: AgentResourceCost,
    val latency: AgentResourceLatency,
    val location: AgentResourceLocation
)

object AgentIdentityPresenter {
    private val capabilityPriority = listOf(
        AgentCapability.CODE,
        AgentCapability.REASONING,
        AgentCapability.RESEARCH,
        AgentCapability.LIVE_DATA,
        AgentCapability.TASK_EXECUTION,
        AgentCapability.TOOL_USE,
        AgentCapability.MCP,
        AgentCapability.SKILL,
        AgentCapability.LOCAL_INFERENCE,
        AgentCapability.KNOWLEDGE_SEARCH,
        AgentCapability.DEVICE_CONTROL,
        AgentCapability.SMART_HOME,
        AgentCapability.CHAT,
        AgentCapability.SCREEN_READING,
        AgentCapability.APP_NAVIGATION,
        AgentCapability.SYSTEM_SETTINGS,
        AgentCapability.CLIPBOARD,
        AgentCapability.ALARM
    ).withIndex().associate { (index, capability) -> capability to index }

    fun present(registration: AgentRegistration): AgentIdentityPresentation {
        val effectiveStatus = if (
            !registration.hasCapacity &&
            registration.status in setOf(AgentEndpointStatus.ONLINE, AgentEndpointStatus.IDLE)
        ) {
            AgentEndpointStatus.BUSY
        } else {
            registration.status
        }
        val capabilities = registration.capabilities.sortedWith(
            compareBy<AgentCapability> { capabilityPriority[it] ?: Int.MAX_VALUE }
                .thenBy(AgentCapability::name)
        )
        return AgentIdentityPresentation(
            agentId = registration.agentId,
            displayName = registration.displayName,
            avatarStyle = avatarStyle(registration),
            status = effectiveStatus,
            capabilities = capabilities,
            cost = registration.cost,
            latency = registration.latency,
            location = registration.location
        )
    }

    private fun avatarStyle(registration: AgentRegistration): AgentAvatarStyle {
        val identity = listOf(
            registration.agentId,
            registration.providerId,
            registration.displayName,
            registration.adapterType
        ).joinToString(" ").lowercase()
        return when {
            "codex" in identity -> AgentAvatarStyle.CODEX
            "claude" in identity || "anthropic" in identity -> AgentAvatarStyle.CLAUDE
            "hermes" in identity -> AgentAvatarStyle.HERMES
            "openclaw" in identity -> AgentAvatarStyle.OPENCLAW
            registration.kind == AgentConnectorKind.DEVICE -> AgentAvatarStyle.DEVICE
            registration.kind == AgentConnectorKind.MODEL &&
                registration.location == AgentResourceLocation.PHONE -> AgentAvatarStyle.LOCAL_MODEL
            registration.kind == AgentConnectorKind.MODEL -> AgentAvatarStyle.CLOUD_MODEL
            else -> AgentAvatarStyle.GENERIC
        }
    }
}
