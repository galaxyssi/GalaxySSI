package com.signalasi.chat

import android.content.Context

enum class AgentModelSelectionMode {
    AUTO,
    MANUAL
}

data class AgentModelSelection(
    val mode: AgentModelSelectionMode = AgentModelSelectionMode.AUTO,
    val targetId: String = "",
    val modelId: String = "",
    val displayName: String = ""
)

object AgentModelSelectionPolicy {
    fun preferredTargetId(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): String {
        if (selection.mode != AgentModelSelectionMode.MANUAL) return ""
        return selection.targetId.trim()
    }

    fun selectedTarget(
        selection: AgentModelSelection,
        targets: List<AgentCallableTarget>
    ): AgentCallableTarget? = preferredTargetId(selection, targets)
        .takeIf(String::isNotBlank)
        ?.let { preferredId -> targets.firstOrNull { it.id == preferredId } }

    fun selectableAgentTargets(targets: List<AgentCallableTarget>): List<AgentCallableTarget> {
        val availableAgents = targets.filter { target ->
            target.kind == AgentConnectorKind.AGENT &&
                AgentConnectorRouteSelector.isDeliverable(target)
        }
        val concreteAgentIds = availableAgents
            .asSequence()
            .filter { ':' in it.id }
            .map { it.id.substringAfterLast(':') }
            .toSet()
        return availableAgents
            .filter { target ->
                ':' in target.id || target.id.substringAfterLast(':') !in concreteAgentIds
            }
            .distinctBy(AgentCallableTarget::id)
    }
}

object AgentExecutionTargetStatusPolicy {
    fun resolveTarget(
        connectorId: String,
        contactId: String,
        targets: List<AgentCallableTarget>
    ): AgentCallableTarget? {
        val identities = listOf(contactId, connectorId)
            .map(String::trim)
            .filter(String::isNotBlank)
        identities.forEach { identity ->
            targets.firstOrNull { it.id == identity }?.let { return it }
        }
        identities.forEach { identity ->
            targets.firstOrNull { target ->
                target.id.endsWith(":$identity") || identity.endsWith(":${target.id}")
            }?.let { return it }
        }
        return null
    }
}

object AgentModelSelectionSettings {
    fun selection(context: Context, conversationId: String): AgentModelSelection {
        val scope = normalizedConversationId(conversationId)
        if (scope.isBlank()) return AgentModelSelection()
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val mode = runCatching {
            AgentModelSelectionMode.valueOf(
                preferences.getString(key(scope, KEY_MODE), AgentModelSelectionMode.AUTO.name).orEmpty()
            )
        }.getOrDefault(AgentModelSelectionMode.AUTO)
        return AgentModelSelection(
            mode = mode,
            targetId = preferences.getString(key(scope, KEY_TARGET_ID), "").orEmpty(),
            modelId = preferences.getString(key(scope, KEY_MODEL_ID), "").orEmpty(),
            displayName = preferences.getString(key(scope, KEY_DISPLAY_NAME), "").orEmpty()
        )
    }

    fun selectAuto(context: Context, conversationId: String) {
        val scope = requireConversationId(conversationId)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(key(scope, KEY_MODE), AgentModelSelectionMode.AUTO.name)
            .remove(key(scope, KEY_TARGET_ID))
            .remove(key(scope, KEY_MODEL_ID))
            .remove(key(scope, KEY_DISPLAY_NAME))
            .apply()
    }

    fun selectManual(
        context: Context,
        conversationId: String,
        targetId: String,
        modelId: String,
        displayName: String
    ) {
        val scope = requireConversationId(conversationId)
        require(targetId.isNotBlank()) { "A model target is required" }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(key(scope, KEY_MODE), AgentModelSelectionMode.MANUAL.name)
            .putString(key(scope, KEY_TARGET_ID), targetId)
            .putString(key(scope, KEY_MODEL_ID), modelId)
            .putString(key(scope, KEY_DISPLAY_NAME), displayName)
            .apply()
    }

    fun clearConversation(context: Context, conversationId: String) {
        val scope = normalizedConversationId(conversationId)
        if (scope.isBlank()) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .remove(key(scope, KEY_MODE))
            .remove(key(scope, KEY_TARGET_ID))
            .remove(key(scope, KEY_MODEL_ID))
            .remove(key(scope, KEY_DISPLAY_NAME))
            .apply()
    }

    fun preferredTargetId(
        context: Context,
        conversationId: String,
        targets: List<AgentCallableTarget>
    ): String = AgentModelSelectionPolicy.preferredTargetId(
        selection(context, conversationId),
        targets
    )

    internal fun conversationPreferenceKey(conversationId: String, field: String): String =
        key(requireConversationId(conversationId), field)

    private fun key(conversationId: String, field: String): String =
        "$KEY_CONVERSATION_PREFIX$conversationId.$field"

    private fun requireConversationId(conversationId: String): String =
        normalizedConversationId(conversationId).also {
            require(it.isNotBlank()) { "A conversation id is required" }
        }

    private fun normalizedConversationId(conversationId: String): String =
        conversationId.trim().take(MAX_CONVERSATION_ID_LENGTH)

    private const val PREFERENCES = "signalasi_agent_model_selection_v2"
    private const val KEY_CONVERSATION_PREFIX = "conversation."
    private const val KEY_MODE = "mode"
    private const val KEY_TARGET_ID = "target_id"
    private const val KEY_MODEL_ID = "model_id"
    private const val KEY_DISPLAY_NAME = "display_name"
    private const val MAX_CONVERSATION_ID_LENGTH = 160
}
