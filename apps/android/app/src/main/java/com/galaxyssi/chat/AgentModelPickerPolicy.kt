package com.galaxyssi.chat

internal enum class AgentModelPickerSource {
    DESKTOP, CLOUD, LOCAL
}

internal object AgentModelPickerPolicy {
    private val olderCodexIds = setOf(
        "gpt-6-astra", "gpt-6-sol", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"
    )
    private val olderClaudeIds = setOf(
        "claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"
    )

    fun desktopTargets(targets: List<AgentCallableTarget>, selectedId: String): List<AgentCallableTarget> =
        AgentModelSelectionPolicy.selectableAgentTargets(targets).sortedBy {
            when {
                it.id == selectedId -> 0
                it.id.substringAfterLast(':') == "codex" -> 1
                else -> 2
            }
        }

    fun cloudTargets(targets: List<AgentCallableTarget>): List<AgentCallableTarget> = targets.filter {
        it.kind == AgentConnectorKind.MODEL && it.status == AgentConnectorStatus.AVAILABLE &&
            it.id != "local-llm" && it.id != "cloud-models" && !it.providerProfile?.modelId.isNullOrBlank()
    }.distinctBy(AgentCallableTarget::id)

    fun modelGroups(
        target: AgentCallableTarget,
        selectedModelId: String
    ): Pair<List<AgentModelOption>, List<AgentModelOption>> {
        val profile = target.invocationProfile
        val models = profile.models.filterNot { RetiredAgentModelPolicy.isRetired(it.id) }
        val selected = profile.modelAliases[selectedModelId] ?: selectedModelId
        val olderIds = if (target.kind == AgentConnectorKind.AGENT) {
            when (target.id.substringAfterLast(':')) {
                "codex" -> olderCodexIds
                "claude" -> olderClaudeIds
                else -> emptySet()
            }
        } else emptySet()
        val (visible, folded) = models.partition { it.id == selected || it.id !in olderIds }
        return if (visible.isEmpty()) models to emptyList() else visible to folded
    }

    fun desktopLabel(title: String): Pair<String, String> =
        title.substringBefore(" \u00b7 ") to title.substringAfter(" \u00b7 ", "")

    fun modelLabel(modelId: String): String? =
        modelId.takeIf { it.startsWith("gpt-") }?.removePrefix("gpt-")
            ?.split('-')?.joinToString(" ") { part -> part.replaceFirstChar { it.uppercaseChar() } }
            ?.let { "GPT-$it" }
}
