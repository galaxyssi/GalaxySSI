package com.galaxyssi.chat

import android.content.Context

internal enum class ScreenAssistantBubbleTap { DISMISS_PROMPT, COLLAPSE, SHOW_PROGRESS, ANALYZE }

internal object ScreenAssistantBubbleTapPolicy {
    fun action(promptOpen: Boolean, panelOpen: Boolean, running: Boolean): ScreenAssistantBubbleTap = when {
        promptOpen -> ScreenAssistantBubbleTap.DISMISS_PROMPT
        running && panelOpen -> ScreenAssistantBubbleTap.COLLAPSE
        running -> ScreenAssistantBubbleTap.SHOW_PROGRESS
        else -> ScreenAssistantBubbleTap.ANALYZE
    }
}

internal data class ScreenAssistantHomeRoute(
    val selection: AgentModelSelection,
    val autoTargetId: String = ""
) {
    val manualTargetId: String get() = selection.targetId.takeIf {
        selection.mode == AgentModelSelectionMode.MANUAL
    }.orEmpty()
}

internal object ScreenAssistantHomeRouting {
    fun capture(context: Context, sourceConversationId: String, targets: List<AgentCallableTarget>): ScreenAssistantHomeRoute {
        val selection = AgentModelSelectionSettings.selection(context, sourceConversationId)
        val autoTarget = if (selection.mode == AgentModelSelectionMode.AUTO) {
            AgentStableAutoRouteStore.target(context, sourceConversationId, targets)?.id.orEmpty()
        } else ""
        return ScreenAssistantHomeRoute(selection, autoTarget)
    }

    fun apply(context: Context, conversationId: String, route: ScreenAssistantHomeRoute) {
        val selection = route.selection
        if (selection.mode == AgentModelSelectionMode.MANUAL) {
            AgentModelSelectionSettings.selectManual(context, conversationId, selection.targetId,
                selection.modelId, selection.displayName, selection.reasoningEffort, rememberAsDefault = false)
        } else {
            AgentModelSelectionSettings.selectAutoForConversation(context, conversationId)
            AgentStableAutoRouteStore.inheritPreferredTarget(context, conversationId, route.autoTargetId)
        }
    }
}
